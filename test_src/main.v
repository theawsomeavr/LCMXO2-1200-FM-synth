module Main #(
    parameter ACC_RESOLUTION = 22,
    parameter TICKS_PER_OP = 12
)(
    input IO_main_clk,
    input IO_audio_clk,

    output reg IO_Flag_read,
    output reg [3:0] IO_Flag_addr,
    input wire [1:0] IO_Flag_value,

    input wire IO_SPI_cs,
    output reg [9:0] IO_User_Mem_addr,
    input wire [17:0] IO_User_Mem_value,

    output reg IO_chan_A, IO_chan_B, IO_chan_C, IO_chan_D,
    output reg IO_chan_E, IO_chan_F, IO_chan_G, IO_chan_H,
    output reg T_k1
);  

reg sync_registers;
initial begin
    sync_registers <= 1;
end

reg _W_Mem_en_L;
reg _W_Mem_en_H;
reg [9:0] _W_Mem_addr;
reg [17:0] _W_Mem_value;

reg [9:0] _R_Mem_addr;
wire [17:0] _R_Mem_value;

BlockRam if_data_L (
    .clk(IO_main_clk),

    .w_en(_W_Mem_en_L),
    .w_addr(_W_Mem_addr),
    .w_value(_W_Mem_value[8:0]),
    .r_addr(_R_Mem_addr),
    .r_value(_R_Mem_value[8:0])
);

BlockRam if_data_H (
    .clk(IO_main_clk),

    .w_en(_W_Mem_en_H),
    .w_addr(_W_Mem_addr),
    .w_value(_W_Mem_value[17:9]),
    .r_addr(_R_Mem_addr),
    .r_value(_R_Mem_value[17:9])
);

// reg [3:0] cur_cell;
// reg [3:0] read_state;

// reg [6:0] Dispatcher_env_div;
// reg [1:0] Dispatcher_next_state;

// reg [4:0] Dispatcher_next_voice;
// reg [2:0] Dispatcher_next_op;
// reg [3:0] Dispatcher_next_ins;

reg Dispatcher_en;
reg [6:0] Dispatcher_rolling_op;

reg [5:0] Dispatcher_cur_voice;
reg [2:0] Dispatcher_cur_op;
reg [3:0] Dispatcher_cur_ins;

