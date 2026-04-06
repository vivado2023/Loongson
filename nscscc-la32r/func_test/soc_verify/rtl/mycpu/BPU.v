`timescale 1ns / 1ps

`include "defines.vh"

`define BHT_IDX_W 10                    // 表索引位宽
`define BHT_ENTRY (1 << `BHT_IDX_W)     // 表项个数
`define BHT_TAG_W 8                     // tag字段位宽

module BPU (
    input  wire         cpu_clk    ,
    input  wire         cpu_rstn   ,
    input  wire [31:0]  if_pc      ,    // IF阶段的PC值
    input  wire         if_valid   ,    // IF阶段的有效信号
    input  wire         id_valid   ,    // ID阶段的有效信号
    input  wire         pl_suspend ,    // 流水线暂停信号
    // predict branch direction and target
    output wire [31:0]  pred_target,    // 预测的下一条指令地址
    output wire         pred_error ,    // 预测是否错误
    // signals to correct BHT
    input  wire         ex_valid   ,    // EX阶段的有效信号
    input  wire         ex_is_bj   ,    // EX阶段是否是条件分支或直接跳转指令
    input  wire [31:0]  ex_pc      ,    // EX阶段的PC值
    input  wire         real_taken ,    // EX阶段指令实际是否发生跳转
    input  wire [31:0]  real_target     // EX阶段指令发生跳转时的目标地址
);

`ifdef ENABLE_BPU

    // BHT
    reg  [`BHT_TAG_W-1:0] tag     [`BHT_ENTRY-1:0][1:0];
    reg                   valid   [`BHT_ENTRY-1:0][1:0];
    reg  [1:0]            history [`BHT_ENTRY-1:0][1:0];
    reg  [31:0]           target  [`BHT_ENTRY-1:0][1:0];
    reg                   lru     [`BHT_ENTRY-1:0];

    wire [`BHT_TAG_W-1:0] if_tag = if_pc[19:12];      // IF阶段指令地址标签
    wire [`BHT_TAG_W-1:0] ex_tag = ex_pc[19:12];      // EX阶段指令地址标签

    wire [          31:0] pc_hash = if_pc[19:0] ^ (if_pc[19:0] >> 5) ^ (if_pc[19:0] >> 11);  // 地址折叠
    wire [`BHT_IDX_W-1:0] index   = pc_hash[`BHT_IDX_W-1:0];    // 表索引

    wire hit0 = valid[index][0] && (tag[index][0] == if_tag);
    wire hit1 = valid[index][1] && (tag[index][1] == if_tag);
    wire hit  = hit0 | hit1;

    wire sel = hit0 ? 1'b0 : hit1 ? 1'b1 : lru[index];

    wire pred_taken = hit && history[index][sel][1];                        // 生成预测跳转方向
    assign pred_target = pred_taken ? target[index][sel] : (if_pc + 32'h4); // 生成预测跳转的目标地址

    // EX阶段才能判断分支跳转是否错误，故需把IF阶段的预测信号传递到EX阶段
    reg  [`BHT_IDX_W-1:0] id_index      , ex_index      ;
    reg                   id_sel        , ex_sel        ;
    reg                   id_pred_taken , ex_pred_taken ;
    reg  [          31:0] id_pred_target, ex_pred_target;
    always @(posedge cpu_clk or negedge cpu_rstn) begin 
        id_index       <= !cpu_rstn ? 'h0 : (if_valid & !pl_suspend ? index        : id_index);
        id_sel         <= !cpu_rstn ? 'h0 : (if_valid & !pl_suspend ? sel          : id_sel);
        id_pred_taken  <= !cpu_rstn ? 'h0 : (if_valid & !pl_suspend ? pred_taken   : id_pred_taken);
        id_pred_target <= !cpu_rstn ? 'h0 : (if_valid & !pl_suspend ? pred_target  : id_pred_target);

        ex_index       <= !cpu_rstn ? 'h0 : (id_valid & !pl_suspend ? id_index        : ex_index);
        ex_sel         <= !cpu_rstn ? 'h0 : (id_valid & !pl_suspend ? id_sel          : ex_sel);
        ex_pred_taken  <= !cpu_rstn ? 'h0 : (id_valid & !pl_suspend ? id_pred_taken   : ex_pred_taken);
        ex_pred_target <= !cpu_rstn ? 'h0 : (id_valid & !pl_suspend ? id_pred_target  : ex_pred_target);
    end

    wire taken_error  = (ex_pred_taken && !real_taken) |   // 情形1：预测跳但没跳
                        (!ex_pred_taken && real_taken);    // 情形2：预测不跳但跳了

    wire target_error = ex_pred_taken && real_taken && (ex_pred_target != real_target);
    
    assign pred_error = ex_valid & (taken_error | target_error);

    wire ex_hit0 = valid[ex_index][0] && (tag[ex_index][0] == ex_tag);
    wire ex_hit1 = valid[ex_index][1] && (tag[ex_index][1] == ex_tag);

    wire ex_way = ex_hit0 ? 1'b0 : ex_hit1 ? 1'b1 : lru[ex_index];

    // Update BHT and BTB
    integer i;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            for (i = 0; i < `BHT_ENTRY; i = i + 1) begin
                valid[i][0] <= 0;
                valid[i][1] <= 0;
                history[i][0] <= 2'b10;
                history[i][1] <= 2'b10;
                lru[i] <= 0;
            end
        end else if (ex_valid && ex_is_bj) begin

            // 写入（只对taken）
            if (real_taken) begin
                valid[ex_index][ex_way]  <= 1'b1;
                tag[ex_index][ex_way]    <= ex_tag;
                target[ex_index][ex_way] <= real_target;
            end

            // 更新history
            case (history[ex_index][ex_way])
                2'b00: history[ex_index][ex_way] <= real_taken ? 2'b01 : 2'b00;
                2'b01: history[ex_index][ex_way] <= real_taken ? 2'b10 : 2'b00;
                2'b10: history[ex_index][ex_way] <= real_taken ? 2'b11 : 2'b01;
                2'b11: history[ex_index][ex_way] <= real_taken ? 2'b11 : 2'b10;
            endcase

            // 更新LRU
            lru[ex_index] <= ~ex_way;
        end
    end

`else

    assign pred_target = if_pc + 32'h4;

    wire taken_error  = ex_is_bj & real_taken;
    wire target_error = 1'b0;
    assign pred_error = ex_valid & (taken_error | target_error);

`endif

endmodule