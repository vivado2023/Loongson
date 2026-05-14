`timescale 1ns / 1ps

`include "defines.vh"

module data_forward (
    input  wire [ 4:0]  id1_rR1   ,      // ID阶段是源寄存器1
    input  wire [ 4:0]  id1_rR2   ,      // ID阶段是源寄存器2
    input  wire         id1_rR1_re,      // ID阶段是否读取了源寄存器1
    input  wire         id1_rR2_re,      // ID阶段是否读取了源寄存器2

    input  wire [ 4:0]  id2_rR1   ,      // ID阶段是源寄存器1
    input  wire [ 4:0]  id2_rR2   ,      // ID阶段是源寄存器2
    input  wire         id2_rR1_re,      // ID阶段是否读取了源寄存器1
    input  wire         id2_rR2_re,      // ID阶段是否读取了源寄存器2

    input  wire         ex1_we    ,      // EX阶段的寄存器堆写使能信号
    input  wire [ 4:0]  ex1_wr    ,      // EX阶段的目的寄存器
    input  wire [31:0]  ex1_wd    ,      // EX阶段的写回数据
    input  wire         ex1_is_ld ,      // EX阶段是否是Load指令

    input  wire         ex2_we    ,      // EX阶段的寄存器堆写使能信号
    input  wire [ 4:0]  ex2_wr    ,      // EX阶段的目的寄存器
    input  wire [31:0]  ex2_wd    ,      // EX阶段的写回数据
    input  wire         ex2_is_ld ,      // EX阶段是否是Load指令

    input  wire         mem1_we   ,      // MEM阶段的寄存器堆写使能信号
    input  wire [ 4:0]  mem1_wr   ,      // MEM阶段的目的寄存器
    input  wire [31:0]  mem1_wd   ,      // MEM阶段的写回数据

    input  wire         mem2_we   ,      // MEM阶段的寄存器堆写使能信号
    input  wire [ 4:0]  mem2_wr   ,      // MEM阶段的目的寄存器
    input  wire [31:0]  mem2_wd   ,      // MEM阶段的写回数据

    input  wire         wb1_we    ,      // WB阶段的寄存器堆写使能信号
    input  wire [ 4:0]  wb1_wr    ,      // WB阶段的目的寄存器
    input  wire [31:0]  wb1_wd    ,      // WB阶段的写回数据

    input  wire         wb2_we    ,      // WB阶段的寄存器堆写使能信号
    input  wire [ 4:0]  wb2_wr    ,      // WB阶段的目的寄存器
    input  wire [31:0]  wb2_wd    ,      // WB阶段的写回数据

    output wire         fd1_rD1_sel,     // 前递到ID阶段的源操作数1的数据选择信号
    output reg  [31:0]  fd1_rD1    ,     // 前递到ID阶段的源操作数1
    output wire         fd1_rD2_sel,     // 前递到ID阶段的源操作数2的数据选择信号
    output reg  [31:0]  fd1_rD2    ,     // 前递到ID阶段的源操作数2

    output wire         fd2_rD1_sel,     // 前递到ID阶段的源操作数1的数据选择信号
    output reg  [31:0]  fd2_rD1    ,     // 前递到ID阶段的源操作数1
    output wire         fd2_rD2_sel,     // 前递到ID阶段的源操作数2的数据选择信号
    output reg  [31:0]  fd2_rD2    ,     // 前递到ID阶段的源操作数2

    output wire         load_use1  ,
    output wire         load_use2
);

