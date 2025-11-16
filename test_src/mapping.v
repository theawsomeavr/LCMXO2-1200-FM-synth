module Mapping #(
    parameter AUDIO_PRESCALAR = 1508 - 1
)(
    input wire pin13_sclk,
    input wire pin14_miso,
    input wire pin15_mosi,
    input wire pin12_sn,
    
    output wire pin2, pin3, pin4, pin5,
    output wire pin8, pin9, pin10, pin11,
    output wire pin6_LED,
    output wire pin16_cs
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
    .spi_scsn (pin12_sn)
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

wire U_Flag_read;
wire [3:0] U_Flag_addr;
wire [1:0] U_Flag_value;

wire [9:0] U_R_Mem_addr;
wire [17:0] U_R_Mem_value;

UserRegisters if_user_regs (
    .IO_main_clk(main_clk),

    .IO_SPI_data_ready(U_data_ready),
    .IO_SPI_data(U_data),
    .IO_SPI_cs(pin12_sn),

    .IO_Flag_read(U_Flag_read),
    .IO_Flag_addr(U_Flag_addr),
    .IO_Flag_value(U_Flag_value),

    .IO_R_Mem_addr(U_R_Mem_addr),
    .IO_R_Mem_value(U_R_Mem_value),

    .Test(pin16_cs)
);

Main if_main (
    .IO_main_clk(main_clk),
    .IO_audio_clk(audio_clk),

    .IO_Flag_read(U_Flag_read),
    .IO_Flag_addr(U_Flag_addr),
    .IO_Flag_value(U_Flag_value),

    .IO_SPI_cs(pin12_sn),
    .IO_User_Mem_addr(U_R_Mem_addr),
    .IO_User_Mem_value(U_R_Mem_value),

    .IO_chan_A(pin2),
    .IO_chan_B(pin3),
    .IO_chan_C(pin4),
    .IO_chan_D(pin5),

    .IO_chan_E(pin8),
    .IO_chan_F(pin9),
    .IO_chan_G(pin10),
    .IO_chan_H(pin11),
    .T_k1(pin6_LED)
);

endmodule