// `define STATE_IDLE      0
// `define STATE_UPDATE_OP 1
// `define STATE_SYNC_REGS 2
// Dispatcher
always @(posedge IO_main_clk) begin
    if (Dispatcher_en == 0) begin
        if (IO_audio_clk) begin
            Dispatcher_en <= 1;
            Dispatcher_cur_ins <= 0;
            Dispatcher_cur_op <= 5;
            Dispatcher_cur_voice <= 0;
            Dispatcher_rolling_op <= 0;

            // OP_output <= 0;
            // Dispatcher_state <= `STATE_UPDATE_OP;
            // Dispatcher_env_div <= Dispatcher_env_div + 1;
        end
    end else begin
        Dispatcher_cur_ins = Dispatcher_cur_ins + 1;
        // Increment instruction
        if (Dispatcher_cur_ins == TICKS_PER_OP) begin
            Dispatcher_cur_ins = 0;
            Dispatcher_cur_op = Dispatcher_cur_op - 1;
            Dispatcher_rolling_op <= Dispatcher_rolling_op + 1;
        end

        // Increment Operator
        if (Dispatcher_cur_op == 3'h7) begin
            Dispatcher_cur_op = 5;

            if (Dispatcher_cur_voice == 5'h11) begin
                Dispatcher_en <= 0;
            end
            Dispatcher_cur_voice <= Dispatcher_cur_voice + 1;
        end
    end
end

wire Enable_synth;
wire Enable_reg_sync;

assign Enable_synth = (Dispatcher_rolling_op < 16*6);
assign Enable_reg_sync = (Dispatcher_rolling_op >= 1) && (Dispatcher_rolling_op <= 16*6);

// Accumulator of the last operator
reg [ACC_RESOLUTION-1:0] prev_acc;

// 3 ticks to load the data
reg [ACC_RESOLUTION-1:0] acc; // 3 slots
reg [ACC_RESOLUTION-1:0] inc; // 3 slots

reg [8:0] Attack; // 1 slots
reg [8:0] Decay; // 1 slots
reg [8:0] Sustain; // 1 slots
reg [8:0] Release; // 1 slots
reg [8:0] ADSR_Volume; // 1 slots
reg [8:0] User_Volume; // 1 slots

reg [9:0] Voice_base_addr;


/****************************************
*  LSB [8:0]        | MSB [17:9]        *
*-------------------------------------- *
*        ACC[17:0] (18 bits)            *
*        INC[17:0] (18 bits)            *
*  ACC[21:18] (4 b) | INC[21:18] (4 b)  *
*  Attack           | Decay             *
*  Sustain          | Release           *
*  ADSR Volume      | User Volume       *
*  Algorithm        |                   *
****************************************/

`define OP_OFFSET_ACC_L           0
`define OP_OFFSET_INC_L           1
`define OP_OFFSET_ACC_H_INC_H     2
`define OP_OFFSET_ATTACK_DECAY    3
`define OP_OFFSET_SUSTAIN_RELEASE 4
`define OP_OFFSET_ADSR_USR_VOL    5
`define OP_OFFSET_ALGORITHM       6

`define OP_REG_SIZE           7

// reg [1:0] ADSR_states[0:95];
// reg [1:0] ADSR_new_state;
// reg [8:0] ADSR_new_volume;

// Synthesis routine
always @(posedge IO_main_clk) begin
    // Test <= Enable_synth;
    if (Enable_synth) begin
        case (Dispatcher_cur_ins)
            // Load ADSR data
            4'h0: begin
                Attack <= _R_Mem_value[8:0];
                Decay  <= _R_Mem_value[17:9];
                _R_Mem_addr <= Voice_base_addr + `OP_OFFSET_SUSTAIN_RELEASE;
            end
            4'h1: begin
                Sustain <= _R_Mem_value[8:0];
                Release <= _R_Mem_value[17:9];
                _R_Mem_addr <= Voice_base_addr + `OP_OFFSET_ADSR_USR_VOL;
            end
            4'h2: begin
                ADSR_Volume <= _R_Mem_value[8:0];
                User_Volume <= _R_Mem_value[17:9];
                _R_Mem_addr <= Voice_base_addr + `OP_OFFSET_ACC_L;
            end

            // Load acc L
            4'h3: begin
                acc[17:0] <= _R_Mem_value;
                _R_Mem_addr <= Voice_base_addr + `OP_OFFSET_INC_L;
            end
            // Load inc L
            4'h4: begin
                inc[17:0] <= _R_Mem_value;
                _R_Mem_addr <= Voice_base_addr + `OP_OFFSET_ACC_H_INC_H;
            end
            // Load acc H and inc H
            4'h5: begin
                acc[21:18] <= _R_Mem_value[3:0];
                inc[21:18] <= _R_Mem_value[11:8];
            end

            // Compute phase
            4'h6: begin
                acc <= acc + inc;
            end
            // Toogle and queue write
            4'h7: begin
                if ((Dispatcher_cur_voice == 0)) begin
                    if (Dispatcher_cur_op == 5) IO_chan_A <= acc[21];
                    if (Dispatcher_cur_op == 4) IO_chan_B <= acc[21];
                    if (Dispatcher_cur_op == 3) IO_chan_C <= acc[21];
                    if (Dispatcher_cur_op == 2) IO_chan_D <= acc[21];
                    if (Dispatcher_cur_op == 1) IO_chan_E <= acc[21];
                    if (Dispatcher_cur_op == 0) IO_chan_F <= acc[21];
                end
            end
            4'h8: begin
                if ((Dispatcher_cur_voice == 1)) begin
                    if (Dispatcher_cur_op == 5) IO_chan_G <= acc[21];
                    if (Dispatcher_cur_op == 4) IO_chan_H <= acc[21];
                end
            end

            4'hb: begin
                prev_acc <= acc;
                Voice_base_addr = Voice_base_addr + `OP_REG_SIZE;
                _R_Mem_addr = Voice_base_addr + `OP_OFFSET_ATTACK_DECAY;
            end
            default: ;
        endcase
    end else begin
        Voice_base_addr <= 0;

        _R_Mem_addr <= `OP_OFFSET_ATTACK_DECAY;
    end
end

// Sync routine
reg [9:0] Sync_base_addr;
always @(posedge IO_main_clk) begin
    _W_Mem_en_L <= 0;
    _W_Mem_en_H <= 0;
    IO_Flag_read <= 0;

    if(Enable_reg_sync) begin
        case (Dispatcher_cur_ins)
            // Sync acc L value
            4'h0: begin

                IO_Flag_read <= 1;
                IO_Flag_addr <= 0;
                // [1:0] IO_Flag_value;

                _W_Mem_addr <= Sync_base_addr + `OP_OFFSET_ACC_L;
                _W_Mem_value <= prev_acc[17:0];
                _W_Mem_en_L <= 1;
                _W_Mem_en_H <= 1;
            end
            // Sync inc L
            4'h1: begin
                T_k1 <= IO_Flag_value[0];

                _W_Mem_addr <= Sync_base_addr + `OP_OFFSET_INC_L;
                _W_Mem_value <= IO_User_Mem_value;

                _W_Mem_en_L <= 1;
                _W_Mem_en_H <= 1;
                IO_User_Mem_addr <= IO_User_Mem_addr + 1;
            end 
            // Sync acc H and inc H
            4'h2: begin
                _W_Mem_addr <= Sync_base_addr + `OP_OFFSET_ACC_H_INC_H;
                _W_Mem_value[3:0] <= prev_acc[21:18];
                _W_Mem_value[11:8] <= IO_User_Mem_value[3:0];

                _W_Mem_en_L <= 1;
                _W_Mem_en_H <= 1;
            end 

            4'hb: begin
                Sync_base_addr <= Sync_base_addr + `OP_REG_SIZE;
                IO_User_Mem_addr <= IO_User_Mem_addr + 1;
            end
            default:;
        endcase
    end else begin
        Sync_base_addr <= 0;
        IO_User_Mem_addr <= 0;
    end
end

endmodule
