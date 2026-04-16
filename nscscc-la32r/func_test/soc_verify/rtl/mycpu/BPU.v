`timescale 1ns / 1ps

`include "defines.vh"

`define BHT_IDX_W 5                    // 表索引位宽
`define BHT_ENTRY (1 << `BHT_IDX_W)     // 表项个数
`define BHT_TAG_W 8                     // tag字段位宽

module BPU (
    input  wire         cpu_clk    ,
    input  wire         cpu_rstn   ,
    input  wire [31:0]  if_pc      ,    // IF阶段的PC值
    // predict branch direction and target
    output wire [31:0]  pred_target,    // 预测的下一条指令地址
    output wire         pred_error ,    // 预测是否错误
    // signals to correct BHT
    input  wire         mem_valid   ,    // MEM阶段的有效信号
    input  wire         mem_is_bj   ,    // MEM阶段是否是条件分支或直接跳转指令
    input  wire [31:0]  mem_pc      ,    // MEM阶段的PC值
    input  wire         real_taken ,    // MEM阶段指令实际是否发生跳转
    input  wire [31:0]  real_target     // MEM阶段指令发生跳转时的目标地址
);

`ifdef ENABLE_BPU

    reg [`BHT_TAG_W-1:0] tag [`BHT_ENTRY-1:0]; 
    reg [`BHT_ENTRY-1:0] valid; 
    reg [ 1:0]          history [`BHT_ENTRY-1:0]; 
    reg [ 31:0]         target [`BHT_ENTRY-1:0];

    wire [`BHT_TAG_W-1:0] if_tag = if_pc[19:12]; // IF阶段指令地址标签 
    wire [`BHT_TAG_W-1:0] mem_tag = mem_pc[19:12]; // MEM阶段指令地址标签

    // if阶段预测
    wire [         31:0]  pc_hash = if_pc[19:0] ^ (if_pc[19:0] >> 5) ^ (if_pc[19:0] >> 11); // 地址折叠
    wire [`BHT_IDX_W-1:0] index   = pc_hash[`BHT_IDX_W-1:0]; // 表索引

    wire   pred_taken = valid[index] && (tag[index] == if_tag) && history[index][1]; // 生成预测跳转方向
    assign pred_target = pred_taken ? target[index] : (if_pc + 32'h4); // 生成预测跳转的目标地址

    // mem阶段还原预测内容
    wire [         31:0]  mem_hash  = mem_pc[19:0] ^ (mem_pc[19:0] >> 5) ^ (mem_pc[19:0] >> 11); // 地址折叠
    wire [`BHT_IDX_W-1:0] mem_index = mem_hash[`BHT_IDX_W-1:0]; // 表索引

    wire   mem_pred_taken = valid[mem_index] && (tag[mem_index] == mem_tag) && history[mem_index][1]; // 生成预测跳转方向
    assign mem_pred_target = mem_pred_taken ? target[mem_index] : (mem_pc + 32'h4); // 生成预测跳转的目标地址


    wire taken_error  = (mem_pred_taken && !real_taken) |   // 情形1：预测跳但没跳
                        (!mem_pred_taken && real_taken);    // 情形2：预测不跳但跳了

    wire target_error = mem_pred_taken && real_taken && (mem_pred_target != real_target);
    
    assign pred_error = mem_valid & (taken_error | target_error);

    wire add_entry     = mem_valid & mem_is_bj & real_taken & !(valid[mem_index] && (tag[mem_index] == mem_tag)); 
    wire update_entry  = mem_valid & mem_is_bj & (valid[mem_index] && (tag[mem_index] == mem_tag)); 
    wire replace_entry = 1'b0;

    integer i; 
    always @(posedge cpu_clk or negedge cpu_rstn) begin 
        if (!cpu_rstn) begin 
            valid <= {`BHT_ENTRY{1'b0}}; 
            for (i = 0; i < `BHT_ENTRY; i = i + 1) history[i] <= 2'b10; 
        end 
        else begin 
            if (add_entry) begin 
                valid[mem_index] <= 1'b1; 
                tag[mem_index]   <= mem_tag; 

                if (real_taken) target[mem_index] <= real_target; 

                history[mem_index] <= real_taken ? 2'b10 : 2'b01; 
            end 
            else if (update_entry) begin 
                if (real_taken) target[mem_index] <= real_target; 

                case (history[mem_index]) 
                    2'b00: history[mem_index] <= real_taken ? 2'b01 : 2'b00; 
                    2'b01: history[mem_index] <= real_taken ? 2'b10 : 2'b00; 
                    2'b10: history[mem_index] <= real_taken ? 2'b11 : 2'b01; 
                    2'b11: history[mem_index] <= real_taken ? 2'b11 : 2'b10; 
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