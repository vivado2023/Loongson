`timescale 1ns / 1ps

`include "defines.vh"

module ID_stage (
    input  wire         cpu_rstn     ,
    input  wire         cpu_clk      ,
    // pipeline control
    input  wire         pl_suspend   ,      // 流水线暂停
    input  wire         pred_error   ,      // 分支预测错误的标志位
    input  wire         fd_rD1_sel   ,      // 源操作数1选择信号（选择前递数据或源寄存器1的值）
    input  wire [31:0]  fd_rD1       ,      // 前递到ID阶段的源操作数1
    input  wire         fd_rD2_sel   ,      // 源操作数2选择信号（选择前递数据或源寄存器1的值）
    input  wire [31:0]  fd_rD2       ,      // 前递到ID阶段的源操作数2
    // From IF and WB
    input  wire         if_valid     ,      // IF阶段有效信号
    input  wire [31:0]  if_pc        ,      // IF阶段PC值
    input  wire [31:0]  if_npc       ,      // IF阶段的下一条指令PC值
    input  wire         wb_rf_we     ,      // WB阶段的寄存器写使能
    input  wire [ 4:0]  wb_wR        ,      // WB阶段的目的寄存器
    input  wire [31:0]  wb_wd        ,      // WB阶段的写回数据
    // To IF
    output wire         id_is_ld_st  ,      // ID阶段是否是Load/Store指令
    output wire         id_is_mul_div,      // ID阶段是否是乘除指令
    // To EX
    output wire         id_valid     ,      // ID阶段有效信号
    output wire [31:0]  id_pc        ,      // ID阶段PC值
    output wire [ 1:0]  id_npc_op    ,      // ID阶段的npc_op，用于控制下一条指令PC值的生成
    output reg  [31:0]  id_ext       ,      // ID阶段的扩展后的立即数
    output wire [31:0]  id_real_rD1  ,      // ID阶段的源操作数1的实际值
    output wire [31:0]  id_real_rD2  ,      // ID阶段的源操作数2的实际值
    output wire [ 4:0]  id_alu_op    ,      // ID阶段的alu_op，用于控制ALU进行何种运算
    output wire         id_alua_sel  ,      // ID阶段的ALU操作数A选择信号（选择源寄存器1的值或扩展后的立即数或其他）
    output wire         id_alub_sel  ,      // ID阶段的ALU操作数B选择信号（选择源寄存器2的值或扩展后的立即数或其他）
    output wire         id_rf_we     ,      // ID阶段的寄存器写使能（指令需要写回时rf_we为1）
    output wire [ 4:0]  id_wR        ,      // ID阶段的目标寄存器
    output wire [ 1:0]  id_wd_sel    ,      // ID阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    output wire [ 3:0]  id_ram_we    ,      // ID阶段的主存写使能信号（针对store指令）
    output wire [ 2:0]  id_ram_ext_op,      // ID阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）
    output wire         id_is_br_jmp ,      // ID阶段是否是条件分支或直接跳转指令
    // Data Forward
    output wire [ 4:0]  id_rR1       ,      // 从指令码中解析出源寄存器1的编号/地址
    output wire         id_rR1_re    ,      // ID阶段的源寄存器1读标志信号（有效时表示指令需要从源寄存器1读取操作数）
    output wire [ 4:0]  id_rR2       ,      // 从指令码中解析出源寄存器2的编号/地址
    output wire         id_rR2_re    ,      // ID阶段的源寄存器2读标志信号（有效时表示指令需要从源寄存器2读取操作数）
    // Instruction Fetch Interface
    input  wire         ifetch_valid ,      // 指令机器码有效信号
    input  wire [31:0]  ifetch_inst         // 指令机器码
);

    IF_ID u_IF_ID (
        .cpu_clk    (cpu_clk   ),
        .cpu_rstn   (cpu_rstn  ),
        .suspend    (pl_suspend),

        .valid_in   (if_valid  ),
        .pc_in      (if_pc     ),
        .pc_out     (id_pc     )
    );
//id阶段有效的条件：指令机器码有效且没有分支预测错误
    assign id_valid = ifetch_valid & !pred_error;

