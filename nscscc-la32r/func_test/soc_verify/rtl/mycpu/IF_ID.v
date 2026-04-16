`timescale 1ns / 1ps

`include "defines.vh"

module IF_ID (
    input  wire         cpu_clk ,
    input  wire         cpu_rstn,
    input  wire         suspend ,
    input  wire         pred_error,

    input  wire         valid_in,
    input  wire [31:0]  pc_in   ,
    output reg          valid_out,
    output reg  [31:0]  pc_out  
);

    always @(posedge cpu_clk) begin
        valid_out <= !cpu_rstn || pred_error ? 1'b0 : (suspend) ? valid_out : valid_in;
        pc_out    <= !cpu_rstn || pred_error ? 32'h0 : (suspend) ? pc_out : pc_in;
    end

endmodule
