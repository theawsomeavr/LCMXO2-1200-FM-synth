module BlockRam(
    input clk,
    input w_en,
    input r_en,
    input [9:0] w_addr,
    input [8:0] w_value,

    input [9:0] r_addr,
    output reg [8:0] r_value
);  

reg [8:0] item[0:1023];

always @ (posedge clk) begin
    if (w_en) begin
        item[w_addr] <= w_value;
    end

    if (r_en) begin
        r_value <= item[r_addr];
    end
end

endmodule
