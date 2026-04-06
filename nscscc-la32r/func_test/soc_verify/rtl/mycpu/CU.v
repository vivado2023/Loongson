`timescale 1ns / 1ps

`include "mycpu_inst.vh"
`include "defines.vh"

module CU (
    input  wire [31:15] inst_31_15,
    output wire [ 1: 0] npc_op    ,
    output wire         is_br_jmp ,
    output wire [ 2: 0] ext_op    ,
    output wire         r2_sel    ,
    output wire         rR1_re    ,
    output wire         rR2_re    ,
    output wire         alua_sel  ,
    output wire         alub_sel  ,
    output wire [ 4: 0] alu_op    ,
    output wire [ 2: 0] ram_ext_op,
    output wire [ 3: 0] ram_we    ,
    output wire         rf_we     ,
    output wire         wr_sel    ,
    output wire [ 1: 0] wd_sel    
);

    wire ADD_W     = (inst_31_15[31:15] == 17'h00020);
    wire SUB_W     = (inst_31_15[31:15] == 17'h00022);
    wire AND_W     = (inst_31_15[31:15] == 17'h00029);
    wire OR_W      = (inst_31_15[31:15] == 17'h0002A);
    wire XOR_W     = (inst_31_15[31:15] == 17'h0002B);
    wire NOR_W     = (inst_31_15[31:15] == 17'h00028);
    wire SLL_W     = (inst_31_15[31:15] == 17'h0002E);
    wire SRL_W     = (inst_31_15[31:15] == 17'h0002F);
    wire SRA_W     = (inst_31_15[31:15] == 17'h00030);
    wire SLT_W     = (inst_31_15[31:15] == 17'h00024);
    wire SLTU_W    = (inst_31_15[31:15] == 17'h00025);
    wire PCADDU12I = (inst_31_15[31:25] == 7'h0E    );
    wire LD_H      = (inst_31_15[31:22] == 10'h0A1  );

    wire TYPE_3R    = ADD_W | SUB_W | AND_W | OR_W | XOR_W | NOR_W | SLL_W | SRL_W | SRA_W | SLT_W | SLTU_W;
    wire LOAD       = LD_H;
    wire STORE      = 1'b0;

    wire NPC_OP_PC4  = TYPE_3R | PCADDU12I | LOAD | STORE;

    wire EXT_OP_12  = LOAD | STORE;
    wire EXT_OP_20  = PCADDU12I;

    wire ALU_OP_ADD  = ADD_W | PCADDU12I | LOAD | STORE;
    wire ALU_OP_SUB  = SUB_W;
    wire ALU_OP_AND  = AND_W;
    wire ALU_OP_OR   = OR_W;
    wire ALU_OP_XOR  = XOR_W;
    wire ALU_OP_NOR  = NOR_W;
    wire ALU_OP_SLL  = SLL_W;
    wire ALU_OP_SRL  = SRL_W;
    wire ALU_OP_SRA  = SRA_W;
    wire ALU_OP_SLT  = SLT_W;
    wire ALU_OP_SLTU = SLTU_W;

    
    wire WD_SEL_ALU = TYPE_3R | PCADDU12I;
    wire WD_SEL_RAM = LOAD | STORE;

    //npc_op的生成逻辑：如果是TYPE_3R、PCADDU12I、LOAD或STORE指令，则npc_op为`NPC_PC4
    assign npc_op = {2{NPC_OP_PC4 }} & `NPC_PC4; 

    assign is_br_jmp = 1'b0;

    //ext_op的生成逻辑：如果是EXT_OP_12为1，则ext_op为`EXT_12；如果是EXT_OP_20为1，则ext_op为`EXT_20
    assign ext_op = {3{EXT_OP_12 }} & `EXT_12  |
                    {3{EXT_OP_20 }} & `EXT_20  ;

    //如果是STORE指令，其源操作数2为rd，与其他指令为rk不同
    assign r2_sel = STORE ? `R2_RD : `R2_RK;

    //如果是PCADDU12I指令，则rR1_re为0（不需要从寄存器读取源操作数1），否则rR1_re为1（需要从寄存器读取源操作数1）
    assign rR1_re = !PCADDU12I;

    //如果是TYPE_3R或STORE指令，则rR2_re为1（需要从寄存器读取源操作数2），否则rR2_re为0（不需要从寄存器读取源操作数2）
    assign rR2_re = TYPE_3R | STORE;

    //如果是PCADDU12I指令，则alua_sel为`ALUA_PC（源操作数1为PC），否则alua_sel为`ALUA_R1（源操作数1为通用寄存器的值）
    assign alua_sel = PCADDU12I ? `ALUA_PC : `ALUA_R1;

    //如果是PCADDU12I、LOAD或STORE指令，则alub_sel为`ALUB_EXT（源操作数2为扩展后的立即数），否则alub_sel为`ALUB_R2（源操作数2为通用寄存器的值）
    assign alub_sel = (PCADDU12I | LOAD | STORE) ? `ALUB_EXT : `ALUB_R2;

    //ADD_W、PCADDU12I、LOAD、STORE指令的ALU操作都是加法，因此alu_op为`ALU_ADD
    assign alu_op = {5{ALU_OP_ADD}} & `ALU_ADD |
                    {5{ALU_OP_SUB}} & `ALU_SUB | 
                    {5{ALU_OP_AND}} & `ALU_AND | 
                    {5{ALU_OP_OR}}  & `ALU_OR  | 
                    {5{ALU_OP_XOR}} & `ALU_XOR | 
                    {5{ALU_OP_NOR}} & `ALU_NOR | 
                    {5{ALU_OP_SLL}} & `ALU_SLL | 
                    {5{ALU_OP_SRL}} & `ALU_SRL | 
                    {5{ALU_OP_SRA}} & `ALU_SRA | 
                    {5{ALU_OP_SLT}} & `ALU_SLT | 
                    {5{ALU_OP_SLTU}}& `ALU_SLTU ;

    //控制主存读回数据的扩展方式（针对load指令）
    assign ram_ext_op = {3{LD_H}} & `RAM_EXT_H;

    //store指令的主存写使能信号为`RAM_WE_W，其他指令的主存写使能信号为0
    assign ram_we = {4{1'b0}} & `RAM_WE_N;

    //寄存器写使能信号的生成逻辑：如果是TYPE_3R、PCADDU12I、LOAD或STORE指令，则rf_we为1（需要写回寄存器），否则rf_we为0（不需要写回寄存器）
    assign rf_we = NPC_OP_PC4 & !STORE;

    //写回目的地址选择信号，除了几个特殊指令，其他都是写回rd寄存器
    assign wr_sel = `WR_RD;

    //写回数据选择信号：如果是TYPE_3R或PCADDU12I指令，则wd_sel为`WD_ALU；如果是LOAD或STORE指令，则wd_sel为`WD_RAM
    assign wd_sel = {2{WD_SEL_ALU}} & `WD_ALU |
                    {2{WD_SEL_RAM}} & `WD_RAM ;

endmodule
