// MD+ HPS Extension interface
// Bridges EXT_BUS between hps_io and the MD+ overlay module.
//
// Commands:
//   CMD_MDP_STATUS (0x60): HPS reads MD+ command state
//     Resp 0: {track_num[7:0], cmd_flags[7:0]}
//     Resp 1: {fade_sectors[7:0], volume[7:0]}
//
//   CMD_MDP_ACK (0x61): HPS acknowledges + sends status back
//     HPS word 1: {current_track[7:0], 7'b0, playing}
//     Clears all pending command flags.
//
//   CMD_MDP_AUDIO (0x62): Audio buffer pointer exchange
//     Resp 0: audio_rd_ptr[15:0]  (FPGA read pointer)
//     HPS word 1: audio_wr_ptr[15:0]  (HPS write pointer)

module hps_ext
(
	input             clk_sys,
	input             reset,
	inout      [35:0] EXT_BUS,

	input             mdp_track_request,
	input       [7:0] mdp_track_num,
	input             mdp_track_loop,
	input             mdp_stop_request,
	input       [7:0] mdp_fade_sectors,
	input             mdp_resume_request,
	input       [7:0] mdp_volume,
	input             mdp_volume_request,

	output reg        mdp_playing,
	output reg  [7:0] mdp_current_track,

	input      [15:0] audio_rd_ptr,
	output reg [15:0] audio_wr_ptr,
	output reg        audio_active
);

// EXT_BUS signal mapping
assign EXT_BUS[15:0] = io_dout;
assign EXT_BUS[32]   = dout_en;

wire [15:0] io_din    = EXT_BUS[31:16];
wire        io_strobe = EXT_BUS[33];
wire        io_enable = EXT_BUS[34];

localparam CMD_MDP_STATUS = 8'h60;
localparam CMD_MDP_ACK    = 8'h61;
localparam CMD_MDP_AUDIO  = 8'h62;
localparam CMD_MDP_MIN    = CMD_MDP_STATUS;
localparam CMD_MDP_MAX    = CMD_MDP_AUDIO;

// Pending command latches (sticky until HPS ACKs)
reg       pending_play;
reg       pending_stop;
reg       pending_resume;
reg       pending_volume;
reg [7:0] latched_track_num;
reg       latched_track_loop;
reg [7:0] latched_fade_sectors;
reg [7:0] latched_volume;

wire [7:0] cmd_byte = {3'b0, latched_track_loop, pending_volume,
                       pending_resume, pending_stop, pending_play};

// EXT_BUS command processing
reg [15:0] io_dout;
reg        dout_en;
reg  [7:0] cmd;
reg  [3:0] byte_cnt;
reg        old_strobe;

always @(posedge clk_sys) begin
	if (reset) begin
		pending_play         <= 0;
		pending_stop         <= 0;
		pending_resume       <= 0;
		pending_volume       <= 0;
		latched_track_num    <= 0;
		latched_track_loop   <= 0;
		latched_fade_sectors <= 0;
		latched_volume       <= 8'hFF;
		mdp_playing          <= 0;
		mdp_current_track    <= 0;
		audio_wr_ptr         <= 0;
		audio_active         <= 0;
		dout_en              <= 0;
		cmd                  <= 0;
		byte_cnt             <= 0;
	end
	else begin
		// Latch md_plus pulses (sticky until ACK clears them)
		if (mdp_track_request) begin
			pending_play       <= 1;
			latched_track_num  <= mdp_track_num;
			latched_track_loop <= mdp_track_loop;
		end
		if (mdp_stop_request) begin
			pending_stop         <= 1;
			latched_fade_sectors <= mdp_fade_sectors;
		end
		if (mdp_resume_request)
			pending_resume <= 1;
		if (mdp_volume_request) begin
			pending_volume <= 1;
			latched_volume <= mdp_volume;
		end

		old_strobe <= io_strobe;

		if (~io_enable) begin
			dout_en  <= 0;
			byte_cnt <= 0;
			cmd      <= 0;
		end
		else if (io_strobe & ~old_strobe) begin
			if (~|byte_cnt) begin
				cmd     <= io_din[7:0];
				dout_en <= (io_din[7:0] >= CMD_MDP_MIN) &&
				           (io_din[7:0] <= CMD_MDP_MAX);

				case (io_din[7:0])
					CMD_MDP_STATUS:
						io_dout <= {latched_track_num, cmd_byte};
					CMD_MDP_AUDIO:
						io_dout <= audio_rd_ptr;
					default:
						io_dout <= 16'h0000;
				endcase

				byte_cnt <= 1;
			end
			else begin
				byte_cnt <= byte_cnt + 1'd1;

				case (cmd)
					CMD_MDP_STATUS: begin
						if (byte_cnt == 4'd1)
							io_dout <= {latched_fade_sectors, latched_volume};
						else
							io_dout <= 16'h0000;
					end

					CMD_MDP_ACK: begin
						if (byte_cnt == 4'd1) begin
							mdp_current_track <= io_din[15:8];
							mdp_playing       <= io_din[0];
							audio_active      <= io_din[0];
							pending_play      <= 0;
							pending_stop      <= 0;
							pending_resume    <= 0;
							pending_volume    <= 0;
						end
						io_dout <= 16'h0000;
					end

					CMD_MDP_AUDIO: begin
						if (byte_cnt == 4'd1) begin
							audio_wr_ptr <= io_din;
						end
						io_dout <= 16'h0000;
					end

					default:
						io_dout <= 16'hFFFF;
				endcase
			end
		end
	end
end

endmodule