//pipeline1 to pipeline1
    // rR1 RAW
    wire raw_rR1_id_ex_1to1  = (id1_rR1 == ex1_wr ) & id1_rR1_re & ex1_we  & (id1_rR1 != 5'h0);
    wire raw_rR1_id_mem_1to1 = (id1_rR1 == mem1_wr) & id1_rR1_re & mem1_we & (id1_rR1 != 5'h0);
    wire raw_rR1_id_wb_1to1  = (id1_rR1 == wb1_wr ) & id1_rR1_re & wb1_we  & (id1_rR1 != 5'h0);

    // rR2 RAW
    wire raw_rR2_id_ex_1to1  = (id1_rR2 == ex1_wr ) & id1_rR2_re & ex1_we  & (id1_rR2 != 5'h0);
    wire raw_rR2_id_mem_1to1 = (id1_rR2 == mem1_wr) & id1_rR2_re & mem1_we & (id1_rR2 != 5'h0);
    wire raw_rR2_id_wb_1to1  = (id1_rR2 == wb1_wr ) & id1_rR2_re & wb1_we  & (id1_rR2 != 5'h0);

//pipeline2 to pipeline2
    // rR1 RAW
    wire raw_rR1_id_ex_2to2  = (id2_rR1 == ex2_wr ) & id2_rR1_re & ex2_we  & (id2_rR1 != 5'h0);
    wire raw_rR1_id_mem_2to2 = (id2_rR1 == mem2_wr) & id2_rR1_re & mem2_we & (id2_rR1 != 5'h0);
    wire raw_rR1_id_wb_2to2  = (id2_rR1 == wb2_wr ) & id2_rR1_re & wb2_we  & (id2_rR1 != 5'h0);

    // rR2 RAW
    wire raw_rR2_id_ex_2to2  = (id2_rR2 == ex2_wr ) & id2_rR2_re & ex2_we  & (id2_rR2 != 5'h0);
    wire raw_rR2_id_mem_2to2 = (id2_rR2 == mem2_wr) & id2_rR2_re & mem2_we & (id2_rR2 != 5'h0);
    wire raw_rR2_id_wb_2to2  = (id2_rR2 == wb2_wr ) & id2_rR2_re & wb2_we  & (id2_rR2 != 5'h0);

//pipeline1 to pipeline2
    // rR1 RAW
    wire raw_rR1_id_ex_1to2  = (id2_rR1 == ex1_wr ) & id2_rR1_re & ex1_we  & (id2_rR1 != 5'h0);
    wire raw_rR1_id_mem_1to2 = (id2_rR1 == mem1_wr) & id2_rR1_re & mem1_we & (id2_rR1 != 5'h0);
    wire raw_rR1_id_wb_1to2  = (id2_rR1 == wb1_wr ) & id2_rR1_re & wb1_we  & (id2_rR1 != 5'h0);

    // rR2 RAW
    wire raw_rR2_id_ex_1to2  = (id2_rR2 == ex1_wr ) & id2_rR2_re & ex1_we  & (id2_rR2 != 5'h0);
    wire raw_rR2_id_mem_1to2 = (id2_rR2 == mem1_wr) & id2_rR2_re & mem1_we & (id2_rR2 != 5'h0);
    wire raw_rR2_id_wb_1to2  = (id2_rR2 == wb1_wr ) & id2_rR2_re & wb1_we  & (id2_rR2 != 5'h0);

//pipeline2 to pipeline1
    // rR1 RAW
    wire raw_rR1_id_ex_2to1  = (id1_rR1 == ex2_wr ) & id1_rR1_re & ex2_we  & (id1_rR1 != 5'h0);
    wire raw_rR1_id_mem_2to1 = (id1_rR1 == mem2_wr) & id1_rR1_re & mem2_we & (id1_rR1 != 5'h0);
    wire raw_rR1_id_wb_2to1  = (id1_rR1 == wb2_wr ) & id1_rR1_re & wb2_we  & (id1_rR1 != 5'h0);

    // rR2 RAW
    wire raw_rR2_id_ex_2to1  = (id1_rR2 == ex2_wr ) & id1_rR2_re & ex2_we  & (id1_rR2 != 5'h0);
    wire raw_rR2_id_mem_2to1 = (id1_rR2 == mem2_wr) & id1_rR2_re & mem2_we & (id1_rR2 != 5'h0);
    wire raw_rR2_id_wb_2to1  = (id1_rR2 == wb2_wr ) & id1_rR2_re & wb2_we  & (id1_rR2 != 5'h0);


    assign fd1_rD1_sel   = raw_rR1_id_ex_1to1 | raw_rR1_id_mem_1to1 | raw_rR1_id_wb_1to1 |
                           raw_rR1_id_ex_2to1 | raw_rR1_id_mem_2to1 | raw_rR1_id_wb_2to1;
    assign fd1_rD2_sel   = raw_rR2_id_ex_1to1 | raw_rR2_id_mem_1to1 | raw_rR2_id_wb_1to1 |
                           raw_rR2_id_ex_2to1 | raw_rR2_id_mem_2to1 | raw_rR2_id_wb_2to1;

    assign fd2_rD1_sel   = raw_rR1_id_ex_1to2 | raw_rR1_id_mem_1to2 | raw_rR1_id_wb_1to2 |
                           raw_rR1_id_ex_2to2 | raw_rR1_id_mem_2to2 | raw_rR1_id_wb_2to2;
    assign fd2_rD2_sel   = raw_rR2_id_ex_1to2 | raw_rR2_id_mem_1to2 | raw_rR2_id_wb_1to2 |
                           raw_rR2_id_ex_2to2 | raw_rR2_id_mem_2to2 | raw_rR2_id_wb_2to2;

//pipeline1
    //fd_rD1
    always @(*) begin
        if      (id1_rR1 == 5'h0)     fd1_rD1 = 32'h0;
        else if (raw_rR1_id_ex_1to1)  fd1_rD1 = ex1_wd;
        else if (raw_rR1_id_ex_2to1)  fd1_rD1 = ex2_wd;
        else if (raw_rR1_id_mem_1to1) fd1_rD1 = mem1_wd;
        else if (raw_rR1_id_mem_2to1) fd1_rD1 = mem2_wd;
        else if (raw_rR1_id_wb_1to1)  fd1_rD1 = wb1_wd;
        else if (raw_rR1_id_wb_2to1)  fd1_rD1 = wb2_wd;
        else                          fd1_rD1 = 32'h0;

    end
    //fd_rD2
    always @(*) begin
        if      (id1_rR2 == 5'h0)     fd1_rD2 = 32'h0;
        else if (raw_rR2_id_ex_1to1)  fd1_rD2 = ex1_wd;
        else if (raw_rR2_id_ex_2to1)  fd1_rD2 = ex2_wd;
        else if (raw_rR2_id_mem_1to1) fd1_rD2 = mem1_wd;
        else if (raw_rR2_id_mem_2to1) fd1_rD2 = mem2_wd;
        else if (raw_rR2_id_wb_1to1)  fd1_rD2 = wb1_wd;
        else if (raw_rR2_id_wb_2to1)  fd1_rD2 = wb2_wd;
        else                          fd1_rD2 = 32'h0;
    end

//pipeline2
    //fd_rD1
    always @(*) begin
        if      (id2_rR1 == 5'h0)     fd2_rD1 = 32'h0;
        else if (raw_rR1_id_ex_1to2)  fd2_rD1 = ex1_wd;
        else if (raw_rR1_id_ex_2to2)  fd2_rD1 = ex2_wd;
        else if (raw_rR1_id_mem_1to2) fd2_rD1 = mem1_wd;
        else if (raw_rR1_id_mem_2to2) fd2_rD1 = mem2_wd;
        else if (raw_rR1_id_wb_1to2)  fd2_rD1 = wb1_wd;
        else if (raw_rR1_id_wb_2to2)  fd2_rD1 = wb2_wd;
        else                          fd2_rD1 = 32'h0;

    end
    //fd_rD2
    always @(*) begin
        if      (id2_rR2 == 5'h0)     fd2_rD2 = 32'h0;
        else if (raw_rR2_id_ex_1to2)  fd2_rD2 = ex1_wd;
        else if (raw_rR2_id_ex_2to2)  fd2_rD2 = ex2_wd;
        else if (raw_rR2_id_mem_1to2) fd2_rD2 = mem1_wd;
        else if (raw_rR2_id_mem_2to2) fd2_rD2 = mem2_wd;
        else if (raw_rR2_id_wb_1to2)  fd2_rD2 = wb1_wd;
        else if (raw_rR2_id_wb_2to2)  fd2_rD2 = wb2_wd;
        else                          fd2_rD2 = 32'h0;
    end

// Load-Use
    assign load_use1 = ex1_is_ld && (raw_rR1_id_ex_1to1 || raw_rR2_id_ex_1to1) || 
                       ex2_is_ld && (raw_rR1_id_ex_2to1 || raw_rR2_id_ex_2to1);
    assign load_use2 = ex1_is_ld && (raw_rR1_id_ex_1to2 || raw_rR2_id_ex_1to2) || 
                       ex2_is_ld && (raw_rR1_id_ex_2to2 || raw_rR2_id_ex_2to2);

endmodule