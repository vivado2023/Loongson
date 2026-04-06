`timescale 1ns / 1ps

`include "defines.vh"

module DCache (
    input  wire         cpu_rstn, 
    input  wire         cpu_clk,
    // Interface to CPU
    input  wire [ 3:0]  data_ren,       // CPU发起读请求（按字节使能）（cpu——>bus）
    input  wire [31:0]  data_addr,      // CPU的读写地址             （cpu——>bus）
    output reg          data_valid,     // 返回给CPU的读数据有效信号  （bus——>cpu）
    output reg  [31:0]  data_rdata,     // 返回给CPU的读数据（bus——>cpu）
    input  wire [ 3:0]  data_wen,       // CPU发起写请求（按字节使能）（cpu——>bus）
    input  wire [31:0]  data_wdata,     // CPU的写数据               （cpu——>bus）
    output reg          data_wresp,     // 写响应信号，表示写请求已完成（bus——>cpu）
    // Interface to Write Bus
    input  wire         dev_wrdy,       // 总线是否能接收写请求
    output reg  [ 3:0]  cpu_wen,        // 写请求使能（cpu——>bus）
    output reg  [31:0]  cpu_waddr,      // 写请求地址（cpu——>bus）
    output reg  [31:0]  cpu_wdata,      // 写请求数据（cpu——>bus）
    // Interface to Read Bus
    input  wire         dev_rrdy,       // 总线是否能接收读请求
    output reg  [ 3:0]  cpu_ren,        // 读请求使能（cpu——>bus）
    output reg  [31:0]  cpu_raddr,      // 读请求地址（cpu——>bus）
    input  wire         dev_rvalid,     // 读请求返回的数据是否有效（bus——>cpu）
    input  wire [31:0]  dev_rdata       // 读请求返回的数据（bus——>cpu）
);

