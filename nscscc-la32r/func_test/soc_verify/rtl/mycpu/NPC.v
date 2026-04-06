`timescale 1ns / 1ps

`include "defines.vh"

module NPC (
    input  wire         cpu_clk ,
    input  wire         cpu_rstn,
    input  wire         id_valid,
    input  wire         ex_valid,
    input  wire [ 1:0]  npc_op  , //决定采用什么方式计算下一条指令的地址，顺序、B、J等
    input  wire [31:0]  ex_pc   ,
    input  wire [31:0]  rj      , //jirl指令需要rj(ifetch_inst[9:5])+imm
    input  wire [31:0]  offset  , //计算分支目标地址的imm
    input  wire         br      , //是否发生分支
    output reg  [31:0]  npc     
);

    wire [31:0] pc4 = ex_pc + 32'h4 ;
    wire [31:0] B16 = ex_pc + offset;
    wire [31:0] J16 = rj    + offset;
    wire [31:0] B26 = ex_pc + offset;

    always @(*) begin
        case (npc_op)
            `NPC_PC4 : npc = pc4;
            `NPC_B16 : npc = br ? B16 : pc4;
            `NPC_J   : npc = br ? J16 : pc4;
            `NPC_B26 : npc = br ? B26 : pc4;
            default  : npc = pc4;
        endcase
    end

endmodule
