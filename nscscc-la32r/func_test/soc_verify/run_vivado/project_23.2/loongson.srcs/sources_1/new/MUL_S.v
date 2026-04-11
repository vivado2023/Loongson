`timescale 1ns / 1ps

module MUL_S(
    input  wire         cpu_clk ,
    input  wire         cpu_rstn,
    input  wire         start   ,
    input  wire [31:0]  A       ,
    input  wire [31:0]  B       ,
    output reg  [63:0]  result  ,
    output reg          busy    ,
    output reg          ready
);

reg [96:0] booth_reg;     // {ACC[63:0], Q[31:0], Q-1}
reg [4:0]  cnt;
reg [63:0] add_value;
reg [63:0] acc_next;
reg [96:0] booth_temp;
reg [96:0] booth_next;

always @(*) begin
    case (booth_reg[2:0])
        3'b000: add_value = 64'd0;
        3'b001: add_value = {{32{A[31]}}, A};            //+A
        3'b010: add_value = {{32{A[31]}}, A};            //+A
        3'b011: add_value = {{31{A[31]}}, A, 1'b0};      //+2A
        3'b100: add_value =~{{31{A[31]}}, A, 1'b0} + 1;  //-2A
        3'b101: add_value =~{{32{A[31]}}, A} + 1;        //-A
        3'b110: add_value =~{{32{A[31]}}, A} + 1;        //-A
        3'b111: add_value = 64'd0;
        default:add_value = 64'd0;
    endcase
end

always @(*) begin
    acc_next = booth_reg[96:33] + add_value;
    booth_temp = {acc_next, booth_reg[32:0]};
    booth_next = {{2{booth_temp[96]}}, booth_temp[96:2]};
end

always @(posedge cpu_clk or negedge cpu_rstn) begin
    if(!cpu_rstn) begin
        booth_reg <= 0;
        cnt       <= 0;
        busy      <= 0;
        ready     <= 0;
        result    <= 0;
    end
    else begin
        if(!busy) begin
            if(start) begin
                booth_reg <= {64'd0, B, 1'b0};
                cnt       <= 5'd0;
                busy      <= 1;
                ready     <= 0;
            end
            else begin
                ready     <= 0;
                busy      <= 0;
            end
        end
        else begin
            if(cnt < 5'd16) begin
                booth_reg <= booth_next;
                cnt       <= cnt + 5'd1;
            end
            else begin
                result    <= booth_reg[64:1];
                busy      <= 0;
                ready     <= 1;
            end
        end
    end
end
endmodule
