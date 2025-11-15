module Mapping #(
    parameter AUDIO_PRESCALAR = 1508 - 1
)(
    input wire pin13_sclk,
    input wire pin14_miso,
    input wire pin15_mosi,
    input wire pin16_cs,
    
    output wire pin0, pin1, pin2, pin3,
    output wire pin5,
    output wire pin6_LED
);

wire main_clk;
OSCH #(
    .NOM_FREQ("66.50")
) internal_oscillator_inst(
    .STDBY(1'b0),
    .OSC(main_clk)
);

reg audio_clk;
reg [11:0] prescalar;

always @(posedge main_clk) begin
    if(prescalar == AUDIO_PRESCALAR) begin
        audio_clk <= 1;
        prescalar <= 0;
    end else begin
        audio_clk <= 0;
        prescalar <= prescalar + 12'd1;
    end
end

wire wb_cyc_i;
wire wb_stb_i;
wire [7:0] wb_adr_i;
wire [7:0] wb_dat_o;
wire wb_ack_o;

spi_slave_efb sspi_efb_inst (
    .wb_clk_i (main_clk), 
    .wb_rst_i (0), 
    .wb_cyc_i (wb_cyc_i), 
    .wb_stb_i (wb_stb_i), 
    .wb_we_i  (0), // Never writting back anything
    .wb_adr_i (wb_adr_i), 
    .wb_dat_i (0), 

    .wb_dat_o (wb_dat_o), 
    .wb_ack_o (wb_ack_o), 

    .spi_clk  (pin13_sclk),  
    .spi_miso (pin14_miso), 
    .spi_mosi (pin15_mosi), 
    .spi_scsn (pin16_cs)
);

wire U_data_ready;
wire [7:0] U_data;

SPIInterface if_spi (
    .IO_main_clk(main_clk),
    .wb_cyc_i(wb_cyc_i),
    .wb_stb_i(wb_stb_i),
    .wb_adr_i(wb_adr_i),
    .wb_dat_o(wb_dat_o),
    .wb_ack_o(wb_ack_o),

    .U_data_ready(U_data_ready),
    .U_data(U_data)
);

wire [9:0] U_R_Mem_addr;
wire [17:0] U_R_Mem_value;

UserRegisters if_user_regs (
    .IO_main_clk(main_clk),

    .IO_SPI_data_ready(U_data_ready),
    .IO_SPI_data(U_data),
    .IO_SPI_cs(pin16_cs),
    .IO_R_Mem_addr(U_R_Mem_addr),
    .IO_R_Mem_value(U_R_Mem_value),

    .TestA(pin5)
    // .TestB(pin0),
    // .Test(pin1)
);

Main if_main (
    .IO_main_clk(main_clk),
    .IO_audio_clk(audio_clk),

    .IO_SPI_cs(pin16_cs),
    .IO_User_Mem_addr(U_R_Mem_addr),
    .IO_User_Mem_value(U_R_Mem_value),

    .TestA(pin0),
    .TestB(pin1),
    .Test(pin6_LED)
);

endmodule
