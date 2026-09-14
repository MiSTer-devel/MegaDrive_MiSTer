// runs on clk_sys, DDRAM_CLK's own clock: issuing requests from clk_md dropped words.
module ss_ddr #(
	parameter [28:0] DDR_BASE = 29'h7C00000  // byte 0x3E000000
)
(
	input             clk,          // must be the clock DDRAM_CLK is driven from

	input      [15:0] chain_len,


	output reg        busy = 0,
	input             ddr_busy,
	output reg [28:0] ddr_addr = 0,
	output reg [63:0] ddr_din = 0,
	output reg        ddr_we = 0,
	output reg  [7:0] ddr_burstcnt = 0,
	output reg  [7:0] ddr_be = 8'hFF,

	// port B: the captured chain goes out after the status words, so the
	// machine state can be diffed from Linux
	output      [9:0] buf_addr,
	input      [63:0] buf_q,
	output reg        buf_we = 0,
	output reg [63:0] buf_din = 0,

	input             req_save,
	input             req_load,
	input       [1:0] slot,
	// the chain transfer uses offset 0 and the measured length; other transfers
	// walk the memories through the top half a chunk at a time
	input      [15:0] blk_off,
	input       [9:0] blk_len,
	input       [9:0] blk_base,
	// two-word header at the start of the slot: main polls word 0 as a change
	// detector and word 1 as the payload size, writing the file when word 0
	// changes. See process_ss() in user_io.cpp.
	input             blk_hdr,
	input             blk_id,
	// off: state goes into the slot but the change detector is handed back its
	// old value, so main sees nothing new and writes no file; a restore inside
	// this session still finds the slot
	input             save_sd,
	input      [31:0] hdr_words32,
	output reg        hdr_present = 0,
	// the chain length the slot was written with, read back out of the header
	output reg [15:0] hdr_chain = 0,
	output reg        ack = 0,
	output reg        ddr_rd = 0,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,

	input             port_ok
);

	// chain_len crosses from the machine clock. it changes only while calibration
	// runs and is static afterwards, so two flops are enough.
	reg [15:0] s_len1 = 0, s_len = 0;

	reg        settle = 0;


	reg  [1:0] rq1 = 0, rq2 = 0;   // the requests arrive from the machine clock
	reg  [9:0] xw = 0;
	reg  [9:0] wa = 0;             // address held for the buffer write
	reg        rd_pend = 0;        // a read was accepted and its data has not arrived
	reg  [1:0] mode = 0;           // 0 idle, 1 save, 2 load

	// combinational: a registered address plus registered memory read is two
	// clocks of latency, and one settle cycle only covers one; the dump came out
	// shifted by a word when this was registered.
	assign buf_addr = buf_we ? wa : (blk_base + xw);


	// words one capture occupies, from the measured length; duplicating this
	// elsewhere is a bug waiting for a build
	wire  [9:0] nwords = (s_len + 16'd63) >> 6;
	// a slot is 32768 words, 256 KB: four put the top of the region at byte
	// 0x3E140000, inside what the kernel command line keeps from Linux and clear
	// of the CDDA ring buffer at byte 0x30000000
	localparam [28:0] SLOT0 = DDR_BASE + 29'd32768;
	wire [28:0] slot_base = SLOT0 + {12'd0, slot, 15'd0};

	// blk_len of zero means "the chain", whose length only the core knows
	wire  [9:0] xlen  = (blk_len == 0) ? nwords : blk_len;
	// the payload starts one 64-bit word in: main owns word 0 of every slot
	wire [28:0] xbase = blk_hdr ? slot_base : (slot_base + 29'd1 + {13'd0, blk_off});
	wire  [9:0] xwords = (blk_hdr || blk_id) ? 10'd1 : xlen;

	// main takes the low half as the change detector, the high half as the size;
	// the size is the controller's own walk length, not a constant
	reg [31:0] save_count = 0;
	wire [63:0] hdr_word = {hdr_words32, 16'd0, save_count[15:0]};
	// in its own word: main overwrites word 0 with 0xFFFFFFFF on every file load
	localparam [31:0] ID_MAGIC = 32'h4D445353;   // "MDSS"
	wire [63:0] id_word = {ID_MAGIC, 16'd0, s_len};



	always @(posedge clk) begin
		{s_len, s_len1} <= {s_len1, chain_len};
		{rq2, rq1} <= {rq1, {req_load, req_save}};

		ddr_we <= 0;
		ddr_rd <= 0;
		buf_we <= 0;

		case (mode)

		2'd0: begin
			busy <= 0;
			// four-phase handshake: ack stays up until the request drops. a one-shot
			// pulse here is two clocks wide in the controller's faster domain, which
			// is too thin to rely on a synchroniser catching.
			if (!rq2[0] && !rq2[1]) ack <= 0;
			if (rq2[0] && !ack && port_ok)      begin mode <= 2'd1; xw <= 0; settle <= 1; busy <= 1; end
			else if (rq2[1] && !ack && port_ok) begin mode <= 2'd2; xw <= 0; rd_pend <= 0; busy <= 1; end
		end


		// snapshot out to its slot
		2'd1: begin
			if (settle) settle <= 0;
			else if (!ddr_we) begin
				ddr_addr     <= xbase + xw;
				ddr_din      <= blk_hdr ? hdr_word : (blk_id ? id_word : buf_q);
				ddr_burstcnt <= 8'd1;
				ddr_be       <= (blk_hdr && !save_sd) ? 8'hF0 : 8'hFF;
				ddr_we       <= 1;
			end
			else if (ddr_busy) ddr_we <= 1;
			else begin
				xw     <= xw + 1'b1;
				settle <= 1;
				if (xw + 1'b1 == xwords) begin
					// bumping the detector is what tells main to write the file, so it
					// happens once, on the header word, after the payload is all there
					if (blk_hdr) save_count <= save_count + 1'b1;
					ack  <= 1;
					mode <= 2'd0;
				end
			end
		end

		// snapshot back in from its slot. the request has to stay asserted until the
		// controller takes it, exactly as for a write, and the data arrives later on
		// its own ready line.
		2'd2: begin
			// one read in flight at a time. issuing the next one while waiting for
			// data asks for the same word twice and the extra answer advances the
			// counter past the end of the slot.
			if (!rd_pend && !ddr_rd) begin
				ddr_addr     <= xbase + xw;
				ddr_burstcnt <= 8'd1;
				ddr_rd       <= 1;
			end
			else if (ddr_rd && ddr_busy) ddr_rd <= 1;
			else if (ddr_rd)             rd_pend <= 1;

			if (rd_pend && ddr_dout_ready) begin
				// a header read answers one question: is there a state in this slot at
				// all. main zeroes a slot it has no file for, so a size of zero means
				// empty and the restore has to be refused rather than shifted in.
				if (blk_hdr) begin
					hdr_present <= |ddr_dout[63:32];
				end
				else if (blk_id) begin
					hdr_chain <= (ddr_dout[63:32] == ID_MAGIC) ? ddr_dout[15:0] : 16'd0;
				end
				else begin
					buf_din <= ddr_dout;
					wa      <= blk_base + xw;
					buf_we  <= 1;
				end
				rd_pend <= 0;
				xw      <= xw + 1'b1;
				if (xw + 1'b1 == xwords) begin ack <= 1; mode <= 2'd0; end
			end
		end

		endcase
	end

endmodule
