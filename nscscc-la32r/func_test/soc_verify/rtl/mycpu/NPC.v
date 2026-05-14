`timescale 1ns / 1ps

`include "defines.vh"

module NPC (
    input  wire         cpu_clk ,
    input  wire         cpu_rstn,
    input  wire [ 1:0]  npc_op1  , //决定采用什么方式计算下一条指令的地址，顺序、B、J等
    input  wire [31:0]  mem_pc1  ,
    input  wire [31:0]  rj1      , //jirl指令需要rj(ifetch_inst[9:5])+imm
    input  wire [31:0]  offset1  , //计算分支目标地址的imm
    input  wire         br1      , //是否发生分支
    output reg  [31:0]  npc1     ,

    input  wire [ 1:0]  npc_op2  , //决定采用什么方式计算下一条指令的地址，顺序、B、J等
    input  wire [31:0]  mem_pc2  ,     
    input  wire [31:0]  rj2      , //jirl指令需要rj(ifetch_inst[9:5])+imm
    input  wire [31:0]  offset2  , //计算分支目标地址的imm
    input  wire         br2      , //是否发生分支
    output reg  [31:0]  npc2     
);

    wire [31:0] pc8_1 = mem_pc1 + 32'h8 ;
    wire [31:0] B16_1 = mem_pc1 + offset1;
    wire [31:0] J16_1 = rj1    + offset1;
    wire [31:0] B26_1 = mem_pc1 + offset1;

    wire [31:0] pc8_2 = mem_pc2 + 32'h8 ;
    wire [31:0] B16_2 = mem_pc2 + offset2;
    wire [31:0] J16_2 = rj2    + offset2;
    wire [31:0] B26_2 = mem_pc2 + offset2;

    always @(*) begin
        case (npc_op1)
            `NPC_PC8 : npc1 = pc8_1;
            `NPC_B16 : npc1 = br1 ? B16_1 : pc8_1;
            `NPC_J   : npc1 = br1 ? J16_1 : pc8_1;
            `NPC_B26 : npc1 = br1 ? B26_1 : pc8_1;
            default  : npc1 = pc8_1;
        endcase
    end

    always @(*) begin
        case (npc_op2)
            `NPC_PC8 : npc2 = pc8_2;
            `NPC_B16 : npc2 = br2 ? B16_2 : pc8_2;
            `NPC_J   : npc2 = br2 ? J16_2 : pc8_2;
            `NPC_B26 : npc2 = br2 ? B26_2 : pc8_2;
            default  : npc2 = pc8_2;
        endcase
    end



endmodule
