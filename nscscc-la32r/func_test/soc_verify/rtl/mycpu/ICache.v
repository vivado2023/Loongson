`timescale 1ns / 1ps

`include "defines.vh"

module ICache (
    input  wire         cpu_rstn,       // low active
    input  wire         cpu_clk,
    // Interface to CPU
    input  wire         inst_rreq,      // CPU发起取指请求
    input  wire [31:0]  inst_addr,      // CPU的取指地址
    output reg          inst_valid,     // 返回给CPU的指令有效信号
    output reg  [31:0]  inst_out,       // 返回给CPU的指令
    input  wire         pred_error,     // 预测错误信号
    // Interface to Read Bus
    input  wire         dev_rrdy,       // 总线是否能接收请求
    output reg  [ 3:0]  cpu_ren,        // 读请求使能
    output reg  [31:0]  cpu_raddr,      // 读请求地址
    input  wire         dev_rvalid,     // 读请求返回的数据是否有效
    input  wire [31:0]  dev_rdata       // 读请求返回的数据
);

`ifdef ENABLE_ICACHE

    localparam INDEX_WID  = $clog2(`CACHE_BLK_NUM / 2);     // Cache块索引的位宽
    localparam OFFSET_WID = $clog2(`CACHE_BLK_LEN) + 2;     // 块内偏移量的位宽
    localparam TAG_WID    = 32 - INDEX_WID - OFFSET_WID;    // 块标签的位宽
    localparam BLK_WID    = `CACHE_BLK_SIZE + TAG_WID + 1;  // Cache块的位宽

    // inst_rreq和inst_addr只有效一个CPU时钟，故需在inst_rreq有效时缓存inst_addr
    reg [31:0] inst_addr_r;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn)      inst_addr_r <= `PC_INIT_VAL;
        else if (inst_rreq) inst_addr_r <= inst_addr;
    end

    // 主存地址分解（变量的位宽最好使用上面的localparam常量来表示）
    wire [TAG_WID-1:0]    tag_from_cpu = inst_addr_r[31:32-TAG_WID];     // 主存地址的TAG
    wire [INDEX_WID-1:0]  cache_index  = inst_addr[32-TAG_WID-1:32-TAG_WID-INDEX_WID]; // 读新的块时用这个
    wire [INDEX_WID-1:0]  cache_index_r= inst_addr_r[32-TAG_WID-1:32-TAG_WID-INDEX_WID]; // 写回用这个
    wire [OFFSET_WID-1:0] offset       = inst_addr_r[OFFSET_WID-1:0];     // 32位字偏移量

    wire [INDEX_WID-1:0] blk_addr;

    assign blk_addr =((current_state == REFILL) ? cache_idx_wr : 
                     ((current_state == WAIT)&&!pred_error ? cache_index_r : cache_index));

    wire [BLK_WID-1:0] cache_line_r0;                                              // 从ICache存储体0读出的Cache块
    wire [BLK_WID-1:0] cache_line_r1;                                              // 从ICache存储体1读出的Cache块

    wire               valid_bit0    = cache_line_r0[BLK_WID-1];                   // Cache组内第0块的有效位
    wire               valid_bit1    = cache_line_r1[BLK_WID-1];                   // Cache组内第1块的有效位
    wire [TAG_WID-1:0] tag_from_set0 = cache_line_r0[BLK_WID-2:BLK_WID-TAG_WID-1]; // Cache组内第0块的TAG
    wire [TAG_WID-1:0] tag_from_set1 = cache_line_r1[BLK_WID-2:BLK_WID-TAG_WID-1]; // Cache组内第1块的TAG


    wire hit0 = (valid_bit0 === 1'b1) && (tag_from_set0 === tag_from_cpu); // Cache组内第0块的命中信号
    wire hit1 = (valid_bit1 === 1'b1) && (tag_from_set1 === tag_from_cpu); // Cache组内第1块的命中信号

    //根据命中情况选择传回的数据块（如果命中块0则返回块0的数据，否则如果命中块1则返回块1的数据，否则返回全0）
    wire [`CACHE_BLK_SIZE-1:0] hit_data_blk = {`CACHE_BLK_SIZE{hit0}} & cache_line_r0[`CACHE_BLK_SIZE-1:0] |
                                              {`CACHE_BLK_SIZE{hit1}} & cache_line_r1[`CACHE_BLK_SIZE-1:0]; 

    // 记录第i个Cache组内的Cache块的被访问情况（比如块0被访问，则置use_bit[i]为01，块1被访问则置use_bit[i]为10），用于实现Cache块替换
    reg  [1:0] use_bit [`CACHE_BLK_NUM / 2 - 1 : 0];
    integer i;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(!cpu_rstn) begin
            for(i = 0; i < `CACHE_BLK_NUM / 2; i = i + 1) use_bit[i] <= 2'b01;
        end
        else begin
            if (hit0)       use_bit[cache_index_r] <= 2'b01;
            else if (hit1)  use_bit[cache_index_r] <= 2'b10;   
        end
    end


    wire cache_we0 = (use_bit[cache_index_r] == 2'b10) && (recv_cnt == `CACHE_BLK_LEN); // ICache存储体0的写使能信号
    wire cache_we1 = (use_bit[cache_index_r] == 2'b01) && (recv_cnt == `CACHE_BLK_LEN); // ICache存储体1的写使能信号
    wire [BLK_WID-1:0] cache_line_w = {1,tag_from_cpu_wr,cache_line_data};               // 待写入ICache的Cache块

    // ICache存储体：Block MEM IP核
    blk_mem_gen_0 U_isram0 (        // ICache存储体0，存储所有Cache组的第0块
        .clka   (cpu_clk),
        .wea    (cache_we0),    //input
        .addra  (blk_addr),     //input
        .dina   (cache_line_w), //input
        .douta  (cache_line_r0) //output
    );

    blk_mem_gen_0 U_isram1 (        // ICache存储体1，存储所有Cache组的第1块
        .clka   (cpu_clk),
        .wea    (cache_we1),
        .addra  (blk_addr),
        .dina   (cache_line_w),
        .douta  (cache_line_r1)
    );

    // REFILL状态下的取指请求缓存
    reg  [TAG_WID  -1:0] tag_from_cpu_wr;       // 缓存块标签
    reg  [INDEX_WID-1:0] cache_idx_wr;          // 缓存Cache块索引
    always @(posedge cpu_clk) begin
        if(current_state == RD_MEM) begin
            tag_from_cpu_wr <= tag_from_cpu;
            cache_idx_wr    <= cache_index_r;
        end
    end
    // 缓存dev_rvalid
    reg dev_rvalid_r;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) dev_rvalid_r <= 1'b0;
        else           dev_rvalid_r <= dev_rvalid;
    end

    reg  cwf_new_req;           // 该信号有效表示REFILL状态下收到了CPU的取指请求
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn)                                    cwf_new_req <= 1'b0;
        else if ((current_state == REFILL) && inst_rreq)       cwf_new_req <= 1'b1;
        else if (inst_valid && !inst_rreq || current_state != REFILL) cwf_new_req <= 1'b0; // 命中后没有新的请求, 或ICache已完成缺失处理退出了REFILL状态
    end

    wire        cwf_tag_match = cwf_new_req && (tag_from_cpu_wr == tag_from_cpu); // REFILL状态下收到的取指请求发生Cache块标签匹配
    wire        cwf_idx_match = cwf_new_req && (cache_idx_wr == cache_index_r);     // REFILL状态下收到的取指请求发生Cache块索引匹配
    wire        cwf_blk_hit   = cwf_tag_match && cwf_idx_match;     // REFILL状态下收到的取指请求在“半成品”Cache块中发生命中
    wire        cwf_hit       = (recv_cnt > offset[OFFSET_WID-1:2]) && cwf_blk_hit && !pred_error; // 生成“半成品”Cache块的命中信号: 命中的前提是总线已返回对应的指令

    wire        cwf_req_left  = cwf_new_req && !cwf_hit;

    //缓存进入REFILL时的指令偏移量
    reg [OFFSET_WID-1:2] miss_offset;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn)                     miss_offset <= 0;
        else if (current_state == RD_MEM)  miss_offset <= offset[OFFSET_WID-1:2];
    end

    wire miss_hit = (current_state == REFILL) && dev_rvalid_r && (recv_cnt-1 == offset[OFFSET_WID-1:2]) && !pred_error
                    && (tag_from_cpu_wr == tag_from_cpu) && (cache_idx_wr == cache_index_r); 

    reg ld_st;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn)                                                 ld_st <= 1'b0;
        else if((current_state == REFILL) && inst_valid && !inst_rreq) ld_st <= 1'b1;
        else if((current_state == TAG_CHECK) || (inst_rreq && !pred_error)) ld_st <= 1'b0;
    end

    // 定义ICache状态机的状态变量
    localparam IDLE      = 3'b000;
    localparam TAG_CHECK = 3'b001;
    localparam RD_MEM    = 3'b010;
    localparam REFILL    = 3'b011;
    localparam WAIT      = 3'b100;

