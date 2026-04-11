`timescale 1ns / 1ps

`include "defines.vh"

`define REG_LEN  4

module Ififo(
    input  wire         cpu_rstn      ,
    input  wire         cpu_clk       ,

    input  wire [31:0]  inst_in       ,
    input  wire         inst_in_valid ,
    input  wire [31:0]  pc_in         ,
    input  wire         pop_valid     , // 是否要弹出指令
    input  wire         pred_error    , // 分支预测错误

    output reg [31:0]   inst_out      ,
    output reg          inst_out_valid,
    output reg [31:0]   pc_out        ,
    output wire         full
);

    reg [63:0] fifo_reg [`REG_LEN-1:0]; // 32位指令+32位PC
    reg [1:0] front;    // 指向当前要输出的指令
    reg [1:0] rear;     // 指向下一个要写入指令的位置
    reg [2:0] cnt;      // 当前指令数量
    
    wire num_push = inst_in_valid && !full;
    wire num_pop  = !inst_out_valid && cnt > 0 && !pred_error;

    assign full = (cnt == `REG_LEN);

    integer i;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) begin
            for(i = 0; i < `REG_LEN; i = i + 1) begin
                fifo_reg[i] <= 64'b0;
            end
        end
        else begin
            if(pred_error) begin
                for(i = 0; i < `REG_LEN; i = i + 1) begin
                    fifo_reg[i] <= 64'b0;
                end
            end
            else if(inst_in_valid && !full)  fifo_reg[rear] <= {inst_in, pc_in};
        end
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) begin
            inst_out       <= 32'b0;
            inst_out_valid <= 1'b0;
            pc_out         <= 32'b0;
        end
        else if(pred_error) begin
            inst_out       <= 32'b0;
            inst_out_valid <= 1'b0;
            pc_out         <= 32'b0;
        end
        else if (pop_valid) begin
            inst_out_valid <= 1'b0;
        end
        else if (!inst_out_valid && cnt > 0 && !pred_error) begin
            inst_out       <= fifo_reg[front][63:32];
            inst_out_valid <= 1'b1;
            pc_out         <= fifo_reg[front][31:0];
        end
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        front <= (!cpu_rstn || pred_error) ? 2'b0 : front + num_pop;
        rear  <= (!cpu_rstn || pred_error) ? 2'b0 : rear + num_push;
        cnt   <= (!cpu_rstn || pred_error) ? 2'b0 : cnt + num_push - num_pop;
    end


endmodule
