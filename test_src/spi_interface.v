module SPIInterface(
    input wire IO_main_clk,
    input wire [7:0] wb_dat_o,
    input wire wb_ack_o,
    output reg [7:0] wb_adr_i,
    output reg wb_cyc_i,
    output reg wb_stb_i,

    output reg U_data_ready,
    output reg [7:0] U_data,

    output reg Test,
    output reg TestA
);

`define IDLE  1'b0
`define WORK  1'b1

`define SPITXDR 8'h59
`define SPISR   8'h5A
`define SPIRXDR 8'h5B

// RX ready bit
`define RRDY 3

reg wb_sm;  // The state register for WISHBONE state machine
reg [1:0] spi_state;
reg [7:0] address;
reg [7:0] spi_res;

initial begin
    spi_state <= 0;
end

reg transmition_start;
reg transmition_done;

always @(posedge IO_main_clk) begin
    case (wb_sm)
    // No transfer
    `IDLE:  if (transmition_start)
             wb_sm <= `WORK;  // Go to `WORK state when the WISHBONE write or read transaction is enabled
    // WISHBONE transfer                                
    `WORK:  if (wb_ack_o)       // Go to `IDLE state when the WISHBONE transfer is acknowledgeed
             wb_sm <= `IDLE;
    endcase
end

always @(posedge IO_main_clk) begin
    // Does this work??
    transmition_done <= 0;
    case (wb_sm)
        `IDLE: 
            if (transmition_start) begin
                wb_cyc_i <= #1 1'b1;   // delay 1 ns to avoid simulation/hardware mismatch
                wb_stb_i <= #1 1'b1;   // delay 1 ns to avoid simulation/hardware mismatch
                wb_adr_i <= address;
            end else begin
                wb_cyc_i <= 1'b0;
                wb_stb_i <= 1'b0;
            end 
        `WORK:
            if (wb_ack_o) begin
                spi_res <= wb_dat_o;
                wb_cyc_i <= 1'b0;
                wb_stb_i <= 1'b0;
                transmition_done <= 1;
            end 
    endcase              
end

always @(posedge IO_main_clk) begin
    transmition_start <= 0;
    U_data_ready <= 0;

    case (spi_state)
      // Queue an SPI status register operation
      2'd0: begin
          address <= `SPISR;
          transmition_start <= 1;
          spi_state <= 2'd1;
      end
      // Read the status, if there is data read the byte
      // else go to step 0
      2'd1: begin
          if (transmition_done) begin
              if (spi_res[`RRDY]) begin
                  address <= `SPIRXDR;
                  spi_state <= 2'd2;
                  transmition_start <= 1;
              end else begin
                  spi_state <= 2'd0;
              end
          end
      end
      // Read the byte and alert the device
      2'd2: begin
          if (transmition_done) begin
              TestA <= !TestA;
              U_data <= spi_res;
              U_data_ready <= 1;
              spi_state <= 2'd0;
          end
      end
      default: ;
    endcase
end

endmodule
