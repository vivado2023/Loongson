`timescale 1ns / 1ps

`include "defines.vh"

`define BHT_IDX_W 10                    // 表索引位宽
`define BHT_ENTRY (1 << `BHT_IDX_W)     // 表项个数
`define BHT_TAG_W 8                     // tag字段位宽

module BPU (
    input  wire         cpu_clk       ,
    input  wire         cpu_rstn      ,
    input  wire [31:0]  if_pc         , // IF阶段的PC值

    input  wire         mem_valid1     , // MEM阶段的有效信号
    input  wire         mem_is_bj1     , // MEM1阶段是否是条件分支或直接跳转指令
    input  wire [31:0]  mem_pc1        , // MEM1阶段的PC值
    input  wire         mem_valid2     , // MEM2阶段的有效信号
    input  wire         mem_is_bj2     , // MEM2阶段是否是条件分支或直接跳转指令
    input  wire [31:0]  mem_pc2        , // MEM2阶段的PC值

    input  wire         real_taken1    , // MEM1阶段指令实际是否发生跳转
    input  wire [31:0]  real_target1   , // MEM1阶段指令发生跳转时的目标地址
    input  wire         real_taken2    , // MEM2阶段指令实际是否发生跳转
    input  wire [31:0]  real_target2   , // MEM2阶段指令发生跳转时的目标地址

    output wire         pred_taken_sel, // 预测跳转的是哪条指令，1表示if_pc1跳转，否则为0
    output wire [31:0]  pred_target   , // 预测的下一条指令地址
    output wire         pred_error    , // 预测是否错误
    output wire         error_from1   , // 预测错误是否来自if_pc1
    output wire [31:0]  real_npc       // 实际的下一条指令地址（无论预测是否正确，都提供给IF阶段以便取指）
);

`ifdef ENABLE_BPU

    reg [`BHT_TAG_W-1:0] tag [`BHT_ENTRY-1:0]; 
    reg [`BHT_ENTRY-1:0] valid; 
    reg [ 1:0]          history [`BHT_ENTRY-1:0]; 
    reg [ 31:0]         target [`BHT_ENTRY-1:0];

    wire [31:0] if_pc1 = if_pc        ;
    wire [31:0] if_pc2 = if_pc + 32'h4;

    wire [`BHT_TAG_W-1:0] if_tag1 = if_pc1[19:12];
    wire [`BHT_TAG_W-1:0] if_tag2 = if_pc2[19:12];
    wire [`BHT_TAG_W-1:0] mem_tag1 = mem_pc1[19:12];
    wire [`BHT_TAG_W-1:0] mem_tag2 = mem_pc2[19:12];

    // if阶段预测
    wire [          31:0] pc_hash1 = if_pc1[19:0] ^ (if_pc1[19:0] >> 5) ^ (if_pc1[19:0] >> 11);
    wire [          31:0] pc_hash2 = if_pc2[19:0] ^ (if_pc2[19:0] >> 5) ^ (if_pc2[19:0] >> 11);

    wire [`BHT_IDX_W-1:0] index1   = pc_hash1[`BHT_IDX_W-1:0];
    wire [`BHT_IDX_W-1:0] index2   = pc_hash2[`BHT_IDX_W-1:0];

    wire   pred_taken1 = valid[index1] && (tag[index1] == if_tag1) && history[index1][1];
    wire   pred_taken2 = valid[index2] && (tag[index2] == if_tag2) && history[index2][1];

    assign pred_taken_sel = pred_taken1;
    
    // 优先预测if_pc1，如果if_pc1不跳再预测if_pc2，如果if_pc2也不跳则预测顺序执行
    assign pred_target = pred_taken1 ? target[index1] : (pred_taken2 ? target[index2] : (if_pc + 32'h8));

    // mem阶段还原预测内容
    wire [         31:0]  mem_hash1  = mem_pc1[19:0] ^ (mem_pc1[19:0] >> 5) ^ (mem_pc1[19:0] >> 11); // 地址折叠
    wire [         31:0]  mem_hash2  = mem_pc2[19:0] ^ (mem_pc2[19:0] >> 5) ^ (mem_pc2[19:0] >> 11); // 地址折叠
    wire [`BHT_IDX_W-1:0] mem_index1 = mem_hash1[`BHT_IDX_W-1:0]; // 表索引
    wire [`BHT_IDX_W-1:0] mem_index2 = mem_hash2[`BHT_IDX_W-1:0]; // 表索引

    wire   mem_pred_taken1 = valid[mem_index1] && (tag[mem_index1] == mem_tag1) && history[mem_index1][1]; // 生成预测跳转方向
    wire   mem_pred_taken2 = valid[mem_index2] && (tag[mem_index2] == mem_tag2) && history[mem_index2][1]; // 生成预测跳转方向
    assign mem_pred_target1 = mem_pred_taken1 ? target[mem_index1] : (mem_pc1 + 32'h4); // 生成预测跳转的目标地址
    assign mem_pred_target2 = mem_pred_taken2 ? target[mem_index2] : (mem_pc2 + 32'h4); // 生成预测跳转的目标地址


    wire taken_error1  = (mem_pred_taken1 && !real_taken1) | (!mem_pred_taken1 && real_taken1);
    wire taken_error2  = (mem_pred_taken2 && !real_taken2) | (!mem_pred_taken2 && real_taken2);

    wire target_error1 = mem_pred_taken1 && real_taken1 && (mem_pred_target1 != real_target1);
    wire target_error2 = mem_pred_taken2 && real_taken2 && (mem_pred_target2 != real_target2);

    wire pred_error1 = mem_valid1 & (taken_error1 | target_error1);
    wire pred_error2 = mem_valid2 & (taken_error2 | target_error2);

    assign error_from1 = pred_error1;
    assign pred_error = pred_error1 | pred_error2;

    assign real_npc = pred_error1 ? real_target1 : (pred_error2 ? real_target2 : (if_pc + 32'h8));

    wire add_entry1     = mem_valid1 & mem_is_bj1 & real_taken1 & !(valid[mem_index1] && (tag[mem_index1] == mem_tag1)); 
    wire add_entry2     = mem_valid2 & mem_is_bj2 & real_taken2 & !(valid[mem_index2] && (tag[mem_index2] == mem_tag2)); 

    wire update_entry1  = mem_valid1 & mem_is_bj1 & (valid[mem_index1] && (tag[mem_index1] == mem_tag1)); 
    wire update_entry2  = mem_valid2 & mem_is_bj2 & (valid[mem_index2] && (tag[mem_index2] == mem_tag2)); 
    wire replace_entry = 1'b0;

    integer i; 
    always @(posedge cpu_clk or negedge cpu_rstn) begin 
        if (!cpu_rstn) begin 
            valid <= {`BHT_ENTRY{1'b0}}; 
            for (i = 0; i < `BHT_ENTRY; i = i + 1) history[i] <= 2'b10; 
        end 
        else begin 
            if (add_entry1) begin 
                valid[mem_index1] <= 1'b1; 
                tag[mem_index1]   <= mem_tag1; 

                if (real_taken1) target[mem_index1] <= real_target1; 

                history[mem_index1] <= real_taken1 ? 2'b10 : 2'b01; 
            end 
            else if (add_entry2) begin 
                valid[mem_index2] <= 1'b1; 
                tag[mem_index2]   <= mem_tag2; 

                if (real_taken2) target[mem_index2] <= real_target2; 

                history[mem_index2] <= real_taken2 ? 2'b10 : 2'b01; 
            end
            else if (update_entry1) begin 
                if (real_taken1) target[mem_index1] <= real_target1; 

                case (history[mem_index1]) 
                    2'b00: history[mem_index1] <= real_taken1 ? 2'b01 : 2'b00; 
                    2'b01: history[mem_index1] <= real_taken1 ? 2'b10 : 2'b00; 
                    2'b10: history[mem_index1] <= real_taken1 ? 2'b11 : 2'b01; 
                    2'b11: history[mem_index1] <= real_taken1 ? 2'b11 : 2'b10; 
                endcase
            end
            else if (update_entry2) begin 
                if (real_taken2) target[mem_index2] <= real_target2; 

                case (history[mem_index2]) 
                    2'b00: history[mem_index2] <= real_taken2 ? 2'b01 : 2'b00; 
                    2'b01: history[mem_index2] <= real_taken2 ? 2'b10 : 2'b00; 
                    2'b10: history[mem_index2] <= real_taken2 ? 2'b11 : 2'b01; 
                    2'b11: history[mem_index2] <= real_taken2 ? 2'b11 : 2'b10; 
                endcase
            end 
        end 
    end

`else

    assign pred_target = if_pc + 32'h4;

    wire taken_error  = mem_is_bj & real_taken;
    wire target_error = 1'b0;
    assign pred_error = mem_valid & (taken_error | target_error);

`endif

endmodule