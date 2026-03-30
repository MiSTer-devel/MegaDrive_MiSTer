// MD+ Audio Streaming Module
//
// Reads 16-bit stereo 44.1kHz PCM from a ring buffer in DDRAM (written by
// the HPS), applies volume and hardware fade, and outputs audio samples.
//
// DDRAM ring buffer: 64KB at configurable base address.
// HPS writes WAV PCM data into the buffer and updates the write pointer
// via EXT_BUS. FPGA reads at 44.1kHz and reports its read pointer back.
//
// Sample format in DDRAM (little-endian, matches WAV):
//   Each 64-bit word = 2 stereo samples
//   Bits [15:0]  = Sample 0 Left
//   Bits [31:16] = Sample 0 Right
//   Bits [47:32] = Sample 1 Left
//   Bits [63:48] = Sample 1 Right

module mdp_audio
(
	input             clk,
	input             reset,

	output            DDRAM_CLK,
	input             DDRAM_BUSY,
	output reg  [7:0] DDRAM_BURSTCNT,
	output reg [28:0] DDRAM_ADDR,
	input      [63:0] DDRAM_DOUT,
	input             DDRAM_DOUT_READY,
	output reg        DDRAM_RD,
	output     [63:0] DDRAM_DIN,
	output      [7:0] DDRAM_BE,
	output            DDRAM_WE,

	input             active,
	input      [15:0] buf_wr_ptr,
	output     [15:0] buf_rd_ptr,

	input             track_start,
	input             stop_request,
	input       [7:0] fade_sectors,
	input       [7:0] volume,
	input             resume_request,
	input             osd_pause,

	output reg signed [15:0] audio_l,
	output reg signed [15:0] audio_r
);

assign DDRAM_CLK = clk;
// Read-only DDRAM access
assign DDRAM_DIN = 64'd0;
assign DDRAM_BE  = 8'hFF;
assign DDRAM_WE  = 1'b0;

// Ring buffer: 64KB, byte address 0x30000000 -> DDRAM_ADDR = 0x30000000 >> 3
localparam [28:0] DDRAM_BASE = 29'h6000000;
localparam [15:0] BUF_MASK   = 16'hFFFF;

// Internal FIFO (256 stereo samples in M10K BRAM)
(* ramstyle = "M10K" *) reg [31:0] fifo_mem [0:255];

