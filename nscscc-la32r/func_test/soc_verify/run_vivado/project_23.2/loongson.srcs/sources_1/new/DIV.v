`timescale 1ns / 1ps

module DIV(
    input  wire         cpu_clk,
    input  wire         cpu_rstn,
    input  wire         is_signed,
    input  wire         start,
    input  wire [31:0]  A,
    input  wire [31:0]  B,
    output reg  [63:0]  result,
    output reg          busy,
    output reg          ready
);

    localparam DivFree   = 2'b00; //空闲状态
    localparam DivByZero = 2'b01; //除数为零
    localparam DivOn     = 2'b10; //正在计算
    localparam DivEnd    = 2'b11; //计算结束

    wire [31:0]  temp_op1;       //暂存被除数
    wire [31:0]  temp_op2;       //暂存除数
    reg  [31:0]  quotient_temp;  //暂存商
    reg  [5:0]   cnt;            //记录试商法进行的轮数
    reg  [31:0]  minuend;        //用来与除数进行比较的数
    wire [32:0]  sub;            //minuend和temp_op2的差
    wire [5:0]   k;              //表示当前试到第k位
    reg  [1:0]   current_state;
    reg  [1:0]   next_state;


//================================================================================
// 第一段：状态转移部分
//================================================================================
    //更新现态
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(cpu_rstn == 1'b0) current_state <= DivFree;
        else                  current_state <= next_state;
    end

    //更新cnt
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(cpu_rstn == 1'b0)            cnt <= 6'd0;
        else if(current_state == DivOn) cnt <= (cnt == 6'd31) ? 6'd0 : cnt + 1'b1;
        else                            cnt <= 6'd0;
    end

    //更新暂存的除数与被除数
    assign temp_op1 = (is_signed) ? (A[31]) ? ~A + 1 : A : A;
    assign temp_op2 = (is_signed) ? (B[31]) ? ~B + 1 : B : B;

    // always @(posedge cpu_clk) begin
    //     if(cpu_rstn == 1'b0) temp_op1 <= 32'b0;
    //     else if(current_state == DivFree && next_state == DivOn) begin
    //         if(is_signed) temp_op1 <= (A[31]) ? ~A + 1 : A;
    //         else          temp_op1 <= A;
    //     end
    // end

    // always @(posedge cpu_clk) begin
    //     if(cpu_rstn == 1'b0) temp_op2 <= 32'b0;
    //     else if(current_state == DivFree && next_state == DivOn) begin
    //         if(is_signed) temp_op2 <= (B[31]) ? ~B + 1 : B;
    //         else             temp_op2 <= B;
    //     end
    // end

    //更新sub,k
    assign sub = {1'b0,minuend} - {1'b0,temp_op2};
    assign k = 6'd31 - cnt;

    //更新minuend
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(cpu_rstn == 1'b0) 
            minuend <= 32'b0; 
        else if(current_state == DivFree && next_state == DivOn) 
            minuend <= {31'd0,temp_op1[31]};
        else if(current_state == DivOn) 
            if(k > 0)
                minuend <= (sub[32]) ? {minuend[30:0], temp_op1[k-1]} : {sub[30:0], temp_op1[k-1]};
    end

    //更新quotient_temp
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(cpu_rstn == 1'b0)                       quotient_temp <= 32'b0;
        else if(current_state == DivOn) quotient_temp[k] <= (sub[32]) ? 1'b0 : 1'b1;
    end



//================================================================================
// 第二段：状态转移条件部分
//================================================================================
    always @(*) begin
        case(current_state)
            DivFree:   next_state = (start == 1'b1) ? ((B == 32'b0) ? DivByZero : DivOn) : DivFree;
            DivByZero: next_state = DivEnd;
            DivOn:     next_state = (cnt == 6'd31) ? DivEnd : DivOn;                                      
            DivEnd:    next_state = DivFree;
            default:   next_state = DivFree;
        endcase
    end

//================================================================================
// 第三段：输出逻辑部分
//================================================================================
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if(cpu_rstn == 1'b0) begin
            result <= {32'b0,32'b0};
            ready  <= 1'b0;
            busy   <= 1'b0;
        end
        else begin
            case(current_state) 
                DivFree: begin
                    busy   <= 1'b0;
                    ready  <= 1'b0;
                    result <= {32'b0,32'b0};
                end
                DivByZero: begin
                    ready  <= 1'b1;
                    result <= {32'b0,32'b0};
                end
                DivOn: begin
                    busy   <= 1'b1;
                end
                DivEnd: begin
                    busy   <= 1'b0;
                    ready  <= 1'b1;
                    result[31:0] <= (is_signed && (A[31] ^ B[31])) ? ~quotient_temp + 1 : quotient_temp;
                    
                    if(is_signed && A[31]) 
                        result[63:32] <= (sub[32]) ? ~minuend + 1 : ~sub[31:0] + 1;
                    else 
                        result[63:32] <= (sub[32]) ? minuend : sub[31:0];
                end
            endcase
        end
    end

endmodule
