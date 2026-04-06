`timescale 1ns / 1ps

`include "defines.vh"

module ALU (
    input  wire         cpu_rstn,   
    input  wire         cpu_clk ,   
    input  wire [ 4:0]  alu_op  ,     
    input  wire [31:0]  A       ,     
    input  wire [31:0]  B       ,     
    output reg  [31:0]  C       ,     
    output reg          f       ,
    output wire         ready
  );

    reg [1:0] cnt;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) cnt <= 2'b0;
        else if((alu_op == `ALU_MUL) || (alu_op == `ALU_MULH) || (alu_op == `ALU_MULH_U)) begin
            if(cnt < 2'b11) cnt <= cnt + 2'b01;
            else            cnt <= 2'b0;
        end
    end

    assign ready = ((alu_op == `ALU_MUL) || (alu_op == `ALU_MULH) || (alu_op == `ALU_MULH_U)) && (cnt == 2'b11)
                    || ready_div;

    wire [32:0] A_ext = (alu_op == `ALU_MULH_U) ? {1'b0,A} : {A[31],A};
    wire [32:0] B_ext = (alu_op == `ALU_MULH_U) ? {1'b0,B} : {B[31],B};
    wire [65:0] mul_result;
    mult_gen_0 u_mult(
        .CLK(cpu_clk),
        .A(A_ext),
        .B(B_ext),
        .P(mul_result)
    );

//除法与取余（试商法）
    wire [63:0] div_result;
    wire start_div = (alu_op == `ALU_DIV || alu_op == `ALU_DIV_U || alu_op == `ALU_MOD || alu_op == `ALU_MOD_U) && !busy_div && !ready_div;
    wire is_signed_div = (alu_op == `ALU_DIV || alu_op == `ALU_MOD);
    wire ready_div;
    wire busy_div;

    DIV u_DIV (
        .cpu_clk(cpu_clk),
        .cpu_rstn(cpu_rstn),
        .is_signed(is_signed_div),
        .start(start_div),
        .A(A),
        .B(B),
        .result(div_result),
        .busy(busy_div),
        .ready(ready_div)
    );

//与通用寄存器有关的运算
    always @(*) begin
        case (alu_op)
            `ALU_ADD : C = A + B;
            `ALU_SUB : C = A - B;
            `ALU_AND : C = A & B;
            `ALU_OR  : C = A | B;
            `ALU_XOR : C = A ^ B;
            `ALU_NOR : C = ~(A | B);
            `ALU_SLL : C = A << B[4:0];
            `ALU_SRL : C = A >> B[4:0];
            `ALU_SRA : C = $signed(A) >>> B[4:0];
            `ALU_SLT : C = ($signed(A) < $signed(B)) ? 32'b1 : 32'b0;
            `ALU_SLTU: C = (A < B) ? 32'b1 : 32'b0;
            `ALU_MUL : C = ready ? mul_result[31:0] : C;
            `ALU_MULH : C = ready ? mul_result[63:32] : C;
            `ALU_MULH_U :C = ready ? mul_result[63:32] : C;
            `ALU_DIV : C = ready_div ? div_result[31:0] : C;
            `ALU_DIV_U : C = ready_div ? div_result[31:0] : C;
            `ALU_MOD : C = ready_div ? div_result[63:32] : C;
            `ALU_MOD_U : C = ready_div ? div_result[63:32] : C;
            `ALU_J_BL : C = A + 32'h4;
            default  : C = 32'h87654321;
        endcase
    end


//与分支判断相关的运算
    always @(*) begin
        case (alu_op)
            `ALU_BEQ : f = (A == B);
            `ALU_BNE : f = (A != B);
            `ALU_BLT : f = ($signed(A) < $signed(B));
            `ALU_BLTU: f = (A < B);
            `ALU_BGE : f = ($signed(A) >= $signed(B));
            `ALU_BGEU: f = (A >= B);
            `ALU_B   : f = 1'b1;
            `ALU_J_BL: f = 1'b1;
            default  : f = 1'b0;
        endcase
    end

endmodule
