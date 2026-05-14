`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/04/28 20:48:20
// Design Name: 
// Module Name: Wait_for_tb
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


module Wait_for_tb(
    input  wire       cpu_rstn      ,
    input  wire       cpu_clk       ,
    input wire [31:0] wb_pc1        ,
    input wire        wb_rf_we1     ,
    input wire [4:0]  wb_wR1        ,
    input wire [31:0] wb_wd1        ,
    input wire [31:0] wb_pc2        ,
    input wire        wb_rf_we2     ,
    input wire [4:0]  wb_wR2        ,
    input wire [31:0] wb_wd2        ,

    output reg [31:0] debug_wb_pc   ,
    output reg [4:0]  debug_wb_rf_we,
    output reg [4:0]  debug_wb_wR   ,
    output reg [31:0] debug_wb_wd
);

    // 一条写回信息：
    // { pc[31:0], rf_we, wR[4:0], wd[31:0] }
    localparam ENTRY_W = 32 + 1 + 5 + 32;
    localparam DEPTH   = 16;
    localparam PTR_W   = 4;   // DEPTH=16，所以指针4位即可

    reg [ENTRY_W-1:0] fifo [0:DEPTH-1];

    reg [PTR_W-1:0] head;
    reg [PTR_W-1:0] tail;
    reg [PTR_W:0]   cnt;

    wire [ENTRY_W-1:0] wb_pack1;
    wire [ENTRY_W-1:0] wb_pack2;

    assign wb_pack1 = {wb_pc1, wb_rf_we1, wb_wR1, wb_wd1};
    assign wb_pack2 = {wb_pc2, wb_rf_we2, wb_wR2, wb_wd2};

    wire fifo_empty;
    wire fifo_full;

    assign fifo_empty = (cnt == 0);
    assign fifo_full  = (cnt == DEPTH);

    always @(posedge cpu_clk) begin
        if (!cpu_rstn) begin
            head <= {PTR_W{1'b0}};
            tail <= {PTR_W{1'b0}};
            cnt  <= {(PTR_W+1){1'b0}};

            debug_wb_pc    <= 32'b0;
            debug_wb_rf_we <= 4'b0;
            debug_wb_wR    <= 5'b0;
            debug_wb_wd    <= 32'b0;
        end else begin
            // =========================================================
            // 1. 每周期从队列头弹出一条
            // =========================================================
            if (!fifo_empty) begin
                debug_wb_pc    <= fifo[head][ENTRY_W-1:ENTRY_W-32];
                debug_wb_rf_we <= {4{fifo[head][ENTRY_W-33:ENTRY_W-34]}};
                debug_wb_wR    <= fifo[head][36:32];
                debug_wb_wd    <= fifo[head][31:0];

                head <= head + 1'b1;
            end else begin
                debug_wb_pc    <= 32'b0;
                debug_wb_rf_we <= 4'b0;
                debug_wb_wR    <= 5'b0;
                debug_wb_wd    <= 32'b0;
            end

            // =========================================================
            // 2. 每周期最多写入两条，保持 wb1 -> wb2 顺序
            // =========================================================

            // 情况一：wb1 和 wb2 都有效
            if (wb_rf_we1 && wb_rf_we2) begin
                // 如果本周期会弹出一条，则等价于多出一个空位
                if (cnt <= DEPTH - 2 || (!fifo_empty && cnt <= DEPTH - 1)) begin
                    fifo[tail] <= wb_pack1;
                    fifo[tail + 1'b1] <= wb_pack2;
                    tail <= tail + 2'd2;

                    if (!fifo_empty)
                        cnt <= cnt + 1'b1;   // 入2出1，净增1
                    else
                        cnt <= cnt + 2'd2;   // 入2出0，净增2
                end
                else if (cnt <= DEPTH - 1 || !fifo_empty) begin
                    // 只剩一个空位时，只能先保存 wb1，wb2 会丢失
                    fifo[tail] <= wb_pack1;
                    tail <= tail + 1'b1;

                    if (!fifo_empty)
                        cnt <= cnt;          // 入1出1，数量不变
                    else
                        cnt <= cnt + 1'b1;   // 入1出0
                end
            end

            // 情况二：只有 wb1 有效
            else if (wb_rf_we1) begin
                if (!fifo_full || !fifo_empty) begin
                    fifo[tail] <= wb_pack1;
                    tail <= tail + 1'b1;

                    if (!fifo_empty)
                        cnt <= cnt;          // 入1出1
                    else
                        cnt <= cnt + 1'b1;   // 入1出0
                end
            end

            // 情况三：只有 wb2 有效
            else if (wb_rf_we2) begin
                if (!fifo_full || !fifo_empty) begin
                    fifo[tail] <= wb_pack2;
                    tail <= tail + 1'b1;

                    if (!fifo_empty)
                        cnt <= cnt;          // 入1出1
                    else
                        cnt <= cnt + 1'b1;   // 入1出0
                end
            end

            // 情况四：没有新的写回，只弹出
            else begin
                if (!fifo_empty)
                    cnt <= cnt - 1'b1;
                else
                    cnt <= cnt;
            end
        end
    end

endmodule
