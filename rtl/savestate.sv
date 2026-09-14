// destructive read: some stages are combinational, so ss_out can't loop back to ss_in.
module savestate #(
	// at least 17: ST_PAUSE reads guard[16]
	parameter GUARD_BITS = 24
)
(
	input             clk,
	input             reset,

	input             ss_save,
	input             ss_load,
	output            busy,

	// measurement destroys machine state; unheld, the core boots on whatever
	// calibration left in the flops, a black screen on hardware
	output            cal_busy,
	output            cal_failed,
	// the measured length, which ss_ddr needs: a transfer of the chain asks for
	// "the whole chain" rather than a word count, and this is that count
	output reg [15:0] chain_len = 0,

	// freezing mid bus cycle left the 68000 with a half finished access while
	// memory around it kept running, and the game restarted every time
	output reg        pause_req = 0,
	input             bus_free,
	// port B of the snapshot buffer, on the DDRAM clock: ss_ddr reads a
	// capture out of it and writes a restore back through the same port
	input             bufb_clk,
	input       [9:0] bufb_addr,
	output     [63:0] bufb_q,

	(* preserve, dont_merge *) output reg ss_en = 0,
	(* preserve, dont_merge *) output reg ss_en_cpu = 0,
	(* preserve, dont_merge *) output reg ss_en_vdp_fm = 0,
	(* preserve, dont_merge *) output reg ss_en_vram = 0,
	output reg        ss_in = 0,
	input             ss_out,

	// save_req stays up until ss_ddr answers, keeping busy high so the buffer
	// is not overwritten mid-copy
	output reg        save_req = 0,
	output reg        load_req = 0,
	input             xfer_ack,
	// header main polls at the slot start: a change detector plus payload size.
	// See process_ss() in Main_MiSTer's user_io.cpp.
	output reg        blk_hdr = 0,
	output reg        blk_id = 0,
	output     [31:0] hdr_words32,
	input             hdr_present,
	input      [15:0] hdr_chain,
	output reg [15:0] blk_off = 0,     // word offset of this transfer inside the slot
	output reg  [9:0] blk_len = 0,     // 0 means the chain, whose length is measured
	output reg  [9:0] blk_base = 0,    // where in the buffer the transfer reads or writes

	// the machine's memories, walked one 16-bit word at a time through a shared
	// bus. only one is selected at a time and they all answer on ss_mem_dout.
	output reg [15:0] mem_addr = 0,
	output reg  [3:0] mem_sel = 0,
	output reg [15:0] mem_din = 0,
	output reg        mem_wr = 0,
	// the same strobe held for the whole three clock phase, for the one memory
	// that does not run on this clock: see the block below
	output            mem_wr_hold,
	input      [15:0] mem_dout,

	// port B of the snapshot buffer again, this time as a write: the restore
	// path fills it from DDR3 before the machine is frozen
	input             bufb_we,
	input      [63:0] bufb_din
);

	localparam ST_FLUSH   = 5'd0;
	localparam ST_MARK    = 5'd1;
	localparam ST_MEASURE = 5'd2;
	localparam ST_IDLE    = 5'd3;
	localparam ST_HDR     = 5'd17;   // write the header main polls, after a save
	localparam ST_HDRCHK  = 5'd18;   // read it before a restore: is the slot empty
	localparam ST_OUT     = 5'd4;
	localparam ST_IN      = 5'd5;
	localparam ST_DONE    = 5'd6;
	localparam ST_PRE     = 5'd7;
	localparam ST_FILL1   = 5'd8;
	localparam ST_PAUSE   = 5'd9;
	localparam ST_FETCH   = 5'd11;   // waiting for ss_ddr to fill the buffer from a slot
	localparam ST_MREAD   = 5'd12;   // filling the top of the buffer from a memory
	localparam ST_MOUT    = 5'd13;   // that chunk on its way to the slot
	localparam ST_MIN     = 5'd14;   // a chunk on its way back from the slot
	localparam ST_MWRITE  = 5'd15;   // writing that chunk back into a memory
	localparam ST_CHOUT   = 5'd16;   // the chain is on its way to the slot
	localparam ST_IDCHK   = 5'd19;   // read identity before a restore: magic, chain length
	localparam ST_ID      = 5'd20;   // write identity after a save, before the header

	// sel: 0 68000 RAM, 1 Z80 RAM, 2 VRAM, 3 CRAM/VSRAM, 4 cartridge state, 5 sprite cache
	// sat is written only on VRAM writes to the sprite table, never refilled from VRAM
	localparam  [9:0] CHUNK_BASE = 10'd512;  // the top half of the buffer
	localparam  [9:0] CHUNK      = 10'd256;
	localparam  [2:0] N_MEM      = 3'd6;

	// derived from the buffer, never hand-typed: a stale hand-written value here
	// once outgrew the chain and calibration silently stored chain_len 0.
	localparam BUF_WORDS = 1024;
	localparam MAX_WORDS = BUF_WORDS/2;

	// a hardware chain that comes back a different length than simulation measured
	// means synthesis built something other than what was tested

	// reading a single bit straight out of buf_mem forces the whole word out
	// combinationally, and Quartus builds it from flip-flops and muxes instead
	// of M10K: measured cost of getting this wrong, 122 percent of the device.
	reg [63:0] outsh = 0;
	reg  [8:0] rdaddr = 0;

	// every reg here needs its own power-up value: a testbench always resets first,
	// so simulation can never show what hardware does before a reset pulse arrives.
	reg  [4:0] state = ST_FILL1;
	reg        calibrated = 0;
	reg [15:0] bitcnt = 0;
	reg  [8:0] widx = 0;
	reg  [5:0] bidx = 0;
	reg [63:0] shreg = 0;
	reg        out_pad = 0;   // the capture is past chain_len, filling the last word
	reg [GUARD_BITS-1:0] guard = 0;
	reg [21:0] save_guard = 0;
	reg        saving = 0;
	reg        loading = 0;
	reg        xfer_ok = 0;
	// where the walk ended, in 64-bit words, carried rather than typed: main wants
	// the payload size and this is the one place that already knows it.
	reg [15:0] payload_end = 0;
	assign hdr_words32 = {15'd0, payload_end, 1'b0};   // 32-bit words
	reg  [2:0] mem_idx = 0;     // which memory of the table is being walked
	reg  [5:0] mchunk = 0;      // which chunk of it is in flight
	reg  [2:0] mphase = 0;      // which 16-bit word of the 64-bit buffer word
	reg  [8:0] mword = 0;       // buffer word inside the chunk
	reg  [1:0] mrd = 0;         // the two clocks a block RAM read takes to answer
	reg [63:0] mpack = 0;
	reg [15:0] hit_cnt = 0;   // raw bitcnt when the marker arrived, before any clamping

	reg        fsm_busy = 0;
	// busy stays up through the DDR3 copy as well: the buffer must not be
	// overwritten by a new snapshot while ss_ddr is still reading it out.
	assign busy = fsm_busy | save_req | load_req;
	assign cal_busy = ~calibrated;
	assign cal_failed = calibrated & (chain_len == 0);

	// hdr_ok is registered rather than compared inline: the compare sat in front
	// of every scan-enable replica and cost several nanoseconds there.
	reg        hdr_ok = 0;
	reg  [1:0] ack_sync = 0;
	always @(posedge clk) ack_sync <= {ack_sync[0], xfer_ack};

	// the cartridge runs on clk_sys, half of clk_md: a one-clock strobe at 107 MHz
	// falls between clk_sys edges on words that start on an even clock, so those
	// words were dropped on every restore. hold it for the whole three-clock phase.
	reg [1:0] wr_ext = 0;
	always @(posedge clk) begin
		if (mem_wr)       wr_ext <= 2'd2;
		else if (|wr_ext) wr_ext <= wr_ext - 1'd1;
	end
	assign mem_wr_hold = mem_wr | (|wr_ext);
	// idle needs ack_sync[1] down too, two clocks behind ack: a state waiting only
	// on its own request could raise the next one inside that window and see the
	// *previous* transfer's ack, which is what stopped the header ever being written.
	wire xfer_idle = ~save_req & ~load_req & ~ack_sync[1];
	wire [63:0] nextword = {shreg[62:0], ss_out};
	// a partial last word sits at the low end of the shift register while ST_IN
	// feeds from bit 63 down; ST_OUT already zero-fills the padding, so shifting
	// onto the word boundary needs nothing extra to reach it.

	// continuous assignments, not always @*: that block skips the first event, so
	// at time zero cur_last read x, "mchunk != cur_last" was x, and the walk left
	// work RAM after one chunk in simulation while synthesis built it correctly.
	wire  [3:0] cur_sel  = (mem_idx == 3'd0) ? 4'd0      : (mem_idx == 3'd1) ? 4'd1     :
	                       (mem_idx == 3'd2) ? 4'd2      : (mem_idx == 3'd3) ? 4'd3     :
	                       (mem_idx == 3'd4) ? 4'd4      : 4'd5;
	wire [15:0] cur_off  = (mem_idx == 3'd0) ? 16'd1024  : (mem_idx == 3'd1) ? 16'd9216 :
	                       (mem_idx == 3'd2) ? 16'd11264 : (mem_idx == 3'd3) ? 16'd27648 :
	                       (mem_idx == 3'd4) ? 16'd28672 : 16'd28928;
	wire  [5:0] cur_last = (mem_idx == 3'd0) ? 6'd31     : (mem_idx == 3'd1) ? 6'd7     :
	                       (mem_idx == 3'd2) ? 6'd63     : 6'd0;
	wire [15:0] nxt_off  = (mem_idx == 3'd0) ? 16'd9216  : (mem_idx == 3'd1) ? 16'd11264 :
	                       (mem_idx == 3'd2) ? 16'd27648 : (mem_idx == 3'd3) ? 16'd28672 : 16'd28928;
	// mem_sel is registered with the address, not derived from mem_idx: mem_idx
	// advances on the last write, so a combinational selector sent that word
	// to the next memory instead.

	// the memory walk borrows the top half of the buffer, a chunk at a time, while
	// the chain capture keeps the bottom half
	wire        mem_phase = (state == ST_MREAD) || (state == ST_MWRITE);

	// four 16-bit words shifted in from the top make one buffer word, so the word
	// at the lowest memory address ends up in the lowest bits
	wire [63:0] mpack_next = {mem_dout, mpack[63:16]};
	wire [63:0] bufword  = mem_phase ? mpack_next : nextword;
	wire        in_phase = (state == ST_PRE) || (state == ST_IN);
	wire        buf_we   = ((state == ST_OUT) && (&bidx))
	                     || ((state == ST_MREAD) && (mrd == 2'd2) && (mphase == 3'd3));
	wire  [9:0] addra = mem_phase ? (CHUNK_BASE + {1'b0, mword})
	                              : {1'b0, in_phase ? rdaddr : widx};

	// port A carries one address for both fill and replay: they never happen at
	// once, and two addresses on one port stop M10K inference.
	wire [63:0] rdword;
	// second half starts at 256, not 200: the address is a concatenation, and
	// sizing the memory at 400 words put the second capture past its end.
	ss_buf #(.WORDS(BUF_WORDS)) buf_mem
	(
		.clka(clk), .wea(buf_we), .addra(addra), .dina(bufword), .qa(rdword),
		.clkb(bufb_clk), .web(bufb_we), .dinb(bufb_din), .addrb(bufb_addr), .qb(bufb_q)
	);

	// Blocking next-state temporary: every replica samples the same D on this
	// edge, including hold, reset and the final watchdog override. No pipeline.
	reg ss_en_next;
	always @(posedge clk) begin
		ss_en_next = ss_en;
		if (reset) begin
			state      <= ST_FILL1;
			ss_en_next = 0;
			ss_in      <= 0;
			fsm_busy       <= 0;
			save_req   <= 0;
			load_req   <= 0;
			mem_wr     <= 0;
			save_guard <= 0;
			xfer_ok    <= 0;
			bitcnt     <= 0;
			out_pad    <= 0;
			chain_len  <= 0;
			calibrated <= 0;
			blk_off    <= 0;
			blk_len    <= 0;
			blk_base   <= 0;
			blk_hdr    <= 0;
			blk_id     <= 0;
			payload_end <= 0;
		end
		else begin
			// one clock wide, always: left set past ST_MWRITE it wrote stale data
			// at a stale address into the memory being restored on every later clock.
			mem_wr <= 0;

			// give up after about forty milliseconds: an unanswered request would
			// hold busy high for good and the copy itself needs only tens of us.
			if (save_req | load_req) begin
				save_guard <= save_guard + 1'b1;
				if (ack_sync[1] || &save_guard) begin
					save_req   <= 0;
					load_req   <= 0;
					save_guard <= 0;
					xfer_ok    <= ack_sync[1];
				end
			end
			else save_guard <= 0;

			case (state)

			// continuity check before anything else: drive ones the whole length of
			// the chain and see whether one arrives. a chain cut anywhere by synthesis
			// looks exactly like a lost marker later on, and the two need different fixes.
			ST_FILL1: begin
				ss_en_next = 1;
				ss_in  <= 1;
				bitcnt <= bitcnt + 1'b1;
				// only believe it once ones have had time to cross: at reset the chain
				// still holds machine state, which is full of ones on its own
				if (bitcnt > 16'd40000) begin bitcnt <= 0; state <= ST_FLUSH; end
			end

			// push zeros through first: the chain powers up holding reset values and
			// if ss_out already reads 1 the marker looks like it arrived immediately
			ST_FLUSH: begin
				ss_en_next = 1;
				ss_in  <= 0;
				bitcnt <= bitcnt + 1'b1;
				if (bitcnt > 16'd40000) begin bitcnt <= 0; state <= ST_MARK; end
			end

			ST_MARK: begin
				ss_in  <= 1;
				bitcnt <= 0;
				state  <= ST_MEASURE;
			end

			ST_MEASURE: begin
				ss_in  <= 0;
				bitcnt <= bitcnt + 1'b1;
				if (ss_out) begin
					// a chain longer than the buffer would write past buf_mem's end and
					// shift back as garbage with no reset to recover; treat it as failed.
					chain_len  <= (bitcnt > MAX_WORDS*64) ? 16'd0 : bitcnt;
					// a marker present on the first measuring clock means the chain never
					// shifted (ss_out is the Z80's IORQ, held high in reset), not a short
					// chain; both cases store zero, which is why they read alike.
					hit_cnt    <= bitcnt;
					calibrated <= 1;
					widx       <= 0;
					guard      <= 0;
					state      <= ST_IDLE;
					ss_en_next = 0;
				end
				else if (bitcnt > 16'd60000) begin
					// marker never came back: release the core and refuse snapshots
					// instead, a failed measurement must never hold it in reset.
					ss_en_next = 0;
					chain_len  <= 0;
					calibrated <= 1;
					widx       <= 0;
					guard      <= 0;
					state      <= ST_IDLE;
				end
			end

			ST_IDLE: begin
				ss_en_next = 0;
				pause_req <= 0;
				fsm_busy  <= 0;
				// a restore fetches its slot into the buffer before anything is frozen:
				// the machine should stand still for the shift, not for a memory read
				// that can be done while it is running.
				if (ss_load & calibrated & (chain_len != 0)) begin
					saving      <= 0;
					loading     <= 1;
					fsm_busy    <= 1;
					xfer_ok     <= 0;
					guard       <= 0;
					bitcnt      <= 0;
					widx        <= 0;
					bidx        <= 0;
					// the chain, from the top of the slot into the bottom of the buffer
					blk_off     <= 0;
					blk_len     <= 0;      // 0 means the chain, whose length the core measured
					blk_base    <= 0;
					rdaddr      <= 0;
					// the header first. main zeroes a slot it has no file for, so an
					// empty one has to be refused rather than shifted into the machine.
					blk_hdr     <= 1;
					load_req    <= 1;
					state       <= ST_HDRCHK;
				end
				else if (ss_save & calibrated & (chain_len != 0)) begin
					saving  <= ss_save;
					loading <= 0;
					fsm_busy   <= 1;

					guard  <= 0;
					bitcnt <= 0;
					widx   <= 0;
					bidx   <= 0;
					pause_req <= 1;
					state  <= ST_PAUSE;
				end
			end

			// the guard above already dropped load_req on the answer or the timeout,
			// so this only has to look at which one it was
			ST_HDRCHK: begin
				if (xfer_idle) begin
					blk_hdr <= 0;
					if (xfer_ok && hdr_present) begin
						blk_id   <= 1;
						blk_off  <= 0;
						load_req <= 1;
						state    <= ST_IDCHK;
					end
					else begin
						fsm_busy <= 0;
						loading  <= 0;
						state    <= ST_IDLE;
					end
				end
			end

			ST_IDCHK: begin
				if (xfer_idle) begin
					blk_id <= 0;
					if (xfer_ok && hdr_ok) begin
						blk_off  <= 16'd1;
						load_req <= 1;
						state    <= ST_FETCH;
					end
					else begin
						fsm_busy <= 0;
						loading  <= 0;
						state    <= ST_IDLE;
					end
				end
			end

			// before the header: main must not see the counter move before the payload is in
			ST_ID: begin
				if (xfer_idle) begin
					blk_id   <= 0;
					blk_hdr  <= 1;
					save_req <= 1;
					state    <= ST_HDR;
				end
			end

			// the payload is all in the slot; the header is what makes main write it
			// to a file, so it goes last and on its own.
			ST_HDR: begin
				if (xfer_idle) begin
					blk_hdr   <= 0;
					pause_req <= 0;
					fsm_busy  <= 0;
					state     <= ST_IDLE;
				end
			end

			ST_FETCH: begin
				if (xfer_idle) begin
					if (xfer_ok) begin
						pause_req <= 1;
						guard     <= 0;
						state     <= ST_PAUSE;
					end
					else begin
						fsm_busy <= 0;
						loading  <= 0;
						state    <= ST_IDLE;
					end
				end
			end

			// guard[16]: a settling count for the 68000, which has no bus-free
			// acknowledge of its own the way the Z80 side does
			ST_PAUSE: begin
				guard <= guard + 1'b1;
				if (bus_free && guard[16]) begin
					guard  <= 0;
					bitcnt <= 0;
					widx   <= 0;
					bidx   <= 0;
					rdaddr <= 0;
					// memories go back first, chain untouched; the other way round the
					// processors would run the length of the memory walk on stale registers
					if (loading) begin
						mchunk   <= 0;
						mword    <= 0;
						mphase   <= 0;
						mrd      <= 0;
						mem_idx  <= 0;
						blk_off  <= 16'd1024;
						blk_len  <= CHUNK;
						blk_base <= CHUNK_BASE;
						load_req <= 1;
						state    <= ST_MIN;
					end
					else begin
						ss_en_next = 1;
						state <= ST_OUT;
					end
				end
				else if (&guard) begin
					// final, not a retry: retrying holds the bus request long enough to
					// click the audio and stall the game
					pause_req     <= 0;
					fsm_busy      <= 0;
					state         <= ST_IDLE;
				end
			end

			// the machine is left holding zeros here, only sane again after ST_IN
			ST_OUT: begin
				ss_in  <= 0;
				shreg  <= nextword;
				bidx   <= bidx + 1'b1;
				bitcnt <= bitcnt + 1'b1;

				// exactly one write statement for buf_mem: two conditional writes, even
				// to the same address, stop Quartus inferring M10K and put 12800 bits
				// into logic instead, 117 percent of the device.

				if (&bidx) widx <= widx + 1'b1;

				if (bitcnt == chain_len - 1'b1) out_pad <= 1;
				if ((&bidx) && (out_pad || (bitcnt == chain_len - 1'b1))) begin
					rdaddr  <= 0;
					bitcnt  <= 0;
					widx    <= 0;
					bidx    <= 0;
					out_pad <= 0;
					state   <= ST_PRE;
				end
			end

			// give the registered read a couple of clocks to present word zero before
			// the first bit is needed, otherwise the opening 64 bits shift in stale.
			ST_PRE: begin
				// cartridge banking latches when sel drops from 4; left selected through
				// the shift, a banked game resumes on the wrong bank. Not a state earlier:
				// that clock still carries mem_wr for the walk's last word.
				mem_sel <= 4'd15;
				bidx <= bidx + 1'b1;
				if (bidx == 6'd2) begin
					outsh  <= rdword;
					rdaddr <= 1;
					bidx   <= 0;
					bitcnt <= 0;
					state  <= ST_IN;
				end
			end

			// put it back, same order it came out: a shift register reloaded with
			// its own contents in read order ends up exactly as it started
			ST_IN: begin
				// shift out of outsh, refilled once per word from the single registered
				// read of buf_mem below. reading the array from more than one place
				// stops Quartus inferring M10K and the buffer lands in logic instead.
				ss_in <= outsh[63];
				if (&bidx) begin
					outsh  <= rdword;
					rdaddr <= rdaddr + 1'b1;
				end
				else outsh <= {outsh[62:0], 1'b0};
				bidx   <= bidx + 1'b1;
				bitcnt <= bitcnt + 1'b1;
				if (&bidx) widx <= widx + 1'b1;
				if (bitcnt == chain_len - 1'b1) state <= ST_DONE;
			end


			ST_DONE: begin
				loading       <= 0;
				ss_en_next = 0;
				// a save walks its memories out after the chain; a restore is done here
				if (saving) begin
					blk_off  <= 16'd1;
					blk_len  <= 0;      // the chain, whose length the core measured
					blk_base <= 0;
					save_req <= 1;
					mchunk   <= 0;
					mword    <= 0;
					mphase   <= 0;
					mrd      <= 0;
					mem_idx  <= 0;
					state    <= ST_CHOUT;
				end
				else begin
					pause_req <= 0;
					fsm_busy  <= 0;
					state     <= ST_IDLE;
				end
			end

			// the chain is on its way to the slot; the memories follow it
			ST_CHOUT: begin
				if (xfer_idle) begin
					if (xfer_ok) state <= ST_MREAD;
					else begin
						pause_req <= 0;
						fsm_busy  <= 0;
						state     <= ST_IDLE;
					end
				end
			end

			ST_MREAD: begin
				mrd <= mrd + 1'b1;
				if (mrd == 2'd0) begin
					mem_addr <= {mchunk, mword[7:0], mphase[1:0]};
					mem_sel  <= cur_sel;
				end
				if (mrd == 2'd2) begin
					mrd   <= 0;
					mpack <= mpack_next;
					if (mphase == 3'd3) begin
						mphase <= 0;
						if (mword == CHUNK[8:0] - 1'b1) begin
							mword    <= 0;
							blk_off  <= cur_off + {2'd0, mchunk, 8'd0};
							blk_len  <= CHUNK;
							blk_base <= CHUNK_BASE;
							payload_end <= cur_off + {2'd0, mchunk, 8'd0} + {6'd0, CHUNK};
							save_req <= 1;
							state    <= ST_MOUT;
						end
						else mword <= mword + 1'b1;
					end
					else mphase <= mphase + 1'b1;
				end
			end

			ST_MOUT: begin
				if (xfer_idle) begin
					if (!xfer_ok) begin
						pause_req <= 0;
						fsm_busy  <= 0;
						state     <= ST_IDLE;
					end
					else if (mchunk != cur_last) begin
						mchunk <= mchunk + 1'b1;
						state  <= ST_MREAD;
					end
					else if (mem_idx != N_MEM - 1'b1) begin
						mem_idx <= mem_idx + 1'b1;
						mchunk  <= 0;
						state   <= ST_MREAD;
					end
					else begin
						mem_sel  <= 4'd15;
						blk_id   <= 1;
						blk_off  <= 0;
						blk_len  <= 0;
						blk_base <= 0;
						save_req <= 1;
						state    <= ST_ID;
					end
				end
			end

			// the restore side: a chunk comes back from the slot, then goes into the
			// memory a word at a time
			ST_MIN: begin
				if (xfer_idle) begin
					if (xfer_ok) begin
						mword  <= 0;
						mphase <= 0;
						mrd    <= 0;
						state  <= ST_MWRITE;
					end
					else begin
						pause_req <= 0;
						fsm_busy  <= 0;
						loading   <= 0;
						state     <= ST_IDLE;
					end
				end
			end

			ST_MWRITE: begin
				mrd <= mrd + 1'b1;
				if (mrd == 2'd2) begin
					mrd <= 0;
					// phase 0 only waits for the buffer word the address has been
					// presenting; phases 1 to 4 push its four halves into the memory
					if (mphase == 3'd0) begin
						mpack  <= rdword;
						mphase <= 1;
					end
					else begin
						mem_addr <= {mchunk, mword[7:0], mphase[1:0] - 2'd1};
						mem_sel  <= cur_sel;
						mem_din  <= mpack[15:0];
						mpack    <= {16'd0, mpack[63:16]};
						mem_wr   <= 1;
						if (mphase == 3'd4) begin
							mphase <= 0;
							if (mword == CHUNK[8:0] - 1'b1) begin
								mword <= 0;
								if (mchunk != cur_last) begin
									mchunk   <= mchunk + 1'b1;
									blk_off  <= cur_off + {2'd0, (mchunk + 1'b1), 8'd0};
									blk_len  <= CHUNK;
									blk_base <= CHUNK_BASE;
									load_req <= 1;
									state    <= ST_MIN;
								end
								else if (mem_idx != N_MEM - 1'b1) begin
									// nxt_off is the next memory's offset: cur_off follows
									// mem_idx combinationally and has not moved yet here
									mem_idx  <= mem_idx + 1'b1;
									mchunk   <= 0;
									blk_off  <= nxt_off;
									blk_len  <= CHUNK;
									blk_base <= CHUNK_BASE;
									load_req <= 1;
									state    <= ST_MIN;
								end
								else begin
									// memories are back; the chain goes in last, so the
									// processors resume with registers that match them
									ss_en_next = 1;
									bitcnt <= 0;
									widx   <= 0;
									bidx   <= 0;
									rdaddr <= 0;
									state  <= ST_PRE;
								end
							end
							else mword <= mword + 1'b1;
						end
						else mphase <= mphase + 1'b1;
					end
				end
			end

			default: state <= ST_IDLE;
			endcase


			// watchdog last so it overrides the case above. a snapshot freezes the
			// whole machine, so a stuck controller takes the core down with it and
			// the only way out is a power cycle.
			if (state != ST_IDLE && state != ST_PAUSE && calibrated) begin
				guard <= guard + 1'b1;
				if (&guard) begin
					// unfreezing here leaves the machine holding a half-restored chain,
					// which is just as dead as staying frozen. clear calibrated so
					// cal_busy holds the core in reset and the whole sequence restarts.
					state      <= ST_FILL1;
					ss_en_next = 0;
					fsm_busy   <= 0;
					bitcnt     <= 0;
					out_pad    <= 0;
					calibrated <= 0;
				end
			end
		end
		hdr_ok       <= (hdr_chain == chain_len);
		ss_en        <= ss_en_next;
		ss_en_cpu    <= ss_en_next;
		ss_en_vdp_fm <= ss_en_next;
		ss_en_vram   <= ss_en_next;
	end

endmodule
