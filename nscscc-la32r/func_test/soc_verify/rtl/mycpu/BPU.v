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

    reg [`BHT_TAG_W-1:0] tag [`BHT_ENTRY-1:0]; 
    reg [`BHT_ENTRY-1:0] valid; 
    reg [ 1:0]          history [`BHT_ENTRY-1:0]; 
    reg [ 31:0]         target [`BHT_ENTRY-1:0];

    wire [`BHT_TAG_W-1:0] if_tag = if_pc[19:12]; // IF阶段指令地址标签 
    wire [`BHT_TAG_W-1:0] ex_tag = ex_pc[19:12]; // EX阶段指令地址标签

    // if阶段预测
    wire [         31:0]  pc_hash = if_pc[19:0] ^ (if_pc[19:0] >> 5) ^ (if_pc[19:0] >> 11); // 地址折叠
    wire [`BHT_IDX_W-1:0] index   = pc_hash[`BHT_IDX_W-1:0]; // 表索引

    wire   pred_taken = valid[index] && (tag[index] == if_tag) && history[index][1]; // 生成预测跳转方向
    assign pred_target = pred_taken ? target[index] : (if_pc + 32'h4); // 生成预测跳转的目标地址

    // ex阶段还原预测内容
    wire [         31:0]  ex_hash  = ex_pc[19:0] ^ (ex_pc[19:0] >> 5) ^ (ex_pc[19:0] >> 11); // 地址折叠
    wire [`BHT_IDX_W-1:0] ex_index = ex_hash[`BHT_IDX_W-1:0]; // 表索引

    wire   ex_pred_taken = valid[ex_index] && (tag[ex_index] == ex_tag) && history[ex_index][1]; // 生成预测跳转方向
    assign ex_pred_target = ex_pred_taken ? target[ex_index] : (ex_pc + 32'h4); // 生成预测跳转的目标地址


    wire taken_error  = (ex_pred_taken && !real_taken) |   // 情形1：预测跳但没跳
                        (!ex_pred_taken && real_taken);    // 情形2：预测不跳但跳了

    wire target_error = ex_pred_taken && real_taken && (ex_pred_target != real_target);
    
    assign pred_error = ex_valid & (taken_error | target_error);

    wire add_entry     = ex_valid & ex_is_bj & real_taken & !(valid[ex_index] && (tag[ex_index] == ex_tag)); 
    wire update_entry  = ex_valid & ex_is_bj & (valid[ex_index] && (tag[ex_index] == ex_tag)); 
    wire replace_entry = 1'b0;

    integer i; 
    always @(posedge cpu_clk or negedge cpu_rstn) begin 
        if (!cpu_rstn) begin 
            valid <= {`BHT_ENTRY{1'b0}}; 
            for (i = 0; i < `BHT_ENTRY; i = i + 1) history[i] <= 2'b10; 
        end 
        else begin 
            if (add_entry) begin 
                valid[ex_index] <= 1'b1; 
                tag[ex_index]   <= ex_tag; 

                if (real_taken) target[ex_index] <= real_target; 

                history[ex_index] <= real_taken ? 2'b10 : 2'b01; 
            end 
            else if (update_entry) begin 
                if (real_taken) target[ex_index] <= real_target; 
                
                case (history[ex_index]) 
                    2'b00: history[ex_index] <= real_taken ? 2'b01 : 2'b00; 
                    2'b01: history[ex_index] <= real_taken ? 2'b10 : 2'b00; 
                    2'b10: history[ex_index] <= real_taken ? 2'b11 : 2'b01; 
                    2'b11: history[ex_index] <= real_taken ? 2'b11 : 2'b10; 
                endcase 
            end 
        end 
    end

`else

    assign pred_target = if_pc + 32'h4;

    wire taken_error  = ex_is_bj & real_taken;
    wire target_error = 1'b0;
    assign pred_error = ex_valid & (taken_error | target_error);

`endif

endmodule