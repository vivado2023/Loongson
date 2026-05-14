`timescale 1ns / 1ps

`include "defines.vh"

module myCPU (
    input  wire         cpu_rstn     ,
    input  wire         cpu_clk      ,

    // Instruction Fetch Interface
    output wire         ifetch_rreq  ,      // 取指请求, 取指时为1'b1
    output wire [31:0]  ifetch_addr  ,      // 指令地址
    input  wire [ 1:0]  ifetch_valid ,      // 指令有效信号
    input  wire [63:0]  ifetch_inst  ,      // 指令机器码
    output wire         pred_error   ,      // 分支预测失败标志位信号
    output wire [ 1:0]  pred_taken_sel,      // 预测跳转的是哪条指令，1表示if_pc1跳转，否则为0
    
    // Data Access Interface
    output wire [ 3:0]  daccess_ren  ,      // 读使能, 发出读请求时置为4'hF
    output wire [31:0]  daccess_addr ,      // 读/写地址
    input  wire         daccess_valid,      // 读数据有效信号
    input  wire [31:0]  daccess_rdata,      // 读数据
    output wire [ 3:0]  daccess_wen  ,      // 写使能，支持字节使能
    output wire [31:0]  daccess_wdata,      // 写数据
    input  wire         daccess_wresp       // 写响应
);
    // Data Access
    wire [ 3:0]  daccess1_ren  ;      // MEM1阶段的读使能, 发出读请求时置为4'hF
    wire [31:0]  daccess1_addr ;      // MEM1阶段的读/写地址
    wire         daccess1_valid;      // MEM1阶段的读数据有效信号
    wire [31:0]  daccess1_rdata;      // MEM1阶段的读数据
    wire [ 3:0]  daccess1_wen  ;      // MEM1阶段的写使能，支持字节使能
    wire [31:0]  daccess1_wdata;      // MEM1阶段的写数据
    wire         daccess1_wresp;      // MEM1阶段的写响应

    wire [ 3:0]  daccess2_ren  ;      // MEM2阶段的读使能, 发出读请求时置为4'hF
    wire [31:0]  daccess2_addr ;      // MEM2阶段的读/写地址
    wire         daccess2_valid;      // MEM2阶段的读数据有效信号
    wire [31:0]  daccess2_rdata;      // MEM2阶段的读数据
    wire [ 3:0]  daccess2_wen  ;      // MEM2阶段的写使能，支持字节使能
    wire [31:0]  daccess2_wdata;      // MEM2阶段的写数据
    wire         daccess2_wresp;      // MEM2阶段的写响应

    assign daccess_ren   = daccess1_ren | daccess2_ren;
    assign daccess_addr  = (daccess1_ren | daccess1_wen) ? daccess1_addr : daccess2_addr;
    assign daccess_wen   = daccess1_wen | daccess2_wen;
    assign daccess_wdata = daccess1_wen ? daccess1_wdata : daccess2_wdata;

    assign daccess1_valid = mem1_is_ld_st ? daccess_valid : 1'b0;
    assign daccess1_rdata = mem1_is_ld_st ? daccess_rdata : 32'b0;
    assign daccess1_wresp = mem1_is_ld_st ? daccess_wresp : 1'b0;

    assign daccess2_valid = mem2_is_ld_st ? daccess_valid : 1'b0;
    assign daccess2_rdata = mem2_is_ld_st ? daccess_rdata : 32'b0;
    assign daccess2_wresp = mem2_is_ld_st ? daccess_wresp : 1'b0;

    // pipeline control
    wire        pred_error   ;      // 分支预测失败标志位信号
    wire        error_from1  ;
    wire [31:0] pred_target  ;      // 分支预测目标地址
    wire        ex1_suspend  ;       // EX阶段发出的流水线暂停信号（针对乘除指令）
    wire        ex2_suspend  ;       // EX阶段发出的流水线暂停信号（针对乘除指令）
    wire        ldst_suspend1 ;      // 执行访存指令时的流水线暂停信号
    wire        ldst_unalign1 ;      // 访存指令的访存地址是否满足对齐条件
    wire        ldst_suspend2 ;      // 执行访存指令时的流水线暂停信号
    wire        ldst_unalign2 ;      // 访存指令的访存地址是否满足对齐条件
    wire [31:0] fd1_rD1       ;      // 前递到ID阶段的源操作数1
    wire [31:0] fd1_rD2       ;      // 前递到ID阶段的源操作数2
    wire        fd1_rD1_sel   ;      // ID阶段的源操作数1选择信号（选择前递数据或源寄存器1的值）
    wire        fd1_rD2_sel   ;      // ID阶段的源操作数2选择信号（选择前递数据或源寄存器2的值）
    wire [31:0] fd2_rD1       ;      // 前递到ID阶段的源操作数1
    wire [31:0] fd2_rD2       ;      // 前递到ID阶段的源操作数2
    wire        fd2_rD1_sel   ;      // ID阶段的源操作数1选择信号（选择前递数据或源寄存器1的值）
    wire        fd2_rD2_sel   ;      // ID阶段的源操作数2选择信号（选择前递数据或源寄存器2的值）
    wire        load_use1     ;      // ID阶段的指令与EX1阶段的Load指令存在Load-Use数据冒险
    wire        load_use2     ;      // ID阶段的指令与EX2阶段的Load指令存在Load-Use数据冒险

    // IF Stage
    wire        if_valid     ;      // IF阶段有效信号（有效表示当前有指令正处于IF阶段, 或IF阶段正在取指）
    wire [31:0] if_pc        ;      // IF阶段的PC值, 或取指的指令地址
    wire [31:0] if_pc_r;            // IF阶段的PC值，延时一个周期，保证和取到的指令一起给到IFIFO
    wire [31:0] if_npc       ;      // IF阶段的下一条指令PC值

    // IFIFO Stage
    wire [31:0] ififo_inst_out1;     // IFIFO输出的指令
    wire        ififo_valid1;        // IFIFO输出的指令有效信号
    wire        id_ifetch_valid1;    // ID阶段发出的取指有效信号（表示ID阶段已准备好接收IFIFO输出的指令，可以让IFIFO输出下一条指令）
    wire [31:0] ififo_pc_out1;       // IFIFO输出的指令对应的PC值

    wire [31:0] ififo_inst_out2;     // IFIFO输出的指令
    wire        ififo_valid2;        // IFIFO输出的指令有效信号
    wire        id_ifetch_valid2;    // ID阶段发出的取指有效信号（表示ID阶段已准备好接收IFIFO输出的指令，可以让IFIFO输出下一条指令）
    wire [31:0] ififo_pc_out2;       // IFIFO输出的指令对应的PC值
    wire        spaceless;              

    // ID stage
    wire        id1_ifetch_valid;
    wire        id1_valid     ;      // ID阶段有效信号（有效表示当前有指令正处于ID阶段）
    wire [31:0] id1_pc        ;      // ID阶段的PC值
    wire [ 1:0] id1_npc_op    ;      // ID阶段的npc_op，用于控制下一条指令PC值的生成
    wire [ 4:0] id1_rR1       ;      // 从指令码中解析出源寄存器1的编号/地址
    wire [ 4:0] id1_rR2       ;      // 从指令码中解析出源寄存器2的编号/地址
    wire        id1_rR1_re    ;      // ID阶段的源寄存器1读标志信号（有效时表示指令需要从源寄存器1读取操作数）
    wire        id1_rR2_re    ;      // ID阶段的源寄存器2读标志信号（有效时表示指令需要从源寄存器2读取操作数）
    wire [31:0] id1_rD1       ;
    wire [31:0] id1_rD2       ;
    wire [31:0] id1_ext       ;      // ID阶段的扩展后的立即数
    wire [31:0] id1_real_rD1  ;      // ID阶段的源操作数1的实际值
    wire [31:0] id1_real_rD2  ;      // ID阶段的源操作数2的实际值
    wire [ 4:0] id1_alu_op    ;      // ID阶段的alu_op，用于控制ALU进行何种运算
    wire        id1_alua_sel  ;      // ID阶段的ALU操作数A选择信号（选择源寄存器1的值或扩展后的立即数或其他）
    wire        id1_alub_sel  ;      // ID阶段的ALU操作数B选择信号（选择源寄存器2的值或扩展后的立即数或其他）
    wire        id1_rf_we     ;      // ID阶段的寄存器写使能（指令需要写回时rf_we为1）
    wire [ 4:0] id1_wR        ;      // ID阶段的目标寄存器
    wire [ 1:0] id1_wd_sel    ;      // ID阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    wire        id1_is_ld     ;      // ID阶段是否是Load指令
    wire        id1_is_st     ;      // ID阶段是否是Store指令
    wire        id1_is_mul_div;      // ID阶段是否是乘除指令
    wire [ 3:0] id1_ram_we    ;      // ID阶段的主存写使能信号（针对store指令）
    wire [ 2:0] id1_ram_ext_op;      // ID阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）
    wire        id1_is_br_jmp ;      // ID阶段是否是条件分支或直接跳转指令

    wire        id2_ifetch_valid;
    wire        id2_valid     ;      // ID阶段有效信号（有效表示当前有指令正处于ID阶段）
    wire [31:0] id2_pc        ;      // ID阶段的PC值
    wire [ 1:0] id2_npc_op    ;      // ID阶段的npc_op，用于控制下一条指令PC值的生成
    wire [ 4:0] id2_rR1       ;      // 从指令码中解析出源寄存器1的编号/地址
    wire [ 4:0] id2_rR2       ;      // 从指令码中解析出源寄存器2的编号/地址
    wire        id2_rR1_re    ;      // ID阶段的源寄存器1读标志信号（有效时表示指令需要从源寄存器1读取操作数）
    wire        id2_rR2_re    ;      // ID阶段的源寄存器2读标志信号（有效时表示指令需要从源寄存器2读取操作数）
    wire [31:0] id2_rD1       ;
    wire [31:0] id2_rD2       ;
    wire [31:0] id2_ext       ;      // ID阶段的扩展后的立即数
    wire [31:0] id2_real_rD1  ;      // ID阶段的源操作数1的实际值
    wire [31:0] id2_real_rD2  ;      // ID阶段的源操作数2的实际值
    wire [ 4:0] id2_alu_op    ;      // ID阶段的alu_op，用于控制ALU进行何种运算
    wire        id2_alua_sel  ;      // ID阶段的ALU操作数A选择信号（选择源寄存器1的值或扩展后的立即数或其他）
    wire        id2_alub_sel  ;      // ID阶段的ALU操作数B选择信号（选择源寄存器2的值或扩展后的立即数或其他）
    wire        id2_rf_we     ;      // ID阶段的寄存器写使能（指令需要写回时rf_we为1）
    wire [ 4:0] id2_wR        ;      // ID阶段的目标寄存器
    wire [ 1:0] id2_wd_sel    ;      // ID阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    wire        id2_is_ld     ;      // ID阶段是否是Load指令
    wire        id2_is_st     ;      // ID阶段是否是Store指令
    wire        id2_is_mul_div;      // ID阶段是否是乘除指令
    wire [ 3:0] id2_ram_we    ;      // ID阶段的主存写使能信号（针对store指令）
    wire [ 2:0] id2_ram_ext_op;      // ID阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）
    wire        id2_is_br_jmp ;      // ID阶段是否是条件分支或直接跳转指令

    // EX Stage
    wire        ex1_valid     ;      // EX阶段有效信号（有效表示当前有指令正处于EX阶段）
    wire [31:0] ex1_pc        ;      // EX阶段的PC值
    wire [ 1:0] ex1_npc_op    ;      // EX阶段的npc_op，用于控制下一条指令PC值的生成
    wire [31:0] ex1_rD1       ;      // EX阶段的源寄存器1的值
    wire [31:0] ex1_rD2       ;      // EX阶段的源寄存器2的值
    wire [31:0] ex1_ext       ;      // EX阶段的扩展后的立即数
    wire [31:0] ex1_alu_C     ;      // EX阶段的ALU运算结果
    wire        ex1_alu_f     ;      // EX阶段的标志位
    wire        ex1_rf_we     ;      // EX阶段的寄存器写使能（指令需要写回时rf_we为1）
    wire [ 4:0] ex1_wR        ;      // EX阶段的目的寄存器
    wire [ 1:0] ex1_wd_sel    ;      // EX阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    wire [31:0] ex1_wd        ;      // EX阶段的待写回数据
    wire        ex1_is_ld     ;      // EX阶段是否是Load指令
    wire [ 3:0] ex1_ram_we    ;      // EX阶段的主存写使能信号（针对store指令）
    wire [ 2:0] ex1_ram_ext_op;      // EX阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）
    wire        ex1_sel_ram   ;      // EX阶段是否是访存指令 (特指Load指令, 用于Load-Use处理)
    wire        ex1_is_br_jmp ;      // EX阶段是否是条件分支或直接跳转指令
    wire        ex1_br_jmp_f  ;      // EX阶段分支跳转指令实际是否会发生跳转

    wire        ex2_valid     ;      // EX阶段有效信号（有效表示当前有指令正处于EX阶段）
    wire [31:0] ex2_pc        ;      // EX阶段的PC值
    wire [ 1:0] ex2_npc_op    ;      // EX阶段的npc_op，用于控制下一条指令PC值的生成
    wire [31:0] ex2_rD1       ;      // EX阶段的源寄存器1的值
    wire [31:0] ex2_rD2       ;      // EX阶段的源寄存器2的值
    wire [31:0] ex2_ext       ;      // EX阶段的扩展后的立即数
    wire [31:0] ex2_alu_C     ;      // EX阶段的ALU运算结果
    wire        ex2_alu_f     ;      // EX阶段的标志位
    wire        ex2_rf_we     ;      // EX阶段的寄存器写使能（指令需要写回时rf_we为1）
    wire [ 4:0] ex2_wR        ;      // EX阶段的目的寄存器
    wire [ 1:0] ex2_wd_sel    ;      // EX阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    wire [31:0] ex2_wd        ;      // EX阶段的待写回数据
    wire        ex2_is_ld     ;      // EX阶段是否是Load指令
    wire [ 3:0] ex2_ram_we    ;      // EX阶段的主存写使能信号（针对store指令）
    wire [ 2:0] ex2_ram_ext_op;      // EX阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）
    wire        ex2_sel_ram   ;      // EX阶段是否是访存指令 (特指Load指令, 用于Load-Use处理)
    wire        ex2_is_br_jmp ;      // EX阶段是否是条件分支或直接跳转指令
    wire        ex2_br_jmp_f  ;      // EX阶段分支跳转指令实际是否会发生跳转

    // MEM Stage
    wire        mem1_is_ld_st ;      // MEM阶段是否是load/store指令
    wire        mem1_valid    ;      // MEM阶段有效信号（有效表示当前有指令正处MEM阶段）
    wire [31:0] mem1_pc       ;      // MEM阶段的PC值
    wire [31:0] mem1_alu_C    ;      // MEM阶段的ALU运算结果
    wire [31:0] mem1_ram_ext  ;      // MEM阶段经过扩展的读主存数据
    wire [31:0] mem1_ext      ;      // MEM阶段的扩展后的立即数
    wire        mem1_rf_we    ;      // MEM阶段的寄存器写使能（指令需要写回时rf_we为1）
    wire [ 4:0] mem1_wR       ;      // MEM阶段的目的寄存器
    wire [ 1:0] mem1_wd_sel   ;      // MEM阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    wire [31:0] mem1_wd       ;      // MEM阶段的待写回数据
    wire        mem1_is_br_jmp;      // MEM阶段是否是条件分支或直接跳转指令
    wire        mem1_br_jmp_f ;      // MEM阶段分支跳转指令实际是否会发生跳转
    wire [ 1:0] mem1_npc_op   ;      // MEM阶段的npc_op，用于控制下一条指令PC值的生成
    wire        mem1_alu_f    ;      // MEM阶段的标志位
    wire [31:0] mem1_rD1      ;      // MEM阶段的源寄存器1的值（仅用于分支指令计算分支目标地址）

    wire        mem2_is_ld_st ;      // MEM阶段是否是load/store指令
    wire        mem2_valid    ;      // MEM阶段有效信号（有效表示当前有指令正处MEM阶段）
    wire [31:0] mem2_pc       ;      // MEM阶段的PC值
    wire [31:0] mem2_alu_C    ;      // MEM阶段的ALU运算结果
    wire [31:0] mem2_ram_ext  ;      // MEM阶段经过扩展的读主存数据
    wire [31:0] mem2_ext      ;      // MEM阶段的扩展后的立即数
    wire        mem2_rf_we    ;      // MEM阶段的寄存器写使能（指令需要写回时rf_we为1）
    wire [ 4:0] mem2_wR       ;      // MEM阶段的目的寄存器
    wire [ 1:0] mem2_wd_sel   ;      // MEM阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    wire [31:0] mem2_wd       ;      // MEM阶段的待写回数据
    wire        mem2_is_br_jmp;      // MEM阶段是否是条件分支或直接跳转指令
    wire        mem2_br_jmp_f ;      // MEM阶段分支跳转指令实际是否会发生跳转
    wire [ 1:0] mem2_npc_op   ;      // MEM阶段的npc_op，用于控制下一条指令PC值的生成
    wire        mem2_alu_f    ;      // MEM阶段的标志位
    wire [31:0] mem2_rD1      ;      // MEM阶段的源寄存器1的值（仅用于分支指令计算分支目标地址）

    // WB Stage
    wire        wb1_valid     ;      // WB阶段有效信号（有效表示当前有指令正处于WB阶段）
    wire [31:0] wb1_pc        ;      // WB阶段的PC值
    wire        wb1_rf_we     ;      // WB阶段的寄存器写使能
    wire [ 4:0] wb1_wR        ;      // WB阶段的目的寄存器
    wire [31:0] wb1_wd        ;      // WB阶段的写回数据

    wire        wb2_valid     ;      // WB阶段有效信号（有效表示当前有指令正处于WB阶段）
    wire [31:0] wb2_pc        ;      // WB阶段的PC值
    wire        wb2_rf_we     ;      // WB阶段的寄存器写使能
    wire [ 4:0] wb2_wR        ;      // WB阶段的目的寄存器
    wire [31:0] wb2_wd        ;      // WB阶段的写回数据

    wire pl_suspend = ldst_suspend1 | ldst_suspend2 | ex1_suspend | ex2_suspend;
    // wire pre_suspend = id1_is_ld_st | id1_is_mul_div | id2_is_ld_st | id2_is_mul_div | ex1_is_ld_st | ex2_is_ld_st;

    reg  spaceless_r;
    always @(posedge cpu_clk) begin
        spaceless_r <= spaceless;
    end

    wire pause_ifetch  = spaceless && !pred_error;
    wire resume_ifetch = spaceless_r && !spaceless && ifetch_inst != 64'h0;
    
    BPU u_BPU (
        .cpu_clk        (cpu_clk      ),
        .cpu_rstn       (cpu_rstn     ),
        .if_pc          (if_pc        ),
        // predicted branch dir. and target
        .pred_taken_sel (pred_taken_sel),
        .pred_target    (pred_target  ),
        .pred_error     (pred_error   ),
        .error_from1    (error_from1  ),
        .real_npc       (if_npc        ),
        // real dir. and target
        .mem_valid1      (mem1_valid     ),
        .mem_is_bj1      (mem1_is_br_jmp ),
        .mem_pc1         (mem1_pc        ),
        .real_taken1     (mem1_br_jmp_f  ),
        .real_target1    (if_npc1       ),

        .mem_valid2      (mem2_valid    ),
        .mem_is_bj2      (mem2_is_br_jmp ),
        .mem_pc2         (mem2_pc       ),
        .real_taken2     (mem2_br_jmp_f  ),
        .real_target2    (if_npc2       )
    );

    IF_stage IF (
        .cpu_rstn       (cpu_rstn     ),
        .cpu_clk        (cpu_clk      ),
        // pipeline control
        .pause_ifetch   (pause_ifetch ),
        .resume_ifetch  (resume_ifetch),
        // From BPU
        .pred_error     (pred_error   ),
        .pred_target    (pred_target  ),
        // From if_npc
        .if_npc         (if_npc       ),
        // To IFIFO
        .if_valid       (if_valid     ),
        .if_pc          (if_pc        ),
        .if_pc_r        (if_pc_r      ),
        // Instruction Fetch Interface
        .ifetch_rreq    (ifetch_rreq  ),
        .ifetch_addr    (ifetch_addr  ),
        .ifetch_valid   (ifetch_valid )
    );

