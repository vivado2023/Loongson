`timescale 1ns / 1ps

`include "defines.vh"

module RF (
    input  wire         cpu_clk,
    input  wire [ 4:0]  rR1_1    ,//读地址1
    input  wire [ 4:0]  rR2_1    ,//读地址2
    input  wire [ 4:0]  rR1_2    ,//读地址1
    input  wire [ 4:0]  rR2_2    ,//读地址2

    input  wire         we1     ,//写使能
    input  wire [ 4:0]  wR1     ,//写地址
    input  wire [31:0]  wD1     ,//写数据
    input  wire         we2     ,//写使能
    input  wire [ 4:0]  wR2     ,//写地址
    input  wire [31:0]  wD2     ,//写数据

    output wire [31:0]  rD1_1    ,//读数据1
    output wire [31:0]  rD2_1    ,//读数据2
    output wire [31:0]  rD1_2    ,//读数据1
    output wire [31:0]  rD2_2    //读数据2
);

    reg [31:0] r [1:31];

    always @(posedge cpu_clk) begin
        if (we1 & (wR1 != 5'h0)) r[wR1] <= wD1;
        if (we2 & (wR2 != 5'h0)) r[wR2] <= wD2;
    end

    assign rD1_1 = (rR1_1 == 5'h0) ? 32'h0 : r[rR1_1];
    assign rD2_1 = (rR2_1 == 5'h0) ? 32'h0 : r[rR2_1];
    assign rD1_2 = (rR1_2 == 5'h0) ? 32'h0 : r[rR1_2];
    assign rD2_2 = (rR2_2 == 5'h0) ? 32'h0 : r[rR2_2];

endmodule
