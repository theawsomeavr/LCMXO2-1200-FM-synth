module UserRegisters (
    input IO_main_clk,

    input wire IO_SPI_data_ready,
    input wire [7:0] IO_SPI_data,
    input wire IO_SPI_cs,

    input wire  [9:0] IO_R_Mem_addr,
    output wire [17:0] IO_R_Mem_value,

    output reg Test,
    output reg TestA,
    output reg TestB
);

reg _W_Mem_en_L;
reg _W_Mem_en_H;
reg _W_Mem_slot;
reg [9:0] _W_Mem_addr;
reg [8:0] _W_Mem_value;

BlockRam UserMemL (
    .clk(IO_main_clk),

    .w_en(_W_Mem_en_L),
    .w_addr(_W_Mem_addr),
    .w_value(_W_Mem_value),
    .r_addr(IO_R_Mem_addr),
    .r_value(IO_R_Mem_value[8:0])
);

BlockRam UserMemH (
    .clk(IO_main_clk),

    .w_en(_W_Mem_en_H),
    .w_addr(_W_Mem_addr),
    .w_value(_W_Mem_value),
    .r_addr(IO_R_Mem_addr),
    .r_value(IO_R_Mem_value[17:9])
);

// reg SPI_prev_cs;
// reg SPI_begin_selection;
// reg SPI_end_selection;
// always @(posedge IO_main_clk) begin
//     if (SPI_prev_cs != IO_SPI_cs) begin
//         if (!IO_SPI_cs) SPI_begin_selection <= 1;
//     end else SPI_begin_selection <= 0;
//
//     SPI_prev_cs <= IO_SPI_cs;
// end

reg [3:0] write_state;
reg [3:0] new_write_state;

`define SPI_WAIT_ADDR_L  4'b0001
`define SPI_WAIT_ADDR_H  4'b0010
`define SPI_WAIT_VALUE_L 4'b0100
`define SPI_WAIT_VALUE_H 4'b1000

initial begin
    write_state <= `SPI_WAIT_ADDR_L;
    new_write_state <= `SPI_WAIT_ADDR_L;
end

reg safe_SPI_cs;

always @(posedge IO_main_clk) begin
    safe_SPI_cs <= IO_SPI_cs;
end

always @(posedge IO_main_clk) begin
    _W_Mem_en_L <= 0;
    _W_Mem_en_H <= 0;

    if (IO_SPI_data_ready) begin
        TestB <=
            IO_SPI_data[7] |
            IO_SPI_data[6] |
            IO_SPI_data[5] |
            IO_SPI_data[4] |
            IO_SPI_data[3] |
            IO_SPI_data[2] |
            IO_SPI_data[1] |
            IO_SPI_data[0];

        case (write_state)
            `SPI_WAIT_ADDR_L: begin
                _W_Mem_addr[6:0] <= IO_SPI_data[7:1];
                _W_Mem_slot <= IO_SPI_data[0];

                new_write_state <= `SPI_WAIT_ADDR_H;
            end
            `SPI_WAIT_ADDR_H: begin
                _W_Mem_addr[9:7] <= IO_SPI_data[2:0];
                new_write_state <= `SPI_WAIT_VALUE_L;
            end
            `SPI_WAIT_VALUE_L: begin
                _W_Mem_value[7:0] <= IO_SPI_data;
                new_write_state <= `SPI_WAIT_VALUE_H;
            end
            `SPI_WAIT_VALUE_H: begin
                Test <= !Test;
                _W_Mem_value[8] <= IO_SPI_data[0];


                if (!_W_Mem_slot) begin
                    TestA <= !TestA;
                    _W_Mem_en_L <= 1;
                end else begin
                    _W_Mem_en_H <= 1;
                end
                new_write_state <= `SPI_WAIT_ADDR_L;
            end
            default: ;
        endcase
    end

    if (safe_SPI_cs) begin
        new_write_state <= `SPI_WAIT_ADDR_L;
    end

    write_state <= new_write_state;
end

endmodule