//更新现态
    reg [2:0] current_state, next_state;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        current_state <= !cpu_rstn ? IDLE : next_state;
    end
    
    reg  [OFFSET_WID       :0] recv_cnt;
    reg  [`CACHE_BLK_SIZE-1:0] cache_line_data;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            recv_cnt        <= 0;
            cache_line_data <= 0;
        end
        else if(current_state == REFILL) begin
            if (dev_rvalid) begin
                recv_cnt        <= recv_cnt + 1;
                cache_line_data <= {dev_rdata, cache_line_data[`CACHE_BLK_SIZE-1:32]};
            end
            else if(recv_cnt == `CACHE_BLK_LEN) begin
                recv_cnt        <= 0;
                cache_line_data <= 0;
            end
        end
    end

//状态转移逻辑
    always @(*) begin
        case(current_state)
            IDLE:      next_state = (inst_rreq || cwf_req_left)  ? TAG_CHECK : IDLE;
            TAG_CHECK: begin
                if(pred_error) next_state = TAG_CHECK;
                else if((hit0 | hit1) || ld_st) next_state = inst_rreq ? TAG_CHECK : IDLE;
                else next_state = RD_MEM;
            end
            RD_MEM:    next_state = dev_rrdy                     ? REFILL    : RD_MEM;
            REFILL:    next_state = (recv_cnt == `CACHE_BLK_LEN) ?  WAIT : REFILL;
            WAIT:      next_state = TAG_CHECK;
        endcase
    end

