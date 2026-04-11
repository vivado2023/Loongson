`timescale 1ns / 1ps

module MUL_U(
    input  wire         cpu_clk ,
    input  wire         cpu_rstn,
    input  wire         start   ,
    input  wire [31:0]  A       ,
    input  wire [31:0]  B       ,
    output reg  [63:0]  result  ,
    output reg          busy    ,
    output reg          ready
);

reg [102:0] booth_reg;     // {ACC[67:0], Q[33:0], Q-1}
reg [4:0]  cnt;
reg [67:0] add_value;
reg [67:0] acc_next;
reg [102:0] booth_temp;
reg [102:0] booth_next;

always @(*) begin
    case (booth_reg[2:0])
        3'b000: add_value = 68'd0;
        3'b001: add_value = {36'd0, A};          //+A
        3'b010: add_value = {36'd0, A};          //+A
        3'b011: add_value = {35'd0, A, 1'b0};    //+2A
        3'b100: add_value =~{35'd0, A, 1'b0} + 1;//-2A
        3'b101: add_value =~{36'd0, A} + 1;      //-A
        3'b110: add_value =~{36'd0, A} + 1;      //-A
        3'b111: add_value = 68'd0;
        default:add_value = 68'd0;
    endcase
end

always @(*) begin
    acc_next = booth_reg[102:35] + add_value;
    booth_temp = {acc_next, booth_reg[34:0]};
    booth_next = {{2{booth_temp[102]}}, booth_temp[102:2]};
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
                booth_reg <= {70'd0, B, 1'b0};
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
            if(cnt < 5'd17) begin
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