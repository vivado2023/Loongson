`timescale 1ns / 1ps

module cache_rreq_bridge #(
    parameter BLK_LEN = 4
)(
    input  wire         rstn      ,
    input  wire         cpu_clk   ,
    input  wire         w_hold    ,     // 有效则表示总线收到写数据请求（每个请求只有效一个SRAM时钟）
    input  wire         r_hold    ,     // 有效则表示总线收到读数据请求（每个请求只有效一个SRAM时钟）
    // Cache Read Interface
    output wire         dev_rrdy  ,     // 给Cache读主存的就绪信号（就绪时Cache才能发出读主存请求）
    input  wire         cpu_ren   ,     // Cache的读主存使能信号
    input  wire [31:0]  cpu_raddr ,     // Cache的读主存地址
    output reg          dev_rvalid,     // 返回给Cache的数据有效信号（有效n个周期则返回n个有效数据）
    output reg  [31:0]  dev_rdata ,     // 返回给Cache的读主存数据
    // SRAM-BUS Interface
    input  wire         bus_uclk  ,     // SRAM时钟
    output wire         bus_en    ,     // SRAM使能信号
    output wire [31:0]  bus_raddr ,     // 读SRAM地址
    input  wire [31:0]  bus_rdata       // 读SRAM数据
);

    wire [31:0] fifo_raddr;
    wire        fifo_empty;
    wire        fifo_rd_en = !(w_hold | r_hold) & !fifo_empty;

    async_fifo u_rreq_fifo (
        .rstn       (rstn),
        // Write Port
        .wr_clk     (cpu_clk),
        .wr_en      (cpu_ren),
        .din        (cpu_raddr),
        .full       (),
        // Read Port
        .rd_clk     (bus_uclk),
        .rd_en      (fifo_rd_en),
        .dout       (fifo_raddr),   // word-address
        .empty      (fifo_empty)
    );

    assign dev_rrdy = fifo_empty;

    // Cache Read
    reg  fifo_rd_en_r;
    wire new_rreq = !fifo_rd_en_r & fifo_rd_en;  // posedge of fifo_rd_en
    always @(posedge bus_uclk) fifo_rd_en_r <= fifo_rd_en;

    wire        rd_peripheral = (fifo_raddr[31:16] == 16'hBFAF);
    // fifo_raddr是从FIFO取出的读请求地址, rd_word_addr是总线向下游设备发出的第一个读地址
    wire [31:0] rd_word_addr  = {2'h0, fifo_raddr[31:2]};
    reg         ren_r;

    // 对同一个读请求，总线读取下游设备的第一个地址是rd_word_addr, 后续以rd_addr为读地址
    reg  [ 7:0] rd_cnt;     // 标记总线正在发出第几个读地址的计数器
    reg  [31:0] rd_addr;

    // read_end: 总线读操作结束的标志位
    // Peripheral: read a 32bit-word ; Memory: read a cache-block
    wire        read_end  = rd_peripheral ? (rd_cnt == 8'h1) :
                                            (rd_cnt == BLK_LEN) & !(w_hold | w_hold_r);

    // new_rreq有效时, 总线发出第一个读地址; ren_f有效时, 总线发出后续的读地址
    wire        ren_f     = (BLK_LEN > 1) & (ren_r | (rd_cnt >= BLK_LEN-1) & (w_hold | w_hold_r));
    // rd_bus_en有效表示总线的读操作尚未结束
    wire        rd_bus_en = new_rreq | ren_f;

    reg         r_hold_r, w_hold_r;     // 数据读请求、数据写请求的下一拍
    always @(posedge bus_uclk or negedge rstn) r_hold_r <= !rstn ? 1'b0 : r_hold;
    always @(posedge bus_uclk or negedge rstn) w_hold_r <= !rstn ? 1'b0 : w_hold;

    always @(posedge bus_uclk or negedge rstn) begin
        if (!rstn) begin
            ren_r  <= 1'b0;
            rd_cnt <= 8'h0;
        end else begin
            if ((rd_cnt == BLK_LEN) & !w_hold)  ren_r <= 1'b0;
            else if (new_rreq & !rd_peripheral) ren_r <= 1'b1;

            if      (read_end)           rd_cnt <= 8'h0;
            else if (rd_bus_en & w_hold) rd_cnt <= rd_cnt - 8'h1;   // 考虑读请求过程中，总线收到写数据请求时，rd_cnt如何变化
            else if (rd_bus_en & r_hold) rd_cnt <= rd_cnt;          // 考虑读请求过程中，总线收到读数据请求时，rd_cnt如何变化
            else if (rd_bus_en)          rd_cnt <= rd_cnt + 8'h1;

            if      (new_rreq)       rd_addr <= rd_word_addr + 32'h1;
            else if (ren_f & w_hold) rd_addr <= rd_addr - 32'h1;   // 考虑读请求过程中，总线收到写数据请求时，读地址如何变化
            else if (ren_f & r_hold) rd_addr <= rd_addr;           // 考虑读请求过程中，总线收到读数据请求时，读地址如何变化
            else if (ren_f)          rd_addr <= rd_addr + 32'h1;
        end
    end

    // Generate Output
    wire       rd_sram = !(w_hold | w_hold_r | r_hold_r) & (0 < rd_cnt) & (rd_cnt < BLK_LEN) |
                         !(w_hold | w_hold_r           ) & (rd_cnt == BLK_LEN);
    reg [ 7:0] cwf_cnt;
    always @(posedge cpu_clk or negedge rstn) begin
        if (!rstn) begin
            dev_rvalid <= 1'b0;
        end else begin
            if ((cwf_cnt < rd_cnt) & (rd_peripheral | rd_sram)) begin
                dev_rvalid <= 1'b1;
                dev_rdata  <= bus_rdata;
            end else begin
                dev_rvalid <= 1'b0;
            end
        end
    end

    always @(posedge cpu_clk or negedge rstn) begin
        if (!rstn) begin
            cwf_cnt <= 8'h0;
        end else begin
            if (fifo_rd_en) begin
                cwf_cnt <= 8'h0;
            end else if ((cwf_cnt < rd_cnt) & (rd_peripheral | rd_sram)) begin
                cwf_cnt <= cwf_cnt + 8'h1;
            end
        end
    end

    assign bus_en    = rd_bus_en & !(w_hold | r_hold);
    assign bus_raddr = ren_f ? rd_addr : (rd_peripheral ? fifo_raddr : rd_word_addr);   // 读外设用字节地址, 读主存用字地址

endmodule