//输出逻辑
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            cpu_ren    <= 4'b0;
            cpu_raddr  <= 32'b0;
        end
        else if(current_state == RD_MEM && dev_rrdy) begin
            cpu_ren   <= 4'b1111;
            cpu_raddr <= {inst_addr_r[31:OFFSET_WID],{OFFSET_WID{1'b0}}};
        end
        else cpu_ren  <= 4'b0;
    end

    always @(*) begin
        if (!cpu_rstn) begin
            inst_valid = 1'b0;
            inst_out   = 32'b0;
        end
        else if(pred_error) begin
            inst_valid = 1'b0;
            inst_out   = 32'b0;
        end
        else if(current_state == TAG_CHECK) begin
            inst_valid = (hit0 | hit1) && !ld_st;
            case(offset[OFFSET_WID-1:2])
                3'd0: inst_out = hit_data_blk[31:0];
                3'd1: inst_out = hit_data_blk[63:32];
                3'd2: inst_out = hit_data_blk[95:64];
                3'd3: inst_out = hit_data_blk[127:96];
                3'd4: inst_out = hit_data_blk[159:128];
                3'd5: inst_out = hit_data_blk[191:160];
                3'd6: inst_out = hit_data_blk[223:192];
                3'd7: inst_out = hit_data_blk[255:224];
            endcase
        end
        else if(current_state == REFILL && (cwf_hit || miss_hit)) begin
            inst_valid = 1'b1;
            case(offset[OFFSET_WID-1:2])
                3'd0: begin
                        case (recv_cnt)
                        4'd1: inst_out = cache_line_data[`CACHE_BLK_LEN*32-1:(`CACHE_BLK_LEN-1)*32];
                        4'd2: inst_out = cache_line_data[(`CACHE_BLK_LEN-1)*32-1:(`CACHE_BLK_LEN-2)*32];
                        4'd3: inst_out = cache_line_data[(`CACHE_BLK_LEN-2)*32-1:(`CACHE_BLK_LEN-3)*32];
                        4'd4: inst_out = cache_line_data[(`CACHE_BLK_LEN-3)*32-1:(`CACHE_BLK_LEN-4)*32];
                        4'd5: inst_out = cache_line_data[(`CACHE_BLK_LEN-4)*32-1:(`CACHE_BLK_LEN-5)*32];
                        4'd6: inst_out = cache_line_data[(`CACHE_BLK_LEN-5)*32-1:(`CACHE_BLK_LEN-6)*32];
                        4'd7: inst_out = cache_line_data[(`CACHE_BLK_LEN-6)*32-1:(`CACHE_BLK_LEN-7)*32];
                        4'd8: inst_out = cache_line_data[(`CACHE_BLK_LEN-7)*32-1:(`CACHE_BLK_LEN-8)*32];
                        endcase
                    end 
                3'd1: begin
                        case (recv_cnt)
                        // 4'd1: inst_out = cache_line_data[(`CACHE_BLK_LEN+1)*32-1:`CACHE_BLK_LEN*32];
                        4'd2: inst_out = cache_line_data[(`CACHE_BLK_LEN)*32-1:(`CACHE_BLK_LEN-1)*32];
                        4'd3: inst_out = cache_line_data[(`CACHE_BLK_LEN-1)*32-1:(`CACHE_BLK_LEN-2)*32];
                        4'd4: inst_out = cache_line_data[(`CACHE_BLK_LEN-2)*32-1:(`CACHE_BLK_LEN-3)*32];
                        4'd5: inst_out = cache_line_data[(`CACHE_BLK_LEN-3)*32-1:(`CACHE_BLK_LEN-4)*32];
                        4'd6: inst_out = cache_line_data[(`CACHE_BLK_LEN-4)*32-1:(`CACHE_BLK_LEN-5)*32];
                        4'd7: inst_out = cache_line_data[(`CACHE_BLK_LEN-5)*32-1:(`CACHE_BLK_LEN-6)*32];
                        4'd8: inst_out = cache_line_data[(`CACHE_BLK_LEN-6)*32-1:(`CACHE_BLK_LEN-7)*32];
                        endcase
                    end
                3'd2: begin
                        case (recv_cnt)
                        // 4'd1: inst_out = cache_line_data[(`CACHE_BLK_LEN+2)*32-1:(`CACHE_BLK_LEN+1)*32];
                        // 4'd2: inst_out = cache_line_data[(`CACHE_BLK_LEN+1)*32-1:`CACHE_BLK_LEN*32];
                        4'd3: inst_out = cache_line_data[(`CACHE_BLK_LEN)*32-1:(`CACHE_BLK_LEN-1)*32];
                        4'd4: inst_out = cache_line_data[(`CACHE_BLK_LEN-1)*32-1:(`CACHE_BLK_LEN-2)*32];
                        4'd5: inst_out = cache_line_data[(`CACHE_BLK_LEN-2)*32-1:(`CACHE_BLK_LEN-3)*32];
                        4'd6: inst_out = cache_line_data[(`CACHE_BLK_LEN-3)*32-1:(`CACHE_BLK_LEN-4)*32];
                        4'd7: inst_out = cache_line_data[(`CACHE_BLK_LEN-4)*32-1:(`CACHE_BLK_LEN-5)*32];
                        4'd8: inst_out = cache_line_data[(`CACHE_BLK_LEN-5)*32-1:(`CACHE_BLK_LEN-6)*32];
                        endcase
                    end
                3'd3: begin
                        case (recv_cnt)
                        // 4'd1: inst_out = cache_line_data[(`CACHE_BLK_LEN+3)*32-1:(`CACHE_BLK_LEN+2)*32];
                        // 4'd2: inst_out = cache_line_data[(`CACHE_BLK_LEN+2)*32-1:(`CACHE_BLK_LEN+1)*32];
                        // 4'd3: inst_out = cache_line_data[(`CACHE_BLK_LEN+1)*32-1:`CACHE_BLK_LEN*32];
                        4'd4: inst_out = cache_line_data[(`CACHE_BLK_LEN)*32-1:(`CACHE_BLK_LEN-1)*32];
                        4'd5: inst_out = cache_line_data[(`CACHE_BLK_LEN-1)*32-1:(`CACHE_BLK_LEN-2)*32];
                        4'd6: inst_out = cache_line_data[(`CACHE_BLK_LEN-2)*32-1:(`CACHE_BLK_LEN-3)*32];
                        4'd7: inst_out = cache_line_data[(`CACHE_BLK_LEN-3)*32-1:(`CACHE_BLK_LEN-4)*32];
                        4'd8: inst_out = cache_line_data[(`CACHE_BLK_LEN-4)*32-1:(`CACHE_BLK_LEN-5)*32];
                        endcase
                    end
                3'd4: begin
                        case (recv_cnt)
                        // 4'd1: inst_out = cache_line_data[(`CACHE_BLK_LEN+4)*32-1:(`CACHE_BLK_LEN+3)*32];
                        // 4'd2: inst_out = cache_line_data[(`CACHE_BLK_LEN+3)*32-1:(`CACHE_BLK_LEN+2)*32];
                        // 4'd3: inst_out = cache_line_data[(`CACHE_BLK_LEN+2)*32-1:(`CACHE_BLK_LEN+1)*32];
                        // 4'd4: inst_out = cache_line_data[(`CACHE_BLK_LEN+1)*32-1:`CACHE_BLK_LEN*32];
                        4'd5: inst_out = cache_line_data[(`CACHE_BLK_LEN)*32-1:(`CACHE_BLK_LEN-1)*32];
                        4'd6: inst_out = cache_line_data[(`CACHE_BLK_LEN-1)*32-1:(`CACHE_BLK_LEN-2)*32];
                        4'd7: inst_out = cache_line_data[(`CACHE_BLK_LEN-2)*32-1:(`CACHE_BLK_LEN-3)*32];
                        4'd8: inst_out = cache_line_data[(`CACHE_BLK_LEN-3)*32-1:(`CACHE_BLK_LEN-4)*32];
                        endcase
                    end
                3'd5: begin
                        case (recv_cnt)
                        // 4'd1: inst_out = cache_line_data[(`CACHE_BLK_LEN+5)*32-1:(`CACHE_BLK_LEN+4)*32];
                        // 4'd2: inst_out = cache_line_data[(`CACHE_BLK_LEN+4)*32-1:(`CACHE_BLK_LEN+3)*32];
                        // 4'd3: inst_out = cache_line_data[(`CACHE_BLK_LEN+3)*32-1:(`CACHE_BLK_LEN+2)*32];
                        // 4'd4: inst_out = cache_line_data[(`CACHE_BLK_LEN+2)*32-1:(`CACHE_BLK_LEN+1)*32];
                        // 4'd5: inst_out = cache_line_data[(`CACHE_BLK_LEN+1)*32-1:`CACHE_BLK_LEN*32];
                        4'd6: inst_out = cache_line_data[(`CACHE_BLK_LEN)*32-1:(`CACHE_BLK_LEN-1)*32];
                        4'd7: inst_out = cache_line_data[(`CACHE_BLK_LEN-1)*32-1:(`CACHE_BLK_LEN-2)*32];
                        4'd8: inst_out = cache_line_data[(`CACHE_BLK_LEN-2)*32-1:(`CACHE_BLK_LEN-3)*32];
                        endcase
                    end
                3'd6: begin
                        case (recv_cnt)
                        // 4'd1: inst_out = cache_line_data[(`CACHE_BLK_LEN+6)*32-1:(`CACHE_BLK_LEN+5)*32];
                        // 4'd2: inst_out = cache_line_data[(`CACHE_BLK_LEN+5)*32-1:(`CACHE_BLK_LEN+4)*32];
                        // 4'd3: inst_out = cache_line_data[(`CACHE_BLK_LEN+4)*32-1:(`CACHE_BLK_LEN+3)*32];
                        // 4'd4: inst_out = cache_line_data[(`CACHE_BLK_LEN+3)*32-1:(`CACHE_BLK_LEN+2)*32];
                        // 4'd5: inst_out = cache_line_data[(`CACHE_BLK_LEN+2)*32-1:(`CACHE_BLK_LEN+1)*32];
                        // 4'd6: inst_out = cache_line_data[(`CACHE_BLK_LEN+1)*32-1:`CACHE_BLK_LEN*32];
                        4'd7: inst_out = cache_line_data[(`CACHE_BLK_LEN)*32-1:(`CACHE_BLK_LEN-1)*32];
                        4'd8: inst_out = cache_line_data[(`CACHE_BLK_LEN-1)*32-1:(`CACHE_BLK_LEN-2)*32];
                        endcase
                    end
                3'd7: begin
                        case (recv_cnt)
                        // 4'd1: inst_out = cache_line_data[(`CACHE_BLK_LEN+7)*32-1:(`CACHE_BLK_LEN+6)*32];
                        // 4'd2: inst_out = cache_line_data[(`CACHE_BLK_LEN+6)*32-1:(`CACHE_BLK_LEN+5)*32];
                        // 4'd3: inst_out = cache_line_data[(`CACHE_BLK_LEN+5)*32-1:(`CACHE_BLK_LEN+4)*32];
                        // 4'd4: inst_out = cache_line_data[(`CACHE_BLK_LEN+4)*32-1:(`CACHE_BLK_LEN+3)*32];
                        // 4'd5: inst_out = cache_line_data[(`CACHE_BLK_LEN+3)*32-1:(`CACHE_BLK_LEN+2)*32];
                        // 4'd6: inst_out = cache_line_data[(`CACHE_BLK_LEN+2)*32-1:(`CACHE_BLK_LEN+1)*32];
                        // 4'd7: inst_out = cache_line_data[(`CACHE_BLK_LEN+1)*32-1:`CACHE_BLK_LEN*32];
                        4'd8: inst_out = cache_line_data[(`CACHE_BLK_LEN)*32-1:(`CACHE_BLK_LEN-1)*32];
                        endcase
                    end
            endcase
        end
        else inst_valid = 1'b0;
    end

`else

    localparam IDLE  = 2'b00; // 取指空闲状态
    localparam STAT0 = 2'b01; // 取指请求已发出但总线尚未就绪状态
    localparam STAT1 = 2'b11; // 取指请求已发出且总线就绪状态，等待数据返回
    reg [1:0] state, nstat;
    reg       dev_rvalid_r;
    wire      dev_rvalid_pos = !dev_rvalid_r & dev_rvalid;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        state        <= !cpu_rstn ? IDLE : nstat;
        dev_rvalid_r <= !cpu_rstn ? 1'b0 : dev_rvalid;
    end

    always @(*) begin
        case (state)
            IDLE   : nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : IDLE;
            STAT0  : nstat = dev_rrdy ? STAT1 : STAT0;
            STAT1  : nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : (dev_rvalid_pos ? IDLE : STAT1);
            default: nstat = IDLE;
        endcase
    end

    reg cpu_ren0;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            inst_valid <= 1'b0;
            cpu_ren0   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    inst_valid <= 1'b0;
                    cpu_ren0   <= (inst_rreq & dev_rrdy) ? 1'b1 : 1'b0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                end
                STAT0: begin
                    cpu_ren0   <= dev_rrdy ? 1'b1 : 1'b0;
                end
                STAT1: begin
                    cpu_ren0   <= (inst_rreq & dev_rrdy) ? 1'b1 : 1'b0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                    inst_valid <= dev_rvalid_pos ? 1'b1 : 1'b0;
                    inst_out   <= dev_rvalid_pos ? dev_rdata[31:0] : 32'h0;
                end
                default: begin
                    inst_valid <= 1'b0;
                    cpu_ren0   <= 1'b0;
                end
            endcase
        end
    end

    always @(*) cpu_ren = {4{cpu_ren0 & !inst_rreq}};

`endif

endmodule