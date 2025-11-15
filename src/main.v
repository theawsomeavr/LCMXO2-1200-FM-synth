`include "parameters.vh"
module Main #(
    parameter PWM_RES = 10,
    parameter ACC_RES = 22,
    parameter VOICE_COUNT = 2,
    parameter TICKS_PER_OP = 8,

    parameter ADSR_IDLE    = 0,
    parameter ADSR_ATTACK  = 1,
    parameter ADSR_DECAY   = 2,
    parameter ADSR_RELEASE = 3,

    parameter STATE_IDLE      = 0,
    parameter STATE_UPDATE_OP = 1,
    parameter STATE_SYNC_REGS = 2
    // parameter STATE_RELEASE = 3
)(
    input IO_main_clk,
    input IO_audio_clk,

    output reg Test,
    output reg TestA,
    output reg TestB,
    output reg TestC,
    output reg TestD,
    output reg IO_pwm
);

integer i;
reg [PWM_RES-1:0] buf_pwm_value;
reg [PWM_RES-1:0] pwm_acc;
reg [PWM_RES-1:0] pwm_value;

// function integer sine_lookup (input integer theta);
//     begin
//     end
// endfunction

// Dude, how does this even work?, it is a frequency controlled signal
// reg [PWM_RES:0] PWM_acc;
// always @(posedge IO_main_clk) PWM_acc <= PWM_acc[PWM_RES-1:0] + 120;

// DDS registers
reg _DDS_w_en;
reg [9:0] _DDS_w_addr;
reg [9:0] _DDS_r_addr;

reg [8:0] _DDS_w_value_L;
reg [8:0] _DDS_w_value_H;
wire [8:0] _DDS_r_value_L;
wire [8:0] _DDS_r_value_H;
BlockRam if_DDS_regs_L (
    .clk(IO_main_clk),
    .w_en(_DDS_w_en),
    .r_en(1),
    .w_addr(_DDS_w_addr),
    .w_value(_DDS_w_value_L),
    .r_addr(_DDS_r_addr),
    .r_value(_DDS_r_value_L)
);
BlockRam if_DDS_regs_H (
    .clk(IO_main_clk),
    .w_en(_DDS_w_en),
    .r_en(1),
    .w_addr(_DDS_w_addr),
    .w_value(_DDS_w_value_H),
    .r_addr(_DDS_r_addr),
    .r_value(_DDS_r_value_H)
);

reg [ACC_RES-1:0] OP_inc;
reg [ACC_RES-1:0] OP_acc;
reg [ACC_RES-1:0] OP_acc_next;
reg [7:0] OP_Volume[0:5];

// reg signed [9:0] OP_sample[0:5];

// ADSR registers
// reg [7:0] OP_Attack[0:VOICE_COUNT-1][0:5];
// reg [7:0] OP_Decay[0:VOICE_COUNT-1][0:5];
// reg [7:0] OP_Sustain[0:VOICE_COUNT-1][0:5];
// reg [7:0] OP_Release[0:VOICE_COUNT-1][0:5];
// reg [1:0] OP_State[0:VOICE_COUNT-1][0:5];
// reg [1:0] OP_next_State[0:VOICE_COUNT-1][0:5];

reg [11:0] OP_amplitude[0:VOICE_COUNT-1][0:5];
reg [11:0] OP_next_amplitude[0:VOICE_COUNT-1][0:5];

reg [9:0] OP_res;
reg [11:0] OP_output;

reg [9:0] sine_idx;
reg [10:0] sine_amplitude;
reg signed [10:0] sine_value;

reg [7:0] _s_idx;
wire [9:0] _s_value;
SineLogTable u_sine (
    .clk(IO_main_clk),
    .addr(_s_idx),
    .value(_s_value)
);

reg [11:0] _e_idx;
wire [8:0] _e_value;
ExpTable u_exp (
    .clk(IO_main_clk),
    .addr(_e_idx),
    .value(_e_value)
);

// MIDI2Freq u_freq (
//     .addr(cur_note),
//     .value(inc)
// );

// always @(posedge IO_MIDI_ready) begin
//     case (IO_MIDI_byte_0[7:4])
//         4'h9: begin
//             cur_note = IO_MIDI_byte_1;
//         end
//     endcase
// end

initial begin
    // OP_Attack[0][0] <= 255;
    // OP_Decay[0][0] <= 2;
    // OP_Sustain[0][0] <= 150;
    // OP_Volume[0][0] <= 0;
    //
    // OP_Attack[0][1] <= 255;
    // OP_Decay[0][1] <= 90;
    // OP_Sustain[0][1] <= 255;
    // OP_Volume[0][1] <= 80;
    //
    // OP_Attack[0][2] <= 255;
    // OP_Decay[0][2] <= 1;
    // OP_Sustain[0][2] <= 255;
    // OP_Volume[0][2] <= 0;
    //
    // OP_Attack[0][3] <= 255;
    // OP_Decay[0][3] <= 1*4;
    // OP_Sustain[0][3] <= 255;
    // OP_Volume[0][3] <= 100;
    //
    for(i = 0; i != 6; i = i+1) begin
        OP_amplitude[0][i] <= 12'hfff;
    end

    // OP_inc[0][0] <= 6220*1;
    // OP_inc[0][1] <= 87080*1;
    // OP_inc[0][2] <= 6220*1;
    // OP_inc[0][3] <= 6220*1;
    // OP_inc[0][4] <= 6220*1;
    // OP_inc[0][5] <= 6220*1;
end

always @(posedge IO_main_clk) begin
    if (pwm_acc == 0) begin
        pwm_value <= buf_pwm_value;
    end
    pwm_acc <= pwm_acc + 1;
    IO_pwm <= (pwm_acc > pwm_value) ? 0 : 1;
end

reg [1:0] Dispatcher_state;
reg [1:0] Dispatcher_next_state;
reg [6:0] Dispatcher_env_div;

reg [4:0] Dispatcher_cur_voice;
reg [2:0] Dispatcher_cur_op;
reg [3:0] Dispatcher_cur_ins;
reg [4:0] Dispatcher_next_voice;
reg [2:0] Dispatcher_next_op;
reg [3:0] Dispatcher_next_ins;

// Dispatcher
always @(posedge IO_main_clk) begin
    Dispatcher_state <= Dispatcher_next_state;

    if (Dispatcher_state == 0) begin
        if (IO_audio_clk) begin
            OP_output <= 0;
            Dispatcher_next_state <= STATE_UPDATE_OP;
            Dispatcher_env_div <= Dispatcher_env_div + 1;
        end
    end else begin
        if (Dispatcher_state == STATE_UPDATE_OP) begin
            Dispatcher_cur_ins <= Dispatcher_next_ins;
            Dispatcher_cur_op <= 5 - Dispatcher_next_op;
            Dispatcher_cur_voice <= Dispatcher_next_voice;

            Dispatcher_next_ins = Dispatcher_next_ins + 1;
            // if (Dispatcher_next_ins == TICKS_PER_OP-1) begin
            //     // Operator switch
            //     // Signed extension
            //     OP_output <= OP_output + {OP_res[9], OP_res[9], OP_res};
            // end

            // Increment instruction
            if (Dispatcher_next_ins == TICKS_PER_OP) begin
                OP_output <= OP_output + OP_res;
                Dispatcher_next_ins = 0;
                Dispatcher_next_op = Dispatcher_next_op + 1;
            end

            // Increment Operator
            if (Dispatcher_next_op == 6) begin
                Dispatcher_next_op = 0;
                Dispatcher_next_voice = Dispatcher_next_voice + 1;
            end

            // Increment Voice
            if (Dispatcher_next_voice == VOICE_COUNT) begin
                // Reset the state machine
                Dispatcher_next_voice = 0;
                Dispatcher_next_state = STATE_SYNC_REGS;
                // buf_pwm_value <= OP_output[11:2];
            end
        end else if (Dispatcher_state == STATE_SYNC_REGS) begin
            Dispatcher_next_state = STATE_IDLE;
        end
    end
end

wire Update_ops_en;
wire Update_regs_en;
assign Update_ops_en  = (Dispatcher_state == STATE_UPDATE_OP);
assign Update_regs_en = (Dispatcher_state == STATE_SYNC_REGS);

// Memory Reader
reg [9:0] Reader_cur_addr;
reg [9:0] Writter_cur_addr;
always @(posedge IO_main_clk) begin
    if(Update_ops_en) begin
        // Memory layout
        // Low    High
        // acc_0, acc_1
        // acc_2, inc_0
        // inc_1, inc_2
        case (Dispatcher_cur_ins)
            4'd00: begin
                OP_acc[8:0] <= _DDS_r_value_L;
                OP_acc[17:9] <= _DDS_r_value_H;
                // Capture the next value
                _DDS_r_addr <= Reader_cur_addr;
                Reader_cur_addr <= Reader_cur_addr + 1;
            end
            4'd01: begin
                OP_acc[21:18] <= _DDS_r_value_L[3:0];
                OP_inc[8:0] <= _DDS_r_value_H;
                // Capture the next value
                _DDS_r_addr <= Reader_cur_addr;
                Reader_cur_addr <= Reader_cur_addr + 1;
            end
            4'd02: begin
                OP_inc[17:9] <= _DDS_r_value_L;
                OP_inc[21:18] <= _DDS_r_value_H[3:0];
                // Capture the next value
                _DDS_r_addr <= Reader_cur_addr;
                Reader_cur_addr <= Reader_cur_addr + 1;
            end
            4'd03: begin
                OP_acc_next = OP_acc + OP_inc;
                _DDS_w_value_L = OP_acc_next[8:0];
                _DDS_w_value_H = OP_acc_next[17:9];

                _DDS_w_en <= 1;
                _DDS_w_addr <= Writter_cur_addr;
                Writter_cur_addr <= Writter_cur_addr + 1;
            end
            4'd04: begin
                OP_res <= OP_acc_next[21:18];

                _DDS_w_value_L[3:0] <= OP_acc_next[21:18];
                _DDS_w_value_H <= OP_inc[8:0];
                _DDS_w_addr <= Writter_cur_addr;
                Writter_cur_addr <= Writter_cur_addr + 2;
                // _DDS_w_value_L <= 9'hAA;
                // _DDS_w_value_H <= 9'hAA;
                // _DDS_w_addr <= _DDS_w_addr + 1;
            end
            default: ;
        endcase
    end else begin
        Reader_cur_addr <= 1;
        Writter_cur_addr <= 0;
        _DDS_r_addr <= 0;
        // _DDS_w_addr <= 0;
        _DDS_w_en <= 0;
    end
end

// Dude, having no structs is super weak
reg signed [ACC_RES-1:0] Audio_cur_phase_offset;
reg [ACC_RES-1:0] Audio_cur_inc;
reg [ACC_RES-1:0] Audio_cur_acc;
reg [ACC_RES-1:0] Audio_tmp_acc;

// Audio Processing task
always @(posedge IO_main_clk) if (Update_ops_en) begin
    case (Dispatcher_cur_ins)
        // Increment
        default: ;
    endcase
    // case (Dispatcher_cur_ins)
    //     // Fetch
    //     4'd00: begin
    //         TestA <= !TestA;
    //
    //         Audio_cur_acc <= OP_acc[Dispatcher_cur_voice][Dispatcher_cur_op];
    //         Audio_cur_inc <= OP_inc[Dispatcher_cur_voice][Dispatcher_cur_op];
    //         sine_amplitude <= OP_amplitude[Dispatcher_cur_voice][Dispatcher_cur_op][11:2]
    //         + (OP_Volume[Dispatcher_cur_voice][Dispatcher_cur_op] << 2);
    //
    //         // case (Dispatcher_cur_op)
    //         //     0: Audio_cur_phase_offset <= {OP_sample[Dispatcher_cur_voice][1], 12'b0};
    //         //     2: Audio_cur_phase_offset <= {OP_sample[Dispatcher_cur_voice][3], 12'b0};
    //         //     default:
    //         //         Audio_cur_phase_offset <= 0;
    //         // endcase
    //     end
    //     // Process and set sine parameters
    //     4'd01: begin
    //         Audio_tmp_acc = Audio_cur_acc + Audio_cur_phase_offset;
    //         sine_idx = Audio_tmp_acc[19:10];
    //         if (sine_idx[8] == 0) begin
    //             _s_idx = sine_idx[7:0];
    //         end else begin
    //             _s_idx = 8'hff - sine_idx[7:0];
    //         end
    //
    //         Audio_cur_acc <= Audio_cur_acc + Audio_cur_inc;
    //     end
    //     // Queue logsin value lookup
    //     4'd02: begin
    //         _s_clk <= 1;
    //     end
    //     // Compute exp idx
    //     4'd03: begin
    //         _e_idx <= _s_value + sine_amplitude;
    //     end
    //     // Queue exp value lookup
    //     4'd04: begin
    //         _e_clk <= 1;
    //     end
    //     // Aquire and flip the resulting sine value
    //     4'd05: begin
    //         if (sine_idx[9] == 0) begin
    //             sine_value <= _e_value;
    //         end else begin
    //             sine_value <= 10'h0 - _e_value;
    //         end
    //     end
    //     // Save and end
    //     4'd06: begin
    //         OP_acc[Dispatcher_cur_op] <= Audio_cur_acc;
    //         OP_sample[Dispatcher_cur_voice][Dispatcher_cur_op] <= sine_value;
    //
    //         case (Dispatcher_cur_op)
    //             0, 2, 4:
    //                 OP_res <= sine_value;
    //             default:
    //                 OP_res <= 0;
    //         endcase
    //
    //         _s_clk <= 0;
    //         _e_clk <= 0;
    //     end
    //     default: begin
    //         // Nothing
    //         // Test <= 0;
    //     end
    // endcase
end

reg [1:0] ADSR_cur_state;
reg [12:0] ADSR_cur_amplitude;
reg [12:0] ADSR_tmp_amplitude;

reg [9:0] ADSR_cur_attack;
reg [7:0] ADSR_cur_decay;
reg [11:0] ADSR_cur_sustain;
reg [7:0] ADSR_cur_release;

wire ADSR_en;
assign ADSR_en = (Dispatcher_env_div == 0) & Update_ops_en;

// always @(posedge clk) begin
//     if (key_on_pulse)
//         // state[bank_num][op_num] <= ATTACK;
//     else if (key_off_pulse)
//         // state[bank_num][op_num] <= RELEASE;
//     else if (sample_clk_en)
//         // state[bank_num][op_num] <= next_state;
// end

// ADSR task, runs in parallel with the audio block
// always @(posedge IO_main_clk) if (ADSR_en) begin
//     case (Dispatcher_cur_ins)
//         // Fetch
//         4'd00: begin
//             ADSR_cur_state     <= OP_State[Dispatcher_cur_voice][Dispatcher_cur_op];
//             ADSR_cur_amplitude <= {1'b0, OP_amplitude[Dispatcher_cur_voice][Dispatcher_cur_op]};
//
//             ADSR_cur_attack  <= OP_Attack[Dispatcher_cur_voice][Dispatcher_cur_op] << 2;
//             ADSR_cur_decay   <= OP_Decay[Dispatcher_cur_voice][Dispatcher_cur_op];
//             ADSR_cur_sustain <= OP_Sustain[Dispatcher_cur_voice][Dispatcher_cur_op] << 4;
//             ADSR_cur_release <= OP_Release[Dispatcher_cur_voice][Dispatcher_cur_op];
//         end
//         // Compute ADSR value and increment
//         4'd01: begin
//             case (ADSR_cur_state)
//                 ADSR_IDLE: begin
//                 end
//                 ADSR_ATTACK: begin
//                     ADSR_cur_amplitude = ADSR_cur_amplitude - ADSR_cur_attack;
//                     // If the top has been reached, clamp and switch phase
//                     if (ADSR_cur_amplitude[12]) begin
//                         ADSR_cur_amplitude = 11'h0;
//                         ADSR_cur_state <= ADSR_DECAY;
//                     end
//                 end
//                 ADSR_DECAY: begin
//                     Test <= !Test;
//                     ADSR_cur_amplitude = ADSR_cur_amplitude + ADSR_cur_decay;
//                     ADSR_tmp_amplitude = ADSR_cur_amplitude - ADSR_cur_sustain;
//
//                     // If it not underflows, means that ADSR_cur_amplitude > ADSR_cur_sustain
//                     if (!ADSR_tmp_amplitude[12]) begin
//                         ADSR_cur_amplitude = ADSR_cur_sustain;
//                         ADSR_cur_state <= ADSR_IDLE;
//                     end
//                 end
//                 ADSR_RELEASE: begin
//                     ADSR_cur_amplitude = ADSR_cur_amplitude - ADSR_cur_release;
//                     // If the top has been reached, clamp and switch phase
//                     if (ADSR_cur_amplitude[12]) begin
//                         ADSR_cur_amplitude = 11'h0;
//                         ADSR_cur_state <= ADSR_IDLE;
//                     end
//                 end
//             endcase
//         end
//         // Save the values
//         4'd02: begin
//             OP_next_State[Dispatcher_cur_voice][Dispatcher_cur_op] <= ADSR_cur_state;
//             OP_next_amplitude[Dispatcher_cur_voice][Dispatcher_cur_op] <= ADSR_cur_amplitude[11:0];
//         end
//         // Nothing
//         default: begin
//             // Test <= 0;
//         end
//     endcase
// end

// reg [9:0] tmp_div;
//
// always @(posedge Update_regs_en) begin
//     // Only update these registers if an ADSR update happened
//     if (Dispatcher_env_div == 0) begin
//
//         if (tmp_div == 0) begin
//             for(i = 0; i != 6; i = i+1) begin
//                 OP_State[0][i] <= ADSR_ATTACK;
//                 OP_amplitude[0][i] <= 12'hfff;
//             end
//         end else begin
//             for(i = 0; i != 6; i = i+1) begin
//                 OP_State[0][i] <= OP_next_State[0][i];
//                 OP_amplitude[0][i] <= OP_next_amplitude[0][i];
//             end
//         end
//
//         tmp_div <= tmp_div + 1;
//     end
// end

endmodule