/************************************************************/
//指令解码
/************************************************************/
/*确定指令类型*/
    wire ADD_W     = (ifetch_inst[31:15] == 17'h00020);
    wire SUB_W     = (ifetch_inst[31:15] == 17'h00022);
    wire AND       = (ifetch_inst[31:15] == 17'h00029);
    wire OR        = (ifetch_inst[31:15] == 17'h0002A);
    wire XOR       = (ifetch_inst[31:15] == 17'h0002B);
    wire NOR       = (ifetch_inst[31:15] == 17'h00028);
    wire SLL_W     = (ifetch_inst[31:15] == 17'h0002E);
    wire SRL_W     = (ifetch_inst[31:15] == 17'h0002F);
    wire SRA_W     = (ifetch_inst[31:15] == 17'h00030);
    wire SLT_W     = (ifetch_inst[31:15] == 17'h00024);
    wire SLTU_W    = (ifetch_inst[31:15] == 17'h00025);
    wire MUL_W     = (ifetch_inst[31:15] == 17'h00038);
    wire MULH_W    = (ifetch_inst[31:15] == 17'h00039);
    wire MULH_WU   = (ifetch_inst[31:15] == 17'h0003A);
    wire DIV_W     = (ifetch_inst[31:15] == 17'h00040);
    wire DIV_WU    = (ifetch_inst[31:15] == 17'h00042);
    wire MOD_W     = (ifetch_inst[31:15] == 17'h00041);
    wire MOD_WU    = (ifetch_inst[31:15] == 17'h00043);
    wire SLLI_W    = (ifetch_inst[31:15] == 17'h00081);
    wire SRLI_W    = (ifetch_inst[31:15] == 17'h00089);
    wire SRAI_W    = (ifetch_inst[31:15] == 17'h00091);
    wire ADDI_W    = (ifetch_inst[31:22] == 10'h00A  );
    wire ANDI      = (ifetch_inst[31:22] == 10'h00D  );
    wire ORI       = (ifetch_inst[31:22] == 10'h00E  );
    wire XORI      = (ifetch_inst[31:22] == 10'h00F  );
    wire SLTI      = (ifetch_inst[31:22] == 10'h008  );
    wire SLTUI     = (ifetch_inst[31:22] == 10'h009  );
    wire LD_B      = (ifetch_inst[31:22] == 10'h0A0  );
    wire LD_BU     = (ifetch_inst[31:22] == 10'h0A8  );
    wire LD_H      = (ifetch_inst[31:22] == 10'h0A1  );
    wire LD_HU     = (ifetch_inst[31:22] == 10'h0A9  );
    wire LD_W      = (ifetch_inst[31:22] == 10'h0A2  );
    wire ST_B      = (ifetch_inst[31:22] == 10'h0A4  );
    wire ST_H      = (ifetch_inst[31:22] == 10'h0A5  );
    wire ST_W      = (ifetch_inst[31:22] == 10'h0A6  );
    wire LU12I_W   = (ifetch_inst[31:25] == 7'h0A    );
    wire PCADDU12I = (ifetch_inst[31:25] == 7'h0E    );
    wire BEQ       = (ifetch_inst[31:26] == 6'h16    );
    wire BNE       = (ifetch_inst[31:26] == 6'h17    );
    wire BLT       = (ifetch_inst[31:26] == 6'h18    );
    wire BLTU      = (ifetch_inst[31:26] == 6'h1A    );
    wire BGE       = (ifetch_inst[31:26] == 6'h19    );
    wire BGEU      = (ifetch_inst[31:26] == 6'h1B    );
    wire JIRL      = (ifetch_inst[31:26] == 6'h13    );
    wire B         = (ifetch_inst[31:26] == 6'h14    );
    wire BL        = (ifetch_inst[31:26] == 6'h15    );

    wire is_branch = TYPE_2RI16;
    wire is_jump   = JIRL | B | BL;

    wire TYPE_3R    = ADD_W | SUB_W  | AND | OR | XOR | NOR | SLL_W | SRL_W | SRA_W | SLT_W | SLTU_W | 
                      MUL_W | MULH_W | MULH_WU | DIV_W | DIV_WU | MOD_W | MOD_WU;
    wire TYPE_2RI5  = SLLI_W | SRLI_W | SRAI_W;
    wire TYPE_2RI12 = ADDI_W | ANDI | ORI | XORI | SLTI | SLTUI;
    wire LOAD       = LD_B | LD_BU | LD_H | LD_HU | LD_W;
    wire STORE      = ST_B | ST_H | ST_W;
    wire TYPE_2RI16 = BEQ | BNE | BLT | BLTU | BGE | BGEU;

    wire ALU_OP_ADD    = ADD_W | PCADDU12I | LU12I_W | LOAD | STORE | ADDI_W | JIRL | BL;
    wire ALU_OP_SUB    = SUB_W;
    wire ALU_OP_AND    = AND | ANDI;
    wire ALU_OP_OR     = OR  | ORI;
    wire ALU_OP_XOR    = XOR | XORI;
    wire ALU_OP_NOR    = NOR;
    wire ALU_OP_SLL    = SLL_W | SLLI_W;
    wire ALU_OP_SRL    = SRL_W | SRLI_W;
    wire ALU_OP_SRA    = SRA_W | SRAI_W;
    wire ALU_OP_SLT    = SLT_W | SLTI;
    wire ALU_OP_SLTU   = SLTU_W | SLTUI;
    wire ALU_OP_MUL    = MUL_W;
    wire ALU_OP_MULH   = MULH_W;
    wire ALU_OP_MULH_U = MULH_WU;
    wire ALU_OP_DIV    = DIV_W;
    wire ALU_OP_DIV_U  = DIV_WU;
    wire ALU_OP_MOD    = MOD_W;
    wire ALU_OP_MOD_U  = MOD_WU;


/*确定操作类型*/
    assign id_alu_op = {5{ALU_OP_ADD}} & `ALU_ADD |
                       {5{ALU_OP_SUB}} & `ALU_SUB | 
                       {5{ALU_OP_AND}} & `ALU_AND | 
                       {5{ALU_OP_OR}}  & `ALU_OR  | 
                       {5{ALU_OP_XOR}} & `ALU_XOR | 
                       {5{ALU_OP_NOR}} & `ALU_NOR | 
                       {5{ALU_OP_SLL}} & `ALU_SLL | 
                       {5{ALU_OP_SRL}} & `ALU_SRL | 
                       {5{ALU_OP_SRA}} & `ALU_SRA | 
                       {5{ALU_OP_SLT}} & `ALU_SLT | 
                       {5{ALU_OP_SLTU}}& `ALU_SLTU|
                       {5{ALU_OP_MUL}} & `ALU_MUL |
                       {5{ALU_OP_MULH}} & `ALU_MULH |
                       {5{ALU_OP_MULH_U}} & `ALU_MULH_U |
                       {5{ALU_OP_DIV}} & `ALU_DIV |
                       {5{ALU_OP_DIV_U}} & `ALU_DIV_U |
                       {5{ALU_OP_MOD}} & `ALU_MOD |
                       {5{ALU_OP_MOD_U}} & `ALU_MOD_U |
                       {5{BEQ}} & `ALU_BEQ |
                       {5{BNE}} & `ALU_BNE |
                       {5{BLT}} & `ALU_BLT |
                       {5{BLTU}} & `ALU_BLTU |
                       {5{BGE}} & `ALU_BGE |
                       {5{BGEU}} & `ALU_BGEU |
                       {5{JIRL | BL}} & `ALU_J_BL |
                       {5{B}} & `ALU_B;

/*确定源操作数相关*/
wire [31:0] id_rD1, id_rD2;
//确定源操作数1地址（rj）（只针对通用寄存器）
    assign id_rR1 = !LU12I_W ? ifetch_inst[9:5] : 5'h0;
//确定源操作数1读使能：除PCADDU12I指令，都需要从寄存器读取源操作数1
    assign id_rR1_re = !PCADDU12I;
//确定源操作数1的选择：除PCADDU12I指令源操作数1为PC，其他指令源操作数1为通用寄存器的值
    assign id_alua_sel = (PCADDU12I | JIRL | BL) ? `ALUA_PC : `ALUA_R1;
//确定源操作数1的实际值：如果前递选择信号fd_rD1_sel有效，则使用前递数据fd_rD1，否则使用从寄存器堆读出的数据id_rD1
    assign id_real_rD1 = fd_rD1_sel ? fd_rD1 : id_rD1;

//确定源操作数2地址：如果是store指令，则rR2为rd（ifetch_inst[4:0]），否则rR2为rk（ifetch_inst[14:10]）
    assign id_rR2 = (STORE | TYPE_2RI16) ? ifetch_inst[4:0] : ifetch_inst[14:10];
//确定源操作数2读使能：TYPE_3R或STORE或TYPE_2RI16指令需要从寄存器读取源操作数2
    assign id_rR2_re = TYPE_3R | STORE | TYPE_2RI16;
//确定源操作数2的选择：如果是PCADDU12I、LU12I_W、LOAD或STORE或TYPE_2RI5指令，则为扩展立即数，否则为通用寄存器的值
    assign id_alub_sel = (PCADDU12I | LU12I_W | LOAD | STORE | TYPE_2RI5 | TYPE_2RI12 | JIRL | BL) ? `ALUB_EXT : `ALUB_R2;
//确定源操作数2的实际值：如果前递选择信号fd_rD2_sel有效，则使用前递数据fd_rD2，否则使用从寄存器堆读出的数据id_rD2
    assign id_real_rD2 = fd_rD2_sel ? fd_rD2 : id_rD2;

/*确定写回通用寄存器数据相关*/
//确定写回地址：对于写入寄存器堆的指令，除了bl指令，目的寄存器都是rd（ifetch_inst[4:0]）
    assign id_wR  = !BL ? ifetch_inst[4:0] : 5'h1;
//确定写回使能：如果是TYPE_3R、PCADDU12I、LU12I_W、LOAD或TYPE_2RI5指令，则需要写回通用寄存器
    assign id_rf_we = TYPE_3R | TYPE_2RI5 | TYPE_2RI12 | PCADDU12I | LU12I_W | LOAD | JIRL | BL;

/*确定主存相关指令*/
//确定是否是Load/Store指令
    assign id_is_ld_st = id_valid & (LOAD | STORE);
//控制主存读回数据的扩展方式（针对load指令）
    assign id_ram_ext_op = {3{LD_H}} & `RAM_EXT_H |
                           {3{LD_HU}}& `RAM_EXT_HU|
                           {3{LD_B}} & `RAM_EXT_B |
                           {3{LD_BU}}& `RAM_EXT_BU|
                           {3{LD_W}} & `RAM_EXT_W ;

//store指令的主存写使能信号为`RAM_WE_W，其他指令的主存写使能信号为0
    assign id_ram_we = {4{ST_B}} & `RAM_WE_B |
                       {4{ST_H}} & `RAM_WE_H |
                       {4{ST_W}} & `RAM_WE_W ;


/*其他*/
//npc_op的生成逻辑：如果是TYPE_3R、PCADDU12I、LOAD或STORE指令，则npc_op为`NPC_PC4
    wire NPC_OP_PC4  = TYPE_3R | TYPE_2RI5 | TYPE_2RI12 | PCADDU12I | LU12I_W | LOAD | STORE;
    assign id_npc_op = {2{NPC_OP_PC4}} & `NPC_PC4 |
                       {2{TYPE_2RI16}} & `NPC_B16 |
                       {2{JIRL}}       & `NPC_J |
                       {2{B | BL}}     & `NPC_B26 ; 

//写回数据选择信号：如果是TYPE_3R、TYPE_2RI5或PCADDU12I指令，则wd_sel为`WD_ALU；如果是LOAD或STORE指令，则wd_sel为`WD_RAM
    assign id_wd_sel = {2{TYPE_3R | TYPE_2RI5 | TYPE_2RI12 | PCADDU12I | LU12I_W | JIRL | BL}} & `WD_ALU |
                       {2{LOAD | STORE}}                                 & `WD_RAM ;

    assign id_is_br_jmp = TYPE_2RI16 | JIRL | B | BL;

    assign id_is_mul_div = id_valid & (MUL_W | MULH_W | MULH_WU | DIV_W | DIV_WU | MOD_W | MOD_WU);


/************************************************************/
//通用寄存器堆
/************************************************************/
    RF u_RF(
        .cpu_clk    (cpu_clk ),
        .rR1        (id_rR1  ),
        .rR2        (id_rR2  ),
        .we         (wb_rf_we),
        .wR         (wb_wR   ),
        .wD         (wb_wd   ),
        .rD1        (id_rD1  ),
        .rD2        (id_rD2  )
    );


/************************************************************/
//立即数扩展
/************************************************************/
    always @(*) begin
        if(LOAD | STORE)              id_ext = (ifetch_inst[21] ? {20'hfffff,ifetch_inst[21:10]} : {20'h00000,ifetch_inst[21:10]});
        else if(TYPE_2RI12) begin
            if(ADDI_W | SLTI | SLTUI) id_ext = (ifetch_inst[21] ? {20'hfffff,ifetch_inst[21:10]} : {20'h00000,ifetch_inst[21:10]});
            else                      id_ext = {20'h00000,ifetch_inst[21:10]};
        end
        else if(PCADDU12I | LU12I_W)  id_ext = {ifetch_inst[24:5],12'h000};
        else if(TYPE_2RI16 | JIRL)    id_ext = (ifetch_inst[25] ? {14'h3fff,ifetch_inst[25:10],2'b0} : {14'h0000,ifetch_inst[25:10],2'b0});
        else if(B | BL)               id_ext = (ifetch_inst[9] ? {4'hf,ifetch_inst[9:0],ifetch_inst[25:10],2'b0} : {4'h0,ifetch_inst[9:0],ifetch_inst[25:10],2'b0});
        else                          id_ext = {27'h0000000,ifetch_inst[14:10]};

    end

endmodule
