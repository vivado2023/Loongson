`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/22 20:12:49
// Design Name: 
// Module Name: PreDecoder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module PreDecoder(
    input wire [31:0]  inst1    ,
    input wire [31:0]  inst2    ,
    output wire        both_ldst,
    output wire        raw_hazard      
);
    wire ADD_W1     = (inst1[31:15] === 17'h00020);
    wire SUB_W1     = (inst1[31:15] === 17'h00022);
    wire AND1       = (inst1[31:15] === 17'h00029);
    wire OR1        = (inst1[31:15] === 17'h0002A);
    wire XOR1       = (inst1[31:15] === 17'h0002B);
    wire NOR1       = (inst1[31:15] === 17'h00028);
    wire SLL_W1     = (inst1[31:15] === 17'h0002E);
    wire SRL_W1     = (inst1[31:15] === 17'h0002F);
    wire SRA_W1     = (inst1[31:15] === 17'h00030);
    wire SLT_W1     = (inst1[31:15] === 17'h00024);
    wire SLTU_W1    = (inst1[31:15] === 17'h00025);
    wire MUL_W1     = (inst1[31:15] === 17'h00038);
    wire MULH_W1    = (inst1[31:15] === 17'h00039);
    wire MULH_WU1   = (inst1[31:15] === 17'h0003A);
    wire DIV_W1     = (inst1[31:15] === 17'h00040);
    wire DIV_WU1    = (inst1[31:15] === 17'h00042);
    wire MOD_W1     = (inst1[31:15] === 17'h00041);
    wire MOD_WU1    = (inst1[31:15] === 17'h00043);
    wire SLLI_W1    = (inst1[31:15] === 17'h00081);
    wire SRLI_W1    = (inst1[31:15] === 17'h00089);
    wire SRAI_W1    = (inst1[31:15] === 17'h00091);
    wire ADDI_W1    = (inst1[31:22] === 10'h00A  );
    wire ANDI1      = (inst1[31:22] === 10'h00D  );
    wire ORI1       = (inst1[31:22] === 10'h00E  );
    wire XORI1      = (inst1[31:22] === 10'h00F  );
    wire SLTI1      = (inst1[31:22] === 10'h008  );
    wire SLTUI1     = (inst1[31:22] === 10'h009  );
    wire LD_B1      = (inst1[31:22] === 10'h0A0  );
    wire LD_BU1     = (inst1[31:22] === 10'h0A8  );
    wire LD_H1      = (inst1[31:22] === 10'h0A1  );
    wire LD_HU1     = (inst1[31:22] === 10'h0A9  );
    wire LD_W1      = (inst1[31:22] === 10'h0A2  );
    wire ST_B1      = (inst1[31:22] === 10'h0A4  );
    wire ST_H1      = (inst1[31:22] === 10'h0A5  );
    wire ST_W1      = (inst1[31:22] === 10'h0A6  );
    wire LU12I_W1   = (inst1[31:25] === 7'h0A    );
    wire PCADDU12I1 = (inst1[31:25] === 7'h0E    );
    wire BEQ1       = (inst1[31:26] === 6'h16    );
    wire BNE1       = (inst1[31:26] === 6'h17    );
    wire BLT1       = (inst1[31:26] === 6'h18    );
    wire BLTU1      = (inst1[31:26] === 6'h1A    );
    wire BGE1       = (inst1[31:26] === 6'h19    );
    wire BGEU1      = (inst1[31:26] === 6'h1B    );
    wire JIRL1      = (inst1[31:26] === 6'h13    );
    wire B1         = (inst1[31:26] === 6'h14    );
    wire BL1        = (inst1[31:26] === 6'h15    );

    wire TYPE_3R_1    = ADD_W1 | SUB_W1  | AND1 | OR1 | XOR1 | NOR1 | SLL_W1 | SRL_W1 | SRA_W1 | SLT_W1 | SLTU_W1 | 
                      MUL_W1 | MULH_W1 | MULH_WU1 | DIV_W1 | DIV_WU1 | MOD_W1 | MOD_WU1;
    wire TYPE_2RI5_1  = SLLI_W1 | SRLI_W1 | SRAI_W1;
    wire TYPE_2RI12_1 = ADDI_W1 | ANDI1 | ORI1 | XORI1 | SLTI1 | SLTUI1;
    wire LOAD_1       = LD_B1 | LD_BU1 | LD_H1 | LD_HU1 | LD_W1;
    wire STORE_1      = ST_B1 | ST_H1 | ST_W1;
    wire TYPE_2RI16_1 = BEQ1 | BNE1 | BLT1 | BLTU1 | BGE1 | BGEU1;

    wire ADD_W2     = (inst2[31:15] === 17'h00020);
    wire SUB_W2     = (inst2[31:15] === 17'h00022);
    wire AND2       = (inst2[31:15] === 17'h00029);
    wire OR2        = (inst2[31:15] === 17'h0002A);
    wire XOR2       = (inst2[31:15] === 17'h0002B);
    wire NOR2       = (inst2[31:15] === 17'h00028);
    wire SLL_W2     = (inst2[31:15] === 17'h0002E);
    wire SRL_W2     = (inst2[31:15] === 17'h0002F);
    wire SRA_W2     = (inst2[31:15] === 17'h00030);
    wire SLT_W2     = (inst2[31:15] === 17'h00024);
    wire SLTU_W2    = (inst2[31:15] === 17'h00025);
    wire MUL_W2     = (inst2[31:15] === 17'h00038);
    wire MULH_W2    = (inst2[31:15] === 17'h00039);
    wire MULH_WU2   = (inst2[31:15] === 17'h0003A);
    wire DIV_W2     = (inst2[31:15] === 17'h00040);
    wire DIV_WU2    = (inst2[31:15] === 17'h00042);
    wire MOD_W2     = (inst2[31:15] === 17'h00041);
    wire MOD_WU2    = (inst2[31:15] === 17'h00043);
    wire SLLI_W2    = (inst2[31:15] === 17'h00081);
    wire SRLI_W2    = (inst2[31:15] === 17'h00089);
    wire SRAI_W2    = (inst2[31:15] === 17'h00091);
    wire ADDI_W2    = (inst2[31:22] === 10'h00A  );
    wire ANDI2      = (inst2[31:22] === 10'h00D  );
    wire ORI2       = (inst2[31:22] === 10'h00E  );
    wire XORI2      = (inst2[31:22] === 10'h00F  );
    wire SLTI2      = (inst2[31:22] === 10'h008  );
    wire SLTUI2     = (inst2[31:22] === 10'h009  );
    wire LD_B2      = (inst2[31:22] === 10'h0A0  );
    wire LD_BU2     = (inst2[31:22] === 10'h0A8  );
    wire LD_H2      = (inst2[31:22] === 10'h0A1  );
    wire LD_HU2     = (inst2[31:22] === 10'h0A9  );
    wire LD_W2      = (inst2[31:22] === 10'h0A2  );
    wire ST_B2      = (inst2[31:22] === 10'h0A4  );
    wire ST_H2      = (inst2[31:22] === 10'h0A5  );
    wire ST_W2      = (inst2[31:22] === 10'h0A6  );
    wire LU12I_W2   = (inst2[31:25] === 7'h0A    );
    wire PCADDU12I2 = (inst2[31:25] === 7'h0E    );
    wire BEQ2       = (inst2[31:26] === 6'h16    );
    wire BNE2       = (inst2[31:26] === 6'h17    );
    wire BLT2       = (inst2[31:26] === 6'h18    );
    wire BLTU2      = (inst2[31:26] === 6'h1A    );
    wire BGE2       = (inst2[31:26] === 6'h19    );
    wire BGEU2      = (inst2[31:26] === 6'h1B    );
    wire JIRL2      = (inst2[31:26] === 6'h13    );
    wire B2         = (inst2[31:26] === 6'h14    );
    wire BL2        = (inst2[31:26] === 6'h15    );

    wire TYPE_3R_2    = ADD_W2 | SUB_W2  | AND2 | OR2 | XOR2 | NOR2 | SLL_W2 | SRL_W2 | SRA_W2 | SLT_W2 | SLTU_W2 | 
                      MUL_W2 | MULH_W2 | MULH_WU2 | DIV_W2 | DIV_WU2 | MOD_W2 | MOD_WU2;
    wire TYPE_2RI5_2  = SLLI_W2 | SRLI_W2 | SRAI_W2;
    wire TYPE_2RI12_2 = ADDI_W2 | ANDI2 | ORI2 | XORI2 | SLTI2 | SLTUI2;
    wire LOAD_2       = LD_B2 | LD_BU2 | LD_H2 | LD_HU2 | LD_W2;
    wire STORE_2      = ST_B2 | ST_H2 | ST_W2;
    wire TYPE_2RI16_2 = BEQ2 | BNE2 | BLT2 | BLTU2 | BGE2 | BGEU2;

    wire id1_rf_we = TYPE_3R_1 | TYPE_2RI5_1 | TYPE_2RI12_1 | PCADDU12I1 | LU12I_W1 | LOAD_1 | JIRL1 | BL1;
    wire [4:0] id1_wR = !BL1 ? inst1[4:0] : 5'h1;
    wire id2_rR1_re = !PCADDU12I2;
    wire id2_rR2_re = TYPE_3R_2 | STORE_2 | TYPE_2RI16_2;
    wire [4:0] id2_rR1 = !LU12I_W2 ? inst2[9:5] : 5'h0;
    wire [4:0] id2_rR2 = (STORE_2 | TYPE_2RI16_2) ? inst2[4:0] : inst2[14:10];


    assign both_ldst = (inst1[31:26] == 6'b001010) && (inst2[31:26] == 6'b001010);

    assign raw_hazard = id1_rf_we && (id1_wR != 5'd0) && 
                        (id2_rR1_re && (id1_wR == id2_rR1) || id2_rR2_re && (id1_wR == id2_rR2));


endmodule
