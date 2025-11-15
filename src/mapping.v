`include "parameters.vh"

module Mapping #(
    parameter AUDIO_PRESCALAR = 1508 - 1
)(
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

wire byte_ready;
wire [7:0] serial_byte;

Main if_main (

    .IO_main_clk(main_clk),
    .IO_audio_clk(audio_clk),

    // .IO_MIDI_byte_0(MIDI_bytes_0),
    // .IO_MIDI_byte_1(MIDI_bytes_1),
    // .IO_MIDI_byte_2(MIDI_bytes_2),
    // .IO_MIDI_ready(MIDI_ready),
    .IO_pwm(pin5),

    .TestA(pin0),
    .TestB(pin1),
    .TestC(pin2),
    .TestD(pin3),

    .Test(pin6_LED)
);

// Serial if_uart (
//     .IO_clk(audio_clk[0]),
//     .IO_rx(pin0),
//     .IO_byte(serial_byte),
//     .IO_byte_ready(byte_ready)
// );
//
// MIDIProcessing if_midi (
//     .IO_clk(audio_clk[0]),
//     .IO_byte(serial_byte),
//     .IO_byte_ready(byte_ready),
//
//     .IO_MIDI_byte_0(MIDI_bytes_0),
//     .IO_MIDI_byte_1(MIDI_bytes_1),
//     .IO_MIDI_byte_2(MIDI_bytes_2),
//     .IO_MIDI_ready(MIDI_ready)
// );

endmodule