`ifdef ENABLE_DCACHE

    localparam INDEX_WID  = $clog2(`CACHE_BLK_NUM / 2);
    localparam OFFSET_WID = $clog2(`CACHE_BLK_LEN) + 2; 
    localparam TAG_WID    = 32 - INDEX_WID - OFFSET_WID;
    localparam BLK_WID    = `CACHE_BLK_SIZE + TAG_WID + 1;

    reg [31:0] data_addr_r;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn)                   data_addr_r <= `PC_INIT_VAL;
        else if(|data_ren || |data_wen) data_addr_r <= data_addr;
    end

    //检测地址信号的高16位是否等于16'hBFAF,表示访问外设；访问外设时，直接从主存中读写数据
    wire uncached = (data_addr[31:16] == 16'hBFAF); 

    //锁存读写使能信号，使得读写在几个周期后依旧能有使能信号
    reg is_r, is_w;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) begin
            is_r <= 1'b0;
            is_w <= 1'b0;
        end else begin
            if(|data_ren && !uncached) begin
                is_r <= 1'b1;
                is_w <= 1'b0;
            end 
            else if(|data_wen && !uncached) begin
                is_r <= 1'b0;
                is_w <= 1'b1;
            end
            else if(hit_r0 || hit_r1) begin //表示ld指令结束
                is_r <= 1'b0;
                is_w <= 1'b0;
            end
            else if(cache_we0 || cache_we1) begin //表示st指令结束
                is_r <= 1'b0;
                is_w <= 1'b0;
            end
        end
    end

    //缓存写使能信号一个周期，写主存信号需要在写使能的下个周期赋值
    reg [3:0]  data_wen_r;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) data_wen_r <= 4'b0;
        else          data_wen_r <= data_wen;
    end

    wire [TAG_WID-1:0]    tag_from_cpu = data_addr_r[31:32-TAG_WID];
    wire [INDEX_WID-1:0]  cache_index  = data_addr[32-TAG_WID-1:32-TAG_WID-INDEX_WID];
    wire [INDEX_WID-1:0]  cache_index_r= data_addr_r[32-TAG_WID-1:32-TAG_WID-INDEX_WID];
    wire [OFFSET_WID-1:0] offset       = data_addr_r[OFFSET_WID-1:0];
    //写缓存时要写入当前地址，读缓存时要提前读
    wire [INDEX_WID-1:0]  blk_addr = (current_state == REFILL && recv_cnt==`CACHE_BLK_LEN || is_w) 
                                     ? cache_index_r : cache_index;

    wire [BLK_WID-1:0] cache_line_r0, cache_line_r1;

    wire valid_bit0 = cache_line_r0[BLK_WID-1];
    wire valid_bit1 = cache_line_r1[BLK_WID-1];

    wire [TAG_WID-1:0] tag_from_cache0 = cache_line_r0[BLK_WID-2:BLK_WID-TAG_WID-1];
    wire [TAG_WID-1:0] tag_from_cache1 = cache_line_r1[BLK_WID-2:BLK_WID-TAG_WID-1];

    wire [`CACHE_BLK_SIZE-1:0] cache_data_blk0 = cache_line_r0[`CACHE_BLK_SIZE-1:0];
    wire [`CACHE_BLK_SIZE-1:0] cache_data_blk1 = cache_line_r1[`CACHE_BLK_SIZE-1:0];


    wire hit_r0 = valid_bit0 && (tag_from_cache0 == tag_from_cpu) && is_r;
    wire hit_r1 = valid_bit1 && (tag_from_cache1 == tag_from_cpu) && is_r;
    wire hit_w0 = valid_bit0 && (tag_from_cache0 == tag_from_cpu) && is_w;
    wire hit_w1 = valid_bit1 && (tag_from_cache1 == tag_from_cpu) && is_w;
    wire [`CACHE_BLK_SIZE-1:0] hit_data_blk = {`CACHE_BLK_SIZE{hit_r0 || hit_w0}} & cache_data_blk0 |
                                              {`CACHE_BLK_SIZE{hit_r1 || hit_w1}} & cache_data_blk1;


    reg [1:0] use_bit [`CACHE_BLK_NUM/2-1:0]; // 01: 块0最近使用，10: 块1最近使用
    integer i;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) begin
            for(i=0;i<`CACHE_BLK_NUM/2;i=i+1) use_bit[i] <= 2'b01;
        end else begin
            if(hit_r0)      use_bit[cache_index_r] <= 2'b01;
            else if(hit_r1) use_bit[cache_index_r] <= 2'b10;
        end
    end

    // 写使能选择，读缺失or写；写的时候，如果命中1路就写到1路，否则写到0路
    wire cache_we0 = is_r ? (use_bit[cache_index_r]==2'b10 && recv_cnt==`CACHE_BLK_LEN) : (hit_w0 || (is_w && !hit_w1));
    wire cache_we1 = is_r ? (use_bit[cache_index_r]==2'b01 && recv_cnt==`CACHE_BLK_LEN) : hit_w1;
    wire [`CACHE_BLK_SIZE-1:0] cache_data = (is_w) ? cache_wdata_w : cache_wdata_r; //如果st，就选择前者；如果ld，就选择后者

    wire [BLK_WID-1:0] cache_line_w = {1'b1, tag_from_cpu, cache_data};


    blk_mem_gen_0 U_dsram0 (
        .clka(cpu_clk), 
        .wea(cache_we0), 
        .addra(blk_addr),
        .dina(cache_line_w), 
        .douta(cache_line_r0)
    );

    blk_mem_gen_0 U_dsram1 (
        .clka(cpu_clk), 
        .wea(cache_we1), 
        .addra(blk_addr),
        .dina(cache_line_w), 
        .douta(cache_line_r1)
    );

//==================== 读状态机 ====================
    localparam IDLE      = 3'b000;
    localparam TAG_CHECK = 3'b001;
    localparam RD_MEM    = 3'b010;
    localparam REFILL    = 3'b011;
    localparam UC_MEM    = 3'b100;
    localparam UC_WAIT   = 3'b101;

    reg [2:0] current_state, next_state;
    reg [OFFSET_WID:0] recv_cnt;
    reg [`CACHE_BLK_SIZE-1:0] cache_wdata_r;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        current_state <= !cpu_rstn ? IDLE : next_state;
    end

    //cache缺失时读数据
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) begin
            recv_cnt <= 0;
            cache_wdata_r <= 0;
        end else if(current_state==REFILL && dev_rvalid) begin
            recv_cnt <= recv_cnt + 1;
            cache_wdata_r <= {dev_rdata, cache_wdata_r[`CACHE_BLK_SIZE-1:32]};
        end else if(recv_cnt==`CACHE_BLK_LEN) begin
            recv_cnt <= 0;
            cache_wdata_r <= 0;
        end
    end

    always @(*) begin
        case(current_state)
            IDLE:      next_state = (|data_ren)     ? uncached ? UC_MEM    : TAG_CHECK : IDLE;
            TAG_CHECK: next_state = (hit_r0|hit_r1)            ? IDLE      : RD_MEM;
            RD_MEM:    next_state = dev_rrdy                   ? REFILL    : RD_MEM;
            REFILL:    next_state = (recv_cnt==`CACHE_BLK_LEN) ? TAG_CHECK : REFILL;
            UC_MEM:    next_state = dev_rrdy                   ? UC_WAIT   : UC_MEM;
            UC_WAIT:   next_state = dev_rvalid                 ? IDLE      : UC_WAIT;
            default:   next_state = IDLE;
        endcase
    end

    //向主存发送读数据申请
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) begin
            cpu_ren   <= 4'b0;
            cpu_raddr <= 32'b0;
        end 
        else if(current_state==RD_MEM && dev_rrdy) begin
            cpu_ren   <= 4'b1111;
            cpu_raddr <= {data_addr_r[31:OFFSET_WID],{OFFSET_WID{1'b0}}};
        end 
        else if(current_state==UC_MEM && dev_rrdy) begin
            cpu_ren   <= 4'b1111;
            cpu_raddr <= data_addr_r;
        end
        else cpu_ren <= 4'b0;
    end

    always @(*) begin
        if(current_state == TAG_CHECK) begin
            data_valid = hit_r0 | hit_r1;
            case(offset[OFFSET_WID-1:2])
                3'd0: data_rdata = hit_data_blk[31:0];
                3'd1: data_rdata = hit_data_blk[63:32];
                3'd2: data_rdata = hit_data_blk[95:64];
                3'd3: data_rdata = hit_data_blk[127:96];
                3'd4: data_rdata = hit_data_blk[159:128];
                3'd5: data_rdata = hit_data_blk[191:160];
                3'd6: data_rdata = hit_data_blk[223:192];
                3'd7: data_rdata = hit_data_blk[255:224];
            endcase
        end
        else if(current_state == UC_WAIT) begin
            data_valid = dev_rvalid;
            data_rdata = dev_rdata;
        end
        else begin
            data_valid = 1'b0;
            data_rdata = 32'b0;
        end
    end

//==================== 写状态机 ====================
    localparam W_IDLE = 2'b00;
    localparam W_MEM  = 2'b01;
    localparam W_WAIT = 2'b11;

    reg [1:0] w_state, w_next;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        w_state <= !cpu_rstn ? W_IDLE : w_next;
    end

    reg [`CACHE_BLK_SIZE-1:0] cache_wdata_w;
    always @(*) begin
        if(data_wen_r == 4'b1111) begin
            case(offset[OFFSET_WID-1:2])
                3'd0: cache_wdata_w = {hit_data_blk[255:32], data_wdata};
                3'd1: cache_wdata_w = {hit_data_blk[255:64], data_wdata, hit_data_blk[31:0]};
                3'd2: cache_wdata_w = {hit_data_blk[255:96], data_wdata, hit_data_blk[63:0]};
                3'd3: cache_wdata_w = {hit_data_blk[255:128], data_wdata, hit_data_blk[95:0]};
                3'd4: cache_wdata_w = {hit_data_blk[255:160], data_wdata, hit_data_blk[127:0]};
                3'd5: cache_wdata_w = {hit_data_blk[255:192], data_wdata, hit_data_blk[159:0]};
                3'd6: cache_wdata_w = {hit_data_blk[255:224], data_wdata, hit_data_blk[191:0]};
                3'd7: cache_wdata_w = {data_wdata, hit_data_blk[223:0]};
            endcase
        end
        else if(data_wen_r == 4'b0011) begin
            case(offset[OFFSET_WID-1:2])
                3'd0: cache_wdata_w = {hit_data_blk[255:16], data_wdata[15:0]};
                3'd1: cache_wdata_w = {hit_data_blk[255:48], data_wdata[15:0], hit_data_blk[31:0]};
                3'd2: cache_wdata_w = {hit_data_blk[255:80], data_wdata[15:0], hit_data_blk[63:0]};
                3'd3: cache_wdata_w = {hit_data_blk[255:112], data_wdata[15:0], hit_data_blk[95:0]};
                3'd4: cache_wdata_w = {hit_data_blk[255:144], data_wdata[15:0], hit_data_blk[127:0]};
                3'd5: cache_wdata_w = {hit_data_blk[255:176], data_wdata[15:0], hit_data_blk[159:0]};
                3'd6: cache_wdata_w = {hit_data_blk[255:208], data_wdata[15:0], hit_data_blk[191:0]};
                3'd7: cache_wdata_w = {hit_data_blk[255:240], data_wdata[15:0], hit_data_blk[223:0]};
            endcase
        end
        else if(data_wen_r == 4'b1100) begin
            case(offset[OFFSET_WID-1:2])
                3'd0: cache_wdata_w = {hit_data_blk[255:16], data_wdata[31:16], hit_data_blk[15:0]};
                3'd1: cache_wdata_w = {hit_data_blk[255:64], data_wdata[31:16], hit_data_blk[47:0]};
                3'd2: cache_wdata_w = {hit_data_blk[255:96], data_wdata[31:16], hit_data_blk[79:0]};
                3'd3: cache_wdata_w = {hit_data_blk[255:128], data_wdata[31:16], hit_data_blk[111:0]};
                3'd4: cache_wdata_w = {hit_data_blk[255:160], data_wdata[31:16], hit_data_blk[143:0]};
                3'd5: cache_wdata_w = {hit_data_blk[255:192], data_wdata[31:16], hit_data_blk[175:0]};
                3'd6: cache_wdata_w = {hit_data_blk[255:224], data_wdata[31:16], hit_data_blk[207:0]};
                3'd7: cache_wdata_w = {data_wdata[31:16], hit_data_blk[239:0]};
            endcase
        end
        else if(data_wen_r == 4'b0001) begin
            case(offset[OFFSET_WID-1:2])
                3'd0: cache_wdata_w = {hit_data_blk[255:8], data_wdata[7:0]};
                3'd1: cache_wdata_w = {hit_data_blk[255:40], data_wdata[7:0], hit_data_blk[31:0]};
                3'd2: cache_wdata_w = {hit_data_blk[255:72], data_wdata[7:0], hit_data_blk[63:0]};
                3'd3: cache_wdata_w = {hit_data_blk[255:104], data_wdata[7:0], hit_data_blk[95:0]};
                3'd4: cache_wdata_w = {hit_data_blk[255:136], data_wdata[7:0], hit_data_blk[127:0]};
                3'd5: cache_wdata_w = {hit_data_blk[255:168], data_wdata[7:0], hit_data_blk[159:0]};
                3'd6: cache_wdata_w = {hit_data_blk[255:200], data_wdata[7:0], hit_data_blk[191:0]};
                3'd7: cache_wdata_w = {hit_data_blk[255:232], data_wdata[7:0], hit_data_blk[223:0]};
            endcase
        end
        else if(data_wen_r == 4'b0010) begin
            case(offset[OFFSET_WID-1:2])
                3'd0: cache_wdata_w = {hit_data_blk[255:16], data_wdata[15:8], hit_data_blk[7:0]};
                3'd1: cache_wdata_w = {hit_data_blk[255:48], data_wdata[15:8], hit_data_blk[39:0]};
                3'd2: cache_wdata_w = {hit_data_blk[255:80], data_wdata[15:8], hit_data_blk[71:0]};
                3'd3: cache_wdata_w = {hit_data_blk[255:112], data_wdata[15:8], hit_data_blk[103:0]};
                3'd4: cache_wdata_w = {hit_data_blk[255:144], data_wdata[15:8], hit_data_blk[135:0]};
                3'd5: cache_wdata_w = {hit_data_blk[255:176], data_wdata[15:8], hit_data_blk[167:0]};
                3'd6: cache_wdata_w = {hit_data_blk[255:208], data_wdata[15:8], hit_data_blk[199:0]};
                3'd7: cache_wdata_w = {hit_data_blk[255:240], data_wdata[15:8], hit_data_blk[231:0]};
            endcase
        end
        else if(data_wen_r == 4'b0100) begin
            case(offset[OFFSET_WID-1:2])
                3'd0: cache_wdata_w = {hit_data_blk[255:24], data_wdata[23:16], hit_data_blk[15:0]};
                3'd1: cache_wdata_w = {hit_data_blk[255:56], data_wdata[23:16], hit_data_blk[47:0]};
                3'd2: cache_wdata_w = {hit_data_blk[255:88], data_wdata[23:16], hit_data_blk[79:0]};
                3'd3: cache_wdata_w = {hit_data_blk[255:120], data_wdata[23:16], hit_data_blk[111:0]};
                3'd4: cache_wdata_w = {hit_data_blk[255:152], data_wdata[23:16], hit_data_blk[143:0]};
                3'd5: cache_wdata_w = {hit_data_blk[255:184], data_wdata[23:16], hit_data_blk[175:0]};
                3'd6: cache_wdata_w = {hit_data_blk[255:216], data_wdata[23:16], hit_data_blk[207:0]};
                3'd7: cache_wdata_w = {hit_data_blk[255:248], data_wdata[23:16], hit_data_blk[239:0]};
            endcase
        end
        else if(data_wen_r == 4'b1000) begin
            case(offset[OFFSET_WID-1:2])
                3'd0: cache_wdata_w = {hit_data_blk[255:32], data_wdata[31:24], hit_data_blk[23:0]};
                3'd1: cache_wdata_w = {hit_data_blk[255:64], data_wdata[31:24], hit_data_blk[55:0]};
                3'd2: cache_wdata_w = {hit_data_blk[255:96], data_wdata[31:24], hit_data_blk[87:0]};
                3'd3: cache_wdata_w = {hit_data_blk[255:128], data_wdata[31:24], hit_data_blk[119:0]};
                3'd4: cache_wdata_w = {hit_data_blk[255:160], data_wdata[31:24], hit_data_blk[151:0]};
                3'd5: cache_wdata_w = {hit_data_blk[255:192], data_wdata[31:24], hit_data_blk[183:0]};
                3'd6: cache_wdata_w = {hit_data_blk[255:224], data_wdata[31:24], hit_data_blk[215:0]};
                3'd7: cache_wdata_w = {data_wdata[31:24], hit_data_blk[247:0]};
            endcase
        end
    end

    always @(*) begin
        case(w_state)
            W_IDLE: w_next = (|data_wen) ? W_MEM : W_IDLE;
            W_MEM : w_next = dev_wrdy    ? W_WAIT : W_MEM;
            W_WAIT: w_next = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) begin
            cpu_wen    <= 4'b0;
            data_wresp <= 1'b0;
            cpu_waddr  <= 32'b0;
            cpu_wdata  <= 32'b0;
        end else begin
            case(w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;
                    cpu_wen    <= 4'b0;
                    cpu_waddr  <= 32'b0;
                    cpu_wdata  <= 32'b0;
                end
                W_MEM: begin
                    if(dev_wrdy) begin
                        cpu_wen   <= data_wen_r;
                        cpu_waddr <= data_addr_r;
                        cpu_wdata <= data_wdata;
                    end
                    else begin
                        cpu_wen   <= 4'b0;
                        cpu_waddr <= 32'b0;
                        cpu_wdata <= 32'b0;
                    end
                end
                W_WAIT: begin
                    data_wresp <= 1'b1;
                    cpu_wen    <= 4'b0;
                    cpu_waddr  <= 32'b0;
                    cpu_wdata  <= 32'b0;
                end
            endcase
        end
    end

`else

    localparam R_IDLE  = 2'b00;
    localparam R_STAT0 = 2'b01;
    localparam R_STAT1 = 2'b11;
    reg [1:0] r_state, r_nstat;
    reg [3:0] ren_r;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        r_state <= !cpu_rstn ? R_IDLE : r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE:  r_nstat = (|data_ren) ? (dev_rrdy ? R_STAT1 : R_STAT0) : R_IDLE;
            R_STAT0: r_nstat = dev_rrdy ? R_STAT1 : R_STAT0;
            R_STAT1: r_nstat = dev_rvalid ? R_IDLE : R_STAT1;
            default: r_nstat = R_IDLE;
        endcase
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            data_valid <= 1'b0;
            cpu_ren    <= 4'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    data_valid <= 1'b0;

                    if (|data_ren) begin
                        if (dev_rrdy)
                            cpu_ren <= data_ren;
                        else
                            ren_r   <= data_ren;

                        cpu_raddr <= data_addr;
                    end else
                        cpu_ren   <= 4'h0;
                end
                R_STAT0: begin
                    cpu_ren    <= dev_rrdy ? ren_r : 4'h0;
                end   
                R_STAT1: begin
                    cpu_ren    <= 4'h0;
                    data_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    data_rdata <= dev_rvalid ? dev_rdata : 32'h0;
                end
                default: begin
                    data_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end 
            endcase
        end
    end

    localparam W_IDLE  = 2'b00;
    localparam W_STAT0 = 2'b01;
    localparam W_STAT1 = 2'b11;
    reg  [1:0] w_state, w_nstat;
    reg  [3:0] wen_r;
    wire       wr_resp = dev_wrdy & (cpu_wen == 4'h0) ? 1'b1 : 1'b0;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        w_state <= !cpu_rstn ? W_IDLE : w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE:  w_nstat = (|data_wen) ? (dev_wrdy ? W_STAT1 : W_STAT0) : W_IDLE;
            W_STAT0: w_nstat = dev_wrdy ? W_STAT1 : W_STAT0;
            W_STAT1: w_nstat = wr_resp ? W_IDLE : W_STAT1;
            default: w_nstat = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;

                    if (|data_wen) begin
                        if (dev_wrdy)
                            cpu_wen <= data_wen;
                        else
                            wen_r   <= data_wen;
                        
                        cpu_waddr  <= data_addr;
                        cpu_wdata  <= data_wdata;
                    end else
                        cpu_wen    <= 4'h0;
                end
                W_STAT0: begin
                    cpu_wen    <= dev_wrdy ? wen_r : 4'h0;
                end
                W_STAT1: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= wr_resp ? 1'b1 : 1'b0;
                end
                default: begin
                    data_wresp <= 1'b0;
                    cpu_wen    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule
