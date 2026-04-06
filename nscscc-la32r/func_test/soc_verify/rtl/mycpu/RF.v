`timescale 1ns / 1ps

`include "defines.vh"

module RF (
    input  wire         cpu_clk,
    input  wire [ 4:0]  rR1    ,//读地址1
    input  wire [ 4:0]  rR2    ,//读地址2
    input  wire         we     ,//写使能
    input  wire [ 4:0]  wR     ,//写地址
    input  wire [31:0]  wD     ,//写数据
    output wire [31:0]  rD1    ,//读数据1
    output wire [31:0]  rD2     //读数据2
);

    reg [31:0] r [1:31];

    always @(posedge cpu_clk) begin
        if (we & (wR != 5'h0)) r[wR] <= wD;
    end

    assign rD1 = (rR1 == 5'h0) ? 32'h0 : r[rR1];
    assign rD2 = (rR2 == 5'h0) ? 32'h0 : r[rR2];

endmodule