wire [31:0] if_npc1, if_npc2;
    NPC u_NPC (
        .cpu_clk    (cpu_clk    ),
        .cpu_rstn   (cpu_rstn   ),

        .npc_op1     (mem1_npc_op  ),
        .mem_pc1     (mem1_pc      ),
        .rj1         (mem1_rD1     ),
        .offset1     (mem1_ext     ),
        .br1         (mem1_alu_f   ), 
        .npc1        (if_npc1     ),

        .npc_op2     (mem2_npc_op  ),
        .mem_pc2     (mem2_pc      ),
        .rj2         (mem2_rD1     ),
        .offset2     (mem2_ext     ),
        .br2         (mem2_alu_f   ), 
        .npc2        (if_npc2     )
    );

    wire RAW_hazard = id1_rf_we && ((id2_rR1_re && id2_rR1 == id1_wR) || (id2_rR2_re && id2_rR2 == id1_wR));
    wire BUS_hazard = (id1_is_ld || id1_is_st) && (id2_is_ld || id2_is_st);
    wire SWP_hazard = (id1_is_ld || id1_is_st) && id2_is_br_jmp || (id2_is_ld || id2_is_st) && id1_is_br_jmp; //suspend with predict
    assign pop_valid1 = ififo_valid1 && !pl_suspend && !load_use1;
    assign pop_valid2 = ififo_valid2 && !pl_suspend && !load_use2 && pop_valid1 && !RAW_hazard && !BUS_hazard && !SWP_hazard;
    Ififo u_Ififo (
        .cpu_rstn       (cpu_rstn     ),
        .cpu_clk        (cpu_clk      ),
        // From IF
        .inst_in        (ifetch_inst  ),
        .inst_in_valid  (ifetch_valid | {2{resume_ifetch}}),
        .pc_in          (if_pc_r      ),
        // From ID
        .pop_valid1      (pop_valid1   ),
        .pop_valid2      (pop_valid2   ),

        .pred_error     (pred_error   ),
        // To ID
        .inst_out1       (ififo_inst_out1),
        .inst_out_valid1 (ififo_valid1  ),
        .pc_out1         (ififo_pc_out1 ),

        .inst_out2       (ififo_inst_out2),
        .inst_out_valid2 (ififo_valid2  ),
        .pc_out2         (ififo_pc_out2 ),
        .spaceless       (spaceless     )
    );

    ID_stage ID1 (
        .fd_rD1_sel     (fd1_rD1_sel   ),
        .fd_rD1         (fd1_rD1       ),
        .fd_rD2_sel     (fd1_rD2_sel   ),
        .fd_rD2         (fd1_rD2       ),
        // From IFIFO
        // .ififo_valid    (ififo_valid1  ),
        .ififo_inst    (ififo_inst_out1),
        // .ififo_pc       (ififo_pc_out1 ),
        // From EX and WB
        // .wb_rf_we       (wb1_rf_we     ),
        // .wb_wR          (wb1_wR        ),
        // .wb_wd          (wb1_wd        ),
        // From RF
        .id_rD1         (id1_rD1       ),
        .id_rD2         (id1_rD2       ),
        // To EX
        // .id_pc          (id1_pc        ),
        .id_npc_op      (id1_npc_op    ),
        .id_ext         (id1_ext       ),
        .id_real_rD1    (id1_real_rD1  ),
        .id_real_rD2    (id1_real_rD2  ),
        .id_alu_op      (id1_alu_op    ),
        .id_alua_sel    (id1_alua_sel  ),
        .id_alub_sel    (id1_alub_sel  ),
        .id_rf_we       (id1_rf_we     ),
        .id_wR          (id1_wR        ),
        .id_wd_sel      (id1_wd_sel    ),
        .id_ram_we      (id1_ram_we    ),
        .id_ram_ext_op  (id1_ram_ext_op),
        .id_is_br_jmp   (id1_is_br_jmp ),
        .id_is_ld       (id1_is_ld  ),
        .id_is_st       (id1_is_st  ),
        // .id_is_mul_div  (id1_is_mul_div ),
        // Data Forward
        .id_rR1         (id1_rR1       ),
        .id_rR1_re      (id1_rR1_re    ),
        .id_rR2         (id1_rR2       ),
        .id_rR2_re      (id1_rR2_re    )
    );

    ID_stage ID2 (
        .fd_rD1_sel     (fd2_rD1_sel   ),
        .fd_rD1         (fd2_rD1       ),
        .fd_rD2_sel     (fd2_rD2_sel   ),
        .fd_rD2         (fd2_rD2       ),
        // From IFIFO
        // .ififo_valid    (ififo_valid2  ),
        .ififo_inst    (ififo_inst_out2),
        // .ififo_pc       (ififo_pc_out2 ),
        // From EX and WB
        // .wb_rf_we       (wb2_rf_we     ),
        // .wb_wR          (wb2_wR        ),
        // .wb_wd          (wb2_wd        ),
        // From RF
        .id_rD1         (id2_rD1       ),
        .id_rD2         (id2_rD2       ),
        // To EX
        // .id_pc          (id2_pc        ),
        .id_npc_op      (id2_npc_op    ),
        .id_ext         (id2_ext       ),
        .id_real_rD1    (id2_real_rD1  ),
        .id_real_rD2    (id2_real_rD2  ),
        .id_alu_op      (id2_alu_op    ),
        .id_alua_sel    (id2_alua_sel  ),
        .id_alub_sel    (id2_alub_sel  ),
        .id_rf_we       (id2_rf_we     ),
        .id_wR          (id2_wR        ),
        .id_wd_sel      (id2_wd_sel    ),
        .id_ram_we      (id2_ram_we    ),
        .id_ram_ext_op  (id2_ram_ext_op),
        .id_is_br_jmp   (id2_is_br_jmp ),
        .id_is_ld       (id2_is_ld  ),
        .id_is_st       (id2_is_st  ),
        // .id_is_mul_div  (id2_is_mul_div ),
        // Data Forward
        .id_rR1         (id2_rR1       ),
        .id_rR1_re      (id2_rR1_re    ),
        .id_rR2         (id2_rR2       ),
        .id_rR2_re      (id2_rR2_re    )
    );

    RF u_RF(
        .cpu_clk    (cpu_clk ),
        .rR1_1        (id1_rR1  ),
        .rR2_1        (id1_rR2  ),
        .rR1_2        (id2_rR1  ),
        .rR2_2        (id2_rR2  ),
        .we1         (wb1_rf_we),
        .wR1         (wb1_wR   ),
        .wD1         (wb1_wd   ),
        .we2         (wb2_rf_we),
        .wR2         (wb2_wR   ),
        .wD2         (wb2_wd   ),
        .rD1_1        (id1_rD1  ),
        .rD2_1        (id1_rD2  ),
        .rD1_2        (id2_rD1  ),
        .rD2_2        (id2_rD2  )
    );

    data_forward u_DF (
        .id1_rR1         (id1_rR1       ),
        .id1_rR2         (id1_rR2       ),
        .id1_rR1_re      (id1_rR1_re    ),
        .id1_rR2_re      (id1_rR2_re    ),
        .id2_rR1         (id2_rR1       ),
        .id2_rR2         (id2_rR2       ),
        .id2_rR1_re      (id2_rR1_re    ),
        .id2_rR2_re      (id2_rR2_re    ),
        .ex1_we          (ex1_rf_we & ex1_valid),
        .ex1_wr          (ex1_wR        ),
        .ex1_wd          (ex1_wd        ),
        .ex1_is_ld       (ex1_is_ld     ),
        .ex2_we          (ex2_rf_we & ex2_valid),
        .ex2_wr          (ex2_wR        ),
        .ex2_wd          (ex2_wd        ),
        .ex2_is_ld       (ex2_is_ld     ),
        .mem1_we         (mem1_rf_we    ),
        .mem1_wr         (mem1_wR       ),
        .mem1_wd         (mem1_wd       ),
        .mem2_we         (mem2_rf_we    ),
        .mem2_wr         (mem2_wR       ),
        .mem2_wd         (mem2_wd       ),
        .wb1_we          (wb1_rf_we     ),
        .wb1_wr          (wb1_wR        ),
        .wb1_wd          (wb1_wd        ),
        .wb2_we          (wb2_rf_we     ),
        .wb2_wr          (wb2_wR        ),
        .wb2_wd          (wb2_wd        ),

        .fd1_rD1_sel     (fd1_rD1_sel   ),
        .fd1_rD1         (fd1_rD1       ),
        .fd1_rD2_sel     (fd1_rD2_sel   ),
        .fd1_rD2         (fd1_rD2       ),
        .fd2_rD1_sel     (fd2_rD1_sel   ),
        .fd2_rD1         (fd2_rD1       ),
        .fd2_rD2_sel     (fd2_rD2_sel   ),
        .fd2_rD2         (fd2_rD2       ),
        .load_use1       (load_use1     ),
        .load_use2       (load_use2     )
    );


    EX_stage EX1 (
        .cpu_rstn       (cpu_rstn     ),
        .cpu_clk        (cpu_clk      ),
        // pipeline control
        .pl_suspend     (pl_suspend   ),
        .ex_suspend     (ex1_suspend   ),
        .ldst_unalign   (ldst_unalign1 ),
        .pred_error     (pred_error   ),
        // From ID
        .id_valid       (pop_valid1    ),
        .id_pc          (ififo_pc_out1 ),
        .id_npc_op      (id1_npc_op    ),
        .id_ext         (id1_ext       ),
        .id_real_rD1    (id1_real_rD1  ),
        .id_real_rD2    (id1_real_rD2  ),
        .id_alu_op      (id1_alu_op    ),
        .id_alua_sel    (id1_alua_sel  ),
        .id_alub_sel    (id1_alub_sel  ),
        .id_rf_we       (id1_rf_we     ),
        .id_wR          (id1_wR        ),
        .id_wd_sel      (id1_wd_sel    ),
        .id_ram_we      (id1_ram_we    ),
        .id_ram_ext_op  (id1_ram_ext_op),
        .id_is_br_jmp   (id1_is_br_jmp ),
        .id_is_ld       (id1_is_ld  ),
        // To IF
        .ex_npc_op      (ex1_npc_op    ),
        .ex_alu_f       (ex1_alu_f     ),
        // To ID
        .ex_is_ld       (ex1_is_ld  ),
        // To MEM
        .ex_valid       (ex1_valid     ),
        .ex_wR          (ex1_wR        ),
        .ex_pc          (ex1_pc        ),
        .ex_alu_C       (ex1_alu_C     ),
        .ex_rD1         (ex1_rD1       ),
        .ex_rD2         (ex1_rD2       ),
        .ex_ext         (ex1_ext       ),
        .ex_rf_we       (ex1_rf_we     ),
        .ex_wd_sel      (ex1_wd_sel    ),
        .ex_ram_we      (ex1_ram_we    ),
        .ex_ram_ext_op  (ex1_ram_ext_op),
        .ex_is_br_jmp   (ex1_is_br_jmp ),
        .ex_br_jmp_f    (ex1_br_jmp_f  ),
        // Data Forward
        .ex_wd          (ex1_wd        ),
        .ex_sel_ram     (ex1_sel_ram   )
    );

    EX_stage EX2 (
        .cpu_rstn       (cpu_rstn     ),
        .cpu_clk        (cpu_clk      ),
        // pipeline control
        .pl_suspend     (pl_suspend   ),
        .ex_suspend     (ex2_suspend   ),
        .ldst_unalign   (ldst_unalign2 ),
        .pred_error     (pred_error   ),
        // From ID
        .id_valid       (pop_valid2    ),
        .id_pc          (ififo_pc_out2 ),
        .id_npc_op      (id2_npc_op    ),
        .id_ext         (id2_ext       ),
        .id_real_rD1    (id2_real_rD1  ),
        .id_real_rD2    (id2_real_rD2  ),
        .id_alu_op      (id2_alu_op    ),
        .id_alua_sel    (id2_alua_sel  ),
        .id_alub_sel    (id2_alub_sel  ),
        .id_rf_we       (id2_rf_we     ),
        .id_wR          (id2_wR        ),
        .id_wd_sel      (id2_wd_sel    ),
        .id_ram_we      (id2_ram_we    ),
        .id_ram_ext_op  (id2_ram_ext_op),
        .id_is_br_jmp   (id2_is_br_jmp ),
        .id_is_ld       (id2_is_ld  ),
        // To IF
        .ex_npc_op      (ex2_npc_op    ),
        .ex_alu_f       (ex2_alu_f     ),
        // To ID
        .ex_is_ld       (ex2_is_ld  ),
        // To MEM
        .ex_valid       (ex2_valid     ),
        .ex_wR          (ex2_wR        ),
        .ex_pc          (ex2_pc        ),
        .ex_alu_C       (ex2_alu_C     ),
        .ex_rD1         (ex2_rD1       ),
        .ex_rD2         (ex2_rD2       ),
        .ex_ext         (ex2_ext       ),
        .ex_rf_we       (ex2_rf_we     ),
        .ex_wd_sel      (ex2_wd_sel    ),
        .ex_ram_we      (ex2_ram_we    ),
        .ex_ram_ext_op  (ex2_ram_ext_op),
        .ex_is_br_jmp   (ex2_is_br_jmp ),
        .ex_br_jmp_f    (ex2_br_jmp_f  ),
        // Data Forward
        .ex_wd          (ex2_wd        ),
        .ex_sel_ram     (ex2_sel_ram   )
    );

    MEM_stage MEM1 (
        .cpu_rstn       (cpu_rstn     ),
        .cpu_clk        (cpu_clk      ),
        // pipeline control
        .pl_suspend     (pl_suspend   ),
        .ldst_suspend   (ldst_suspend1 ),
        .ldst_unalign   (ldst_unalign1 ),
        .pred_error     (pred_error   ),
        .mem_is_ld_st   (mem1_is_ld_st  ),
        // From EX
        .ex_valid       (ex1_valid     ),
        .ex_pc          (ex1_pc        ),
        .ex_rD1         (ex1_rD1       ),
        .ex_rD2         (ex1_rD2       ),
        .ex_ext         (ex1_ext       ),
        .ex_alu_C       (ex1_alu_C     ),
        .ex_rf_we       (ex1_rf_we     ),
        .ex_wR          (ex1_wR        ),
        .ex_wd_sel      (ex1_wd_sel    ),
        .ex_ram_we      (ex1_ram_we    ),
        .ex_ram_ext_op  (ex1_ram_ext_op),
        .ex_is_br_jmp   (ex1_is_br_jmp ),
        .ex_br_jmp_f    (ex1_br_jmp_f  ),
        .ex_npc_op      (ex1_npc_op    ),
        .ex_alu_f       (ex1_alu_f     ),
        // To IF
        .mem_is_br_jmp  (mem1_is_br_jmp ),
        .mem_br_jmp_f   (mem1_br_jmp_f  ),
        .mem_npc_op     (mem1_npc_op    ),
        .mem_alu_f      (mem1_alu_f     ),
        .mem_rD1        (mem1_rD1       ),
        // To WB
        .mem_valid      (mem1_valid    ),
        .mem_pc         (mem1_pc       ),
        .mem_ext        (mem1_ext      ),
        .mem_alu_C      (mem1_alu_C    ),
        .mem_ram_ext    (mem1_ram_ext  ),
        .mem_rf_we      (mem1_rf_we    ),
        .mem_wR         (mem1_wR       ),
        .mem_wd_sel     (mem1_wd_sel   ),
        // Data Forward
        .mem_wd         (mem1_wd       ),
        // Data Access Interface
        .daccess_ren    (daccess1_ren  ),
        .daccess_addr   (daccess1_addr ),
        .daccess_valid  (daccess1_valid),
        .daccess_rdata  (daccess1_rdata),
        .daccess_wen    (daccess1_wen  ),
        .daccess_wdata  (daccess1_wdata),
        .daccess_wresp  (daccess1_wresp)
    );

    MEM_stage MEM2 (
        .cpu_rstn       (cpu_rstn     ),
        .cpu_clk        (cpu_clk      ),
        // pipeline control
        .pl_suspend     (pl_suspend   ),
        .ldst_suspend   (ldst_suspend2 ),
        .ldst_unalign   (ldst_unalign2 ),
        .pred_error     (pred_error   ),
        .mem_is_ld_st   (mem2_is_ld_st  ),
        // From EX
        .ex_valid       (ex2_valid     ),
        .ex_pc          (ex2_pc        ),
        .ex_rD1         (ex2_rD1       ),
        .ex_rD2         (ex2_rD2       ),
        .ex_ext         (ex2_ext       ),
        .ex_alu_C       (ex2_alu_C     ),
        .ex_rf_we       (ex2_rf_we     ),
        .ex_wR          (ex2_wR        ),
        .ex_wd_sel      (ex2_wd_sel    ),
        .ex_ram_we      (ex2_ram_we    ),
        .ex_ram_ext_op  (ex2_ram_ext_op),
        .ex_is_br_jmp   (ex2_is_br_jmp ),
        .ex_br_jmp_f    (ex2_br_jmp_f  ),
        .ex_npc_op      (ex2_npc_op    ),
        .ex_alu_f       (ex2_alu_f     ),
        // To IF
        .mem_is_br_jmp  (mem2_is_br_jmp ),
        .mem_br_jmp_f   (mem2_br_jmp_f  ),
        .mem_npc_op     (mem2_npc_op    ),
        .mem_alu_f      (mem2_alu_f     ),
        .mem_rD1        (mem2_rD1       ),
        // To WB
        .mem_valid      (mem2_valid    ),
        .mem_pc         (mem2_pc       ),
        .mem_ext        (mem2_ext      ),
        .mem_alu_C      (mem2_alu_C    ),
        .mem_ram_ext    (mem2_ram_ext  ),
        .mem_rf_we      (mem2_rf_we    ),
        .mem_wR         (mem2_wR       ),
        .mem_wd_sel     (mem2_wd_sel   ),
        // Data Forward
        .mem_wd         (mem2_wd       ),
        // Data Access Interface
        .daccess_ren    (daccess2_ren  ),
        .daccess_addr   (daccess2_addr ),
        .daccess_valid  (daccess2_valid),
        .daccess_rdata  (daccess2_rdata),
        .daccess_wen    (daccess2_wen  ),
        .daccess_wdata  (daccess2_wdata),
        .daccess_wresp  (daccess2_wresp)
    );
    

    WB_stage WB1 (
        .cpu_rstn       (cpu_rstn     ),
        .cpu_clk        (cpu_clk      ),
        // pipeline control
        .pl_suspend     (pl_suspend   ),
        .pred_error     (1'b0         ),
        .error_from1    (error_from1  ),
        // From MEM
        .mem_valid      (mem1_valid    ),
        .mem_pc         (mem1_pc       ),
        .mem_ext        (mem1_ext      ),
        .mem_alu_C      (mem1_alu_C    ),
        .mem_ram_ext    (mem1_ram_ext  ),
        .mem_rf_we      (mem1_rf_we    ),
        .mem_wR         (mem1_wR       ),
        .mem_wd_sel     (mem1_wd_sel   ),
        // To ID
        .wb_rf_we       (wb1_rf_we     ),
        .wb_wR          (wb1_wR        ),
        .wb_wd          (wb1_wd        ),
        // Trace Debug
        .wb_valid       (wb1_valid     ),
        .wb_pc          (wb1_pc        )
    );

    WB_stage WB2 (
        .cpu_rstn       (cpu_rstn     ),
        .cpu_clk        (cpu_clk      ),
        // pipeline control
        .pl_suspend     (pl_suspend   ),
        .pred_error     (pred_error   ),
        .error_from1    (error_from1  ),
        // From MEM
        .mem_valid      (mem2_valid    ),
        .mem_pc         (mem2_pc       ),
        .mem_ext        (mem2_ext      ),
        .mem_alu_C      (mem2_alu_C    ),
        .mem_ram_ext    (mem2_ram_ext  ),
        .mem_rf_we      (mem2_rf_we    ),
        .mem_wR         (mem2_wR       ),
        .mem_wd_sel     (mem2_wd_sel   ),
        // To ID
        .wb_rf_we       (wb2_rf_we     ),
        .wb_wR          (wb2_wR        ),
        .wb_wd          (wb2_wd        ),
        // Trace Debug
        .wb_valid       (wb2_valid     ),
        .wb_pc          (wb2_pc        )
    );


    wire [31:0] debug_wb_pc;
    wire [ 3:0] debug_wb_rf_we;
    wire [ 4:0] debug_wb_rf_rd;
    wire [31:0] debug_wb_rf_wdata;
    Wait_for_tb u_Wait_for_tb (
        .cpu_clk    (cpu_clk    ),
        .cpu_rstn   (cpu_rstn   ),
        .wb_pc1     (wb1_pc     ),
        .wb_rf_we1  (wb1_rf_we  ),
        .wb_wR1     (wb1_wR     ),
        .wb_wd1     (wb1_wd     ),
        .wb_pc2     (wb2_pc     ),
        .wb_rf_we2  (wb2_rf_we  ),
        .wb_wR2     (wb2_wR     ),
        .wb_wd2     (wb2_wd     ),
        .debug_wb_pc   (debug_wb_pc   ),
        .debug_wb_rf_we(debug_wb_rf_we),
        .debug_wb_wR   (debug_wb_rf_rd   ),
        .debug_wb_wd   (debug_wb_rf_wdata   )
    );



    ///////////////////////////////////////////////////////////////////////////
    // Trace Debug Interface
    // RegisterFile Write
    // wire [31:0] debug_wb_pc       = wb_pc;              // WB阶段PC值
    // wire [ 3:0] debug_wb_rf_we    = {4{wb_rf_we}};      // WB阶段的寄存器堆写使能
    // wire [ 4:0] debug_wb_rf_rd    = wb_wR;              // WB阶段被写的寄存器的编号/地址
    // wire [31:0] debug_wb_rf_wdata = wb_wd;              // WB阶段写入寄存器的数据值

    // Memory Data Write
    wire [31:0] debug_wdata_pc   = daccess1_wen ? mem1_pc : (daccess2_wen ? mem2_pc : 32'd0);              // 发起写访存的流水线阶段的PC值（此处为MEM阶段）
    wire [ 3:0] debug_wdata_we   = daccess_wen;         // 写使能
    wire [31:0] debug_wdata_addr = daccess_addr;        // 写地址
    wire [31:0] debug_wdata      = daccess_wdata;       // 写数据

    // // Branch & Jump
    wire [31:0] debug_bj_pc      ;                       // 确定跳转方向和目标地址的阶段的PC值（此处为MEM阶段）
    wire        debug_bj_taken   ; // 发生跳转时有效
    wire [31:0] debug_bj_target  ;                       // 跳转时的目标地址
    ///////////////////////////////////////////////////////////////////////////

endmodule
