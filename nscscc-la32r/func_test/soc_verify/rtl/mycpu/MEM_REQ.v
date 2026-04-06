`timescale 1ns / 1ps

`include "defines.vh"

module MEM_REQ (
    input  wire         clk           ,
    input  wire         rstn          ,
    input  wire         ex_valid      ,
    input  wire         ldst_suspend  ,
    input  wire [ 1:0]  mem_wd_sel    ,
    input  wire [31:0]  mem_ram_addr  ,

    input  wire [ 2:0]  mem_ram_ext_op,
    output reg  [ 3:0]  da_ren        ,
    output wire [31:0]  da_addr       ,

    input  wire [ 3:0]  mem_ram_we    ,
    input  wire [31:0]  mem_ram_wdata ,
    output reg  [ 3:0]  da_wen        ,
    output reg  [31:0]  da_wdata      
);

    reg        send_ldst_req;       // only valid at the first clk of mem stage
    wire [1:0] offset = mem_ram_addr[1:0];

    always @(posedge clk or negedge rstn) begin
        send_ldst_req <= !rstn ? 1'b0 : ex_valid & !ldst_suspend;
    end

//确定读写地址
    assign da_addr = mem_ram_addr;

//确定STORE指令的写使能da_wen和写数据da_wdata
    always @(*) begin
        if (send_ldst_req & (mem_wd_sel == `WD_RAM)) begin    
            case (mem_ram_we)
                `RAM_WE_B: da_wen = 4'h1 << offset;
                `RAM_WE_H: da_wen = (offset == 2'h0) ? 4'h3 : (offset == 2'h2) ? 4'hC : 4'h0;
                `RAM_WE_W: da_wen = (offset == 2'h0) ? 4'hF : 4'h0;
                default  : da_wen = 4'h0;
            endcase
        end
        else da_wen   = 4'h0;
    end

    always @(*) begin
        if (send_ldst_req & (mem_wd_sel == `WD_RAM)) begin    
            case (mem_ram_we)
                `RAM_WE_B: da_wdata = {mem_ram_wdata[7:0], mem_ram_wdata[7:0], mem_ram_wdata[7:0], mem_ram_wdata[7:0]};
                `RAM_WE_H: da_wdata = {mem_ram_wdata[15:0], mem_ram_wdata[15:0]};
                `RAM_WE_W: da_wdata = mem_ram_wdata;
                default  : da_wdata = mem_ram_wdata;
            endcase
        end
    end



//确定LOAD指令读使能da_ren
    always @(*) begin
        if (send_ldst_req & (mem_wd_sel == `WD_RAM) & (mem_ram_we == `RAM_WE_N)) begin
            case (mem_ram_ext_op)
                `RAM_EXT_B  : da_ren = 4'hF;
                `RAM_EXT_BU : da_ren = 4'hF;
                `RAM_EXT_H  : da_ren = (offset == 2'h0 || offset == 2'h2) ? 4'hF : 4'h0;
                `RAM_EXT_HU : da_ren = (offset == 2'h0 || offset == 2'h2) ? 4'hF : 4'h0;
                `RAM_EXT_W  : da_ren = (offset == 2'h0) ? 4'hF : 4'h0;
                default     : da_ren = 4'h0; 
            endcase
        end 
        else da_ren = 4'h0;
    end

endmodule
