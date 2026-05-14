`timescale 1ns / 1ps

`include "defines.vh"

`define REG_LEN  4

module Ififo(
    input  wire         cpu_rstn       ,
    input  wire         cpu_clk        ,

    input  wire [63:0]  inst_in        ,
    input  wire [ 1:0]  inst_in_valid  ,
    input  wire [31:0]  pc_in          ,
    input  wire         pop_valid1     ,
    input  wire         pop_valid2     ,
    input  wire         pred_error     ,

    output reg [31:0]   inst_out1      ,
    output reg [31:0]   inst_out2      ,
    output reg          inst_out_valid1,
    output reg          inst_out_valid2,

    output reg [31:0]   pc_out1        ,
    output reg [31:0]   pc_out2        ,
    output wire         spaceless         
);

    reg [2:0] cnt; // FIFO中指令的数量，范围0~4
    assign spaceless = (inst_in_valid == 2'b11) && (cnt >= (`REG_LEN - 1)) || 
                       (inst_in_valid == 2'b10) && (cnt == `REG_LEN);

    reg [63:0] fifo_reg [`REG_LEN-1:0]; // {inst[31:0], pc[31:0]}

    reg [1:0] front;
    reg [1:0] rear;

    reg [1:0] push_num;
    always @(*) begin
        case (inst_in_valid)
            2'b00: push_num = 2'd0;
            2'b10: push_num = !spaceless ? 2'd1 : 2'd0;
            2'b11: push_num = !spaceless ? 2'd2 : 2'd0;
            default: push_num = 2'd0;
        endcase
    end

    wire [1:0] pop_num = (next_valid1 && !temp_valid1) + (next_valid2 && !temp_valid2);

    // pop后前端输出寄存器剩余指令缓存
    reg              temp_valid1, temp_valid2;
    reg [31:0]       temp_inst1 , temp_inst2 ;
    reg [31:0]       temp_pc1   , temp_pc2   ;

    // 在从后端reg中取完后前端输出寄存器剩余指令缓存
    reg              next_valid1, next_valid2;
    reg [31:0]       next_inst1 , next_inst2 ;
    reg [31:0]       next_pc1   , next_pc2   ;

    always @(*) begin
        case ({pop_valid1, pop_valid2})
            2'b00: begin
                temp_valid1 = inst_out_valid1; temp_inst1 = inst_out1; temp_pc1 = pc_out1;
                temp_valid2 = inst_out_valid2; temp_inst2 = inst_out2; temp_pc2 = pc_out2;
            end
            2'b10: begin
                temp_valid1 = inst_out_valid2; temp_inst1 = inst_out2; temp_pc1 = pc_out2;
                temp_valid2 = 1'b0;            temp_inst2 = 32'b0;     temp_pc2 = 32'b0;
            end
            2'b11: begin
                temp_valid1 = 1'b0; temp_inst1 = 32'b0; temp_pc1 = 32'b0;
                temp_valid2 = 1'b0; temp_inst2 = 32'b0; temp_pc2 = 32'b0;
            end
            default: ;
        endcase
    end

    always @(*) begin
        next_valid1 = temp_valid1; next_inst1 = temp_inst1; next_pc1 = temp_pc1;
        next_valid2 = temp_valid2; next_inst2 = temp_inst2; next_pc2 = temp_pc2;

        if (!temp_valid1 && (cnt > 0)) begin
            next_valid1 = 1'b1;
            next_inst1  = fifo_reg[front][63:32];
            next_pc1    = fifo_reg[front][31:0];

            if (!temp_valid2 && (cnt > 1)) begin
                next_valid2 = 1'b1;
                next_inst2  = fifo_reg[front + 1'b1][63:32];
                next_pc2    = fifo_reg[front + 1'b1][31:0];
            end
        end
        else if (!temp_valid2 && (cnt > 0)) begin
            next_valid2 = 1'b1;
            next_inst2  = fifo_reg[front][63:32];
            next_pc2    = fifo_reg[front][31:0];
        end
    end

    integer i;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            for (i = 0; i < `REG_LEN; i = i + 1) begin
                fifo_reg[i] <= 64'b0;
            end
        end
        else if (pred_error) begin
            for (i = 0; i < `REG_LEN; i = i + 1) begin
                fifo_reg[i] <= 64'b0;
            end
        end
        else begin
            if(push_num == 2'd1) begin
                fifo_reg[rear]        <= {inst_in[63:32], pc_in};
            end
            else if(push_num == 2'd2) begin
                fifo_reg[rear]        <= {inst_in[63:32], pc_in};
                fifo_reg[rear + 1'b1] <= {inst_in[31:0], pc_in + 32'd4};
            end
        end
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            front <= 2'b0;
            rear  <= 2'b0;
            cnt   <= 3'b0;
        end
        else if (pred_error) begin
            front <= 2'b0;
            rear  <= 2'b0;
            cnt   <= 3'b0;
        end
        else begin
            front <= front + pop_num;
            rear  <= rear  + push_num;
            cnt   <= cnt   + push_num - pop_num;
        end
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            inst_out1       <= 32'b0;
            inst_out2       <= 32'b0;
            inst_out_valid1 <= 1'b0;
            inst_out_valid2 <= 1'b0;
            pc_out1         <= 32'b0;
            pc_out2         <= 32'b0;
        end
        else if (pred_error) begin
            inst_out1       <= 32'b0;
            inst_out2       <= 32'b0;
            inst_out_valid1 <= 1'b0;
            inst_out_valid2 <= 1'b0;
            pc_out1         <= 32'b0;
            pc_out2         <= 32'b0;
        end
        else begin
            inst_out1       <= next_inst1;
            inst_out2       <= next_inst2;
            inst_out_valid1 <= next_valid1;
            inst_out_valid2 <= next_valid2;
            pc_out1         <= next_pc1;
            pc_out2         <= next_pc2;
        end
    end


endmodule