reg  [7:0] fifo_wr;
reg  [7:0] fifo_rd;
wire [8:0] fifo_used  = {1'b0, fifo_wr} - {1'b0, fifo_rd};
wire       fifo_low   = (fifo_used < 9'd128);
wire       fifo_full  = (fifo_used >= 9'd254);
wire       fifo_empty = (fifo_wr == fifo_rd);

reg [31:0] fifo_rdata;
always @(posedge clk) fifo_rdata <= fifo_mem[fifo_rd];

// Read pointer
reg [15:0] rd_ptr;
assign buf_rd_ptr = rd_ptr;

wire [16:0] buf_avail = {1'b0, buf_wr_ptr} - {1'b0, rd_ptr};
wire        buf_has_data = (buf_avail[15:0] >= 16'd8);

// Pause state
reg paused;

always @(posedge clk) begin
	if (reset) begin
		paused <= 0;
	end else begin
		if (track_start)
			paused <= 0;
		else if (stop_request && fade_sectors == 0)
			paused <= 1;
		else if (resume_request)
			paused <= 0;
	end
end

// Track-start mute: suppress output for ~50ms to let HPS pre-fill
// 50ms at 53.7MHz = ~2,685,000 clocks
reg [21:0] mute_ctr;
wire       muted = |mute_ctr;

always @(posedge clk) begin
	if (reset)
		mute_ctr <= 0;
	else if (track_start)
		mute_ctr <= 22'd2685000;
	else if (mute_ctr > 0)
		mute_ctr <= mute_ctr - 1'd1;
end

// Fade engine
// $13XX fades over XX sectors at 75 sectors/sec.
// Ramps fade_vol 255->0 in 255 steps.
// Step duration = (sectors/75) * clk_freq / 255 = ~sectors * 2808 clocks.
reg  [7:0] fade_vol;
reg        fading;
reg [19:0] fade_timer;
reg [19:0] fade_step;

always @(posedge clk) begin
	if (reset) begin
		fade_vol  <= 8'hFF;
		fading    <= 0;
	end else begin
		if (track_start) begin
			fade_vol <= 8'hFF;
			fading   <= 0;
		end
		else if (stop_request) begin
			if (fade_sectors == 0) begin
				fade_vol <= 8'hFF;
				fading   <= 0;
			end else begin
				fading    <= 1;
				fade_step <= {12'd0, fade_sectors} * 20'd2808;
				fade_timer<= 0;
			end
		end
		else if (fading) begin
			if (fade_timer >= fade_step) begin
				fade_timer <= 0;
				if (fade_vol == 0)
					fading <= 0;
				else
					fade_vol <= fade_vol - 1'd1;
			end else begin
				fade_timer <= fade_timer + 1'd1;
			end
		end
	end
end

// eff_volume = (game_volume * fade_vol) >> 8
wire [15:0] vol_product = {8'd0, volume} * {8'd0, fade_vol};
wire  [7:0] eff_volume  = vol_product[15:8];

// 44.1 kHz sample clock (~53.7 MHz / 1218 = ~44083 Hz)
reg [10:0] sample_div;
reg        sample_tick;

always @(posedge clk) begin
	sample_tick <= 0;
	if (reset)
		sample_div <= 0;
	else if (sample_div >= 11'd1217) begin
		sample_div  <= 0;
		sample_tick <= 1;
	end else
		sample_div <= sample_div + 1'd1;
end

// DDRAM read state machine
localparam [2:0] DDR_IDLE    = 3'd0,
                 DDR_REQ     = 3'd1,
                 DDR_WAIT    = 3'd2,
                 DDR_STORE0  = 3'd3,
                 DDR_STORE1  = 3'd4;

reg  [2:0] ddr_state;
reg [63:0] ddr_latch;

always @(posedge clk) begin
	if (reset) begin
		ddr_state  <= DDR_IDLE;
		DDRAM_RD   <= 0;
		rd_ptr     <= 0;
		fifo_wr    <= 0;
	end else begin
		DDRAM_RD <= 0;

		case (ddr_state)
			DDR_IDLE: begin
				if (active && !paused && !osd_pause && !muted && fifo_low && buf_has_data)
					ddr_state <= DDR_REQ;
			end

			DDR_REQ: begin
				if (!DDRAM_BUSY) begin
					DDRAM_ADDR     <= DDRAM_BASE + {16'd0, rd_ptr[15:3]};
					DDRAM_BURSTCNT <= 8'd1;
					DDRAM_RD       <= 1;
					ddr_state      <= DDR_WAIT;
				end
			end

			DDR_WAIT: begin
				if (DDRAM_DOUT_READY) begin
					ddr_latch <= DDRAM_DOUT;
					if (!fifo_full) begin
						fifo_mem[fifo_wr] <= DDRAM_DOUT[31:0];
						fifo_wr <= fifo_wr + 1'd1;
					end
					ddr_state <= DDR_STORE1;
				end
			end

			DDR_STORE1: begin
				if (!fifo_full) begin
					fifo_mem[fifo_wr] <= ddr_latch[63:32];
					fifo_wr <= fifo_wr + 1'd1;
				end
				// 8 bytes = one 64-bit word consumed
				rd_ptr    <= (rd_ptr + 16'd8) & BUF_MASK;
				ddr_state <= DDR_IDLE;
			end

			default: ddr_state <= DDR_IDLE;
		endcase

		if (track_start) begin
			fifo_wr   <= 0;
			rd_ptr    <= 0;
			ddr_state <= DDR_IDLE;
			DDRAM_RD  <= 0;
		end
	end
end

// Audio output: volume-scaled at 44.1kHz sample rate
wire signed [15:0] raw_l = $signed(fifo_rdata[15:0]);
wire signed [15:0] raw_r = $signed(fifo_rdata[31:16]);

wire signed [24:0] scaled_l = raw_l * $signed({1'b0, eff_volume});
wire signed [24:0] scaled_r = raw_r * $signed({1'b0, eff_volume});

always @(posedge clk) begin
	if (reset) begin
		audio_l <= 0;
		audio_r <= 0;
		fifo_rd <= 0;
	end else if (sample_tick) begin
		if (active && !paused && !osd_pause && !muted && !fifo_empty && fade_vol > 0) begin
			fifo_rd <= fifo_rd + 1'd1;
			audio_l <= scaled_l[23:8];
			audio_r <= scaled_r[23:8];
		end else begin
			audio_l <= 0;
			audio_r <= 0;
		end
	end

	if (track_start)
		fifo_rd <= 0;
end

endmodule
