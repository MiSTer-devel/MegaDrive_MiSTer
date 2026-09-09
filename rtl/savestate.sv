// Savestate controller.
//
// Reading the scan chain is destructive, so the machine has to be put back
// afterwards. The obvious trick, feeding ss_out straight back into ss_in, does
// not work here: several stages of the chain are combinational pass-throughs,
// so closing that loop creates a real combinational cycle. Measured on the
// running core, a full rotation of any length left the machine limping at one
// percent of its normal bus rate, and on hardware it killed video sync outright.
//
// So the chain is read into a local buffer and shifted back from there. The
// buffer is 12409 bits, under 2 KB, which is one M10K block on a device where
// block RAM is only half used.
//
// Chain length is measured on the actual chip at reset rather than trusted from
// a parameter: what synthesis builds can differ from what simulation says, and a
// rotation off by one position scrambles every flop into its neighbour.

module savestate
(
	input             clk,
	input             reset,

	input             ss_save,
	input             ss_load,
	output            busy,

	// the measurement destroys machine state, so the core must be held in reset
	// until it finishes. without this the machine boots out of whatever the
	// calibration left in its flops, which on hardware is a black screen.
	output            cal_busy,
	output            cal_failed,
	// the measured length, which ss_ddr needs: a transfer of the chain asks for
	// "the whole chain" rather than a word count, and this is that count
	output reg [15:0] chain_len = 0,

	// asks the machine to let go of the bus before anything is frozen, through the
	// same arbitration the OSD pause uses. freezing mid bus cycle left the 68000
	// with a half finished access while the memory around it kept running, and the
	// game restarted every time.
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

	// the snapshot goes to DDR3 from ss_ddr, on the clock the memory port is
	// driven from. this module used to write it straight from clk_md with no
	// ddr_busy handshake, which is the bug ss_ddr exists to avoid; that path was
	// dead behind a DRY_RUN parameter and is gone. save_req stays up until ss_ddr
	// answers, which also keeps busy high so the buffer is not overwritten mid-copy.
	output reg        save_req = 0,
	output reg        load_req = 0,
	input             xfer_ack,
	// The header MiSTer main polls at the start of every slot: a change detector
	// it watches to know a save happened, and the payload size it needs to write
	// the file. See process_ss() in Main_MiSTer's user_io.cpp.
	output reg        blk_hdr = 0,
	output     [31:0] hdr_words32,
	input             hdr_present,
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

	// The machine's memories, walked one after another. Every one of them is read
	// as 16-bit words on a shared bus, four to a 64-bit buffer word, whatever its
	// real width: the Z80's RAM and VRAM are bytes and waste the upper half. That
	// costs slot space, which is free here, and buys one walk instead of three.
	//
	// A chunk is 256 buffer words, so 1024 words of memory. Offsets are in 64-bit
	// words from the start of the slot; the chain sits at 0 and needs 260.
	//
	//   sel  memory            16-bit words  chunks  slot offset
	//    0   68000 work RAM          32768      32         1024
	//    1   Z80 RAM                  8192       8         9216
	//    2   VRAM                    65536      64        11264
	//    3   CRAM and VSRAM           1024       1        27648
	//    4   cartridge state          1024       1        28672
	//
	// The last one is the VDP's own palette and vertical scroll, 104 words of a
	// 1024-word window; the rest of it reads zero and goes nowhere. sat and
	// sprdata are not here on purpose: the VDP refills them from VRAM, which is
	// restored, so carrying them would be work for nothing.
	//
	// ponytail: three clocks a word puts a save at about three milliseconds of
	// pause. the machine is off the bus the whole time, which is what the OSD pause
	// does anyway; pipeline the walk if that ever shows.
	localparam  [9:0] CHUNK_BASE = 10'd512;  // the top half of the buffer
	localparam  [9:0] CHUNK      = 10'd256;
	localparam  [2:0] N_MEM      = 3'd5;

	// derived from the buffer, never typed: this was a hand-written 200 and stayed
	// there when the chain grew past 12800 bits, at which point calibration
	// silently stored chain_len 0 and the core refused every snapshot. the buffer
	// holds two captures, so one capture can be at most half of it.
	localparam BUF_WORDS = 1024;
	localparam MAX_WORDS = BUF_WORDS/2;

	// what simulation measured. a hardware chain that comes back a different length
	// means synthesis built something other than what was tested, and restoring it
	// would shift every flop into its neighbour.

	// must infer as M10K. reading a single bit straight out of the array
	// (buf_mem[w][63-b]) does not: it forces the whole word out
	// combinationally and Quartus builds the buffer from flip-flops and
	// muxes instead. measured cost of getting this wrong: 122 percent of
	// the device. so read a whole word into a register, then shift that.
	reg [63:0] outsh = 0;
	reg  [8:0] rdaddr = 0;

	// every one of these gets a power-up value. the FPGA brings registers up as
	// zero, so without them the controller depends on a reset pulse arriving
	// before anything else happens, and simulation can never show the difference
	// because a testbench always resets first. zero here would mean ST_FLUSH.
	reg  [4:0] state = ST_FILL1;
	reg        calibrated = 0;
	reg [15:0] bitcnt = 0;
	reg  [8:0] widx = 0;
	reg  [5:0] bidx = 0;
	reg [63:0] shreg = 0;
	reg        out_pad = 0;   // the capture is past chain_len, filling the last word
	reg [23:0] guard = 0;
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

	// came back both set, which their own logic makes impossible, so neither could
	// be believed. these ask only whether the chain output moves at all.

	// save_ack comes back on the DDRAM clock
	reg  [1:0] ack_sync = 0;
	always @(posedge clk) ack_sync <= {ack_sync[0], xfer_ack};

	// The cartridge is the one walked memory that does not run on this clock: it
	// is on clk_sys, half of clk_md, both rising together out of the same PLL. A
	// strobe one clock wide at 107.37 MHz falls entirely between two 53.69 MHz
	// edges whenever it starts on an even clock, and which words start on an even
	// clock is fixed by the walk, so the same words of the cartridge vector were
	// dropped on every restore - all sixty-four times the walk writes them.
	// The address and the data already hold for the whole three clock phase; this
	// strobe holds with them, which no 53.69 MHz edge can step over.
	reg [1:0] wr_ext = 0;
	always @(posedge clk) begin
		if (mem_wr)       wr_ext <= 2'd2;
		else if (|wr_ext) wr_ext <= wr_ext - 1'd1;
	end
	assign mem_wr_hold = mem_wr | (|wr_ext);
	// A transfer is over when the request is down AND the acknowledge has come
	// back down with it. ss_ddr holds ack until the request drops, and ack then
	// takes two more clocks to cross back through this synchroniser. A state that
	// waited only for its own request to fall could raise the next one inside that
	// window, and the guard below would see the *previous* transfer's ack, drop
	// the new request in one clock and report it as done. ss_ddr never sees it.
	// That is what stopped the header from ever being written: the header request
	// follows the last memory chunk immediately, with nothing in between.
	wire xfer_idle = ~save_req & ~load_req & ~ack_sync[1];
	wire [63:0] nextword = {shreg[62:0], ss_out};
	// the last word is partial when the chain does not divide by 64: 14534 bits is
	// 227 full words plus 6. those bits sit at the low end of the shift register
	// while ST_IN feeds the chain from bit 63 downwards, so the tail has to reach
	// the top of the word. it used to get there through a 64 bit variable shift,
	// which is six stages of 64 multiplexers and was a third of this module's area.
	// shifting the capture on to the word boundary does the same job for nothing:
	// ST_OUT feeds zeros into the chain, so the padding bits are the zeros the
	// alignment would have inserted anyway, and ST_IN still stops at chain_len.


	// continuous assignments, not an always @* block: that block waits for an event
	// before it ever runs, so at time zero cur_last was x, "mchunk != cur_last" was
	// x, the branch was not taken and the walk left work RAM after one chunk of
	// thirty-two. Synthesis would have built the right logic and simulation would
	// have gone on failing, which is the worst of both.
	wire  [3:0] cur_sel  = (mem_idx == 3'd0) ? 4'd0      : (mem_idx == 3'd1) ? 4'd1     :
	                       (mem_idx == 3'd2) ? 4'd2      : (mem_idx == 3'd3) ? 4'd3     : 4'd4;
	wire [15:0] cur_off  = (mem_idx == 3'd0) ? 16'd1024  : (mem_idx == 3'd1) ? 16'd9216 :
	                       (mem_idx == 3'd2) ? 16'd11264 : (mem_idx == 3'd3) ? 16'd27648 : 16'd28672;
	wire  [5:0] cur_last = (mem_idx == 3'd0) ? 6'd31     : (mem_idx == 3'd1) ? 6'd7     :
	                       (mem_idx == 3'd2) ? 6'd63     : 6'd0;
	wire [15:0] nxt_off  = (mem_idx == 3'd0) ? 16'd9216  : (mem_idx == 3'd1) ? 16'd11264 :
	                       (mem_idx == 3'd2) ? 16'd27648 : 16'd28672;
	// mem_sel is registered with the address rather than derived from mem_idx: the
	// last write of a memory happens on the same clock that advances mem_idx, so a
	// combinational selector already pointed at the next memory and sent that word
	// to the wrong one. Two bytes per restore, at the end of work RAM and of the
	// Z80's.

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

	// calibration results are written straight to the DDR3 region this core
	// reserves, where Linux on the board can read them back with devmem. the OSD
	// carries one usable bit per boot and needs a person to read it; this carries
	// sixty four and needs nobody.


	// the buffer lives in ss_buf so the dump can read it on the DDRAM clock.
	// port A carries one address for both the fill and the replay, because they
	// never happen at once and two addresses on one port stop M10K inference.
	wire [63:0] rdword;
	// the second half starts at 256, not 200: the address is a concatenation, so
	// the chain lives in the bottom half. sizing the memory at 400 words put the
	// whole second capture past its end.
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
			payload_end <= 0;
		end
		else begin
			// one clock wide, always: leaving ST_MWRITE with it set left it high for
			// the whole of the next chunk fetch, and every clock of that wrote the
			// stale data at the stale address into the memory being restored.
			mem_wr <= 0;

			// a request that is never answered would hold busy high for good: no
			// further snapshots, and hold_off keeps the heartbeat dump off the memory
			// port, so the core goes quiet with no way to see why. give up after
			// about forty milliseconds and say so in the flags. the copy itself needs
			// tens of microseconds.
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
					// a chain longer than the buffer would be written past the end of
					// buf_mem and shifted back as undefined data, leaving the machine
					// running on garbage with no reset to recover it. treat it as a
					// failed measurement instead.
					chain_len  <= (bitcnt > MAX_WORDS*64) ? 16'd0 : bitcnt;
					// a marker that is already there on the first measuring clock is not a
					// short chain, it is a chain that never shifted: ss_out is showing the
					// functional IORQ, which sits high while the Z80 is held in reset.
					// both cases end up storing zero, which is why they read alike.
					hit_cnt    <= bitcnt;
					calibrated <= 1;
					widx       <= 0;
					guard      <= 0;
					state      <= ST_IDLE;
					ss_en_next = 0;
				end
				else if (bitcnt > 16'd60000) begin
					// marker never came back, so the chain is not usable on this build.
					// release the core anyway and simply refuse snapshots: a failed
					// measurement must never leave the machine held in reset, which is
					// a dead core with no picture and no OSD to escape with.
					ss_en_next = 0;
					chain_len  <= 0;
					calibrated <= 1;
					widx       <= 0;
					guard      <= 0;
					state      <= ST_IDLE;
				end
			end

			// four words of results into DDR3, then carry on as before. the guard
			// counter is here because a stuck memory controller must not leave the
			// machine frozen: a diagnostic that can hang the core is worse than none.

			ST_IDLE: begin
				ss_en_next = 0;
				pause_req <= 0;
				fsm_busy  <= 0;
				// once, a couple of seconds after calibration, run the round trip by
				// itself: capture, put it back, capture again into the other half of
				// the buffer. the machine stays frozen throughout, so the two halves
				// have to match bit for bit. anything that differs names a cell the
				// chain does not carry properly, read straight out of DDR3.
				// only count while the 68000 is actually writing work RAM. a fixed timer
				// from calibration expires while the core is still on a black screen with
				// no cartridge, and a snapshot of an idle machine proves nothing.
				// The automatic self test used to count here and fire a snapshot ten
				// seconds after the machine started doing something. It captured,
				// restored and captured again into the two halves of the buffer so
				// tools/diff_chain.sh could compare them, which is how the round trip
				// was first shown to be bit exact on real silicon. It has done that,
				// and what is left of it on a player's machine is a stall and an
				// audible click a few seconds into every game.

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
					// the chain, from the top of the slot into the bottom of the buffer.
					// These were the descriptor of whatever ran last: after a save that is
					// the final memory chunk, offset 28672 length 256 into buffer word 512.
					// The fetch then read the cartridge region into the top half and the
					// chain was shifted in from buffer words 0..259, which nobody had
					// written this time round - they still held the chain the last SAVE
					// read out. Restoring the slot you had just saved therefore worked, by
					// accident, and restoring any other slot put that slot's memories under
					// the other slot's registers: structured video garbage and a hung 68000.
					// A restore had never once read a chain out of DDR3.
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
					// only the automatic test compares two captures, and it always does.
					// a manual save must not: the memory walk that follows it writes the
					// top half of the buffer, which is exactly where the second capture
					// would sit, so the comparison would be against memory data. the
					// automatic test does no memory walk and keeps both halves intact.
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

			// read the chain out, packing 64 bits per word. the machine is left
			// holding zeros at this point and is only sane again after ST_IN.
			// let the processors reach a boundary and drop the bus. the acknowledge
			// comes from the Z80 side; the 68000 has none exposed, so a settling
			// count covers it. a millisecond is nothing against a 232 microsecond
			// snapshot and it is the difference between a clean freeze and a crash.
			// the slot is on its way into the buffer. the guard above drops load_req
			// on the answer or on the timeout, so this only has to look at which.
			ST_HDRCHK: begin
				if (xfer_idle) begin
					blk_hdr <= 0;
					if (xfer_ok && hdr_present) begin
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

			ST_PAUSE: begin
				guard <= guard + 1'b1;
				if (bus_free && guard[16]) begin
					guard  <= 0;
					bitcnt <= 0;
					widx   <= 0;
					bidx   <= 0;
					rdaddr <= 0;
					// a restore puts the memories back first, with the machine paused but
					// the chain untouched, and only then freezes and shifts the registers
					// in. the other way round the processors would run for the length of
					// the memory walk with registers that no longer match anything.
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
					// giving up has to be final for the self test, otherwise it retries
					// every couple of seconds and each attempt holds the bus request long
					// enough to click the audio and stall the game.
					pause_req     <= 0;
					fsm_busy      <= 0;
					state         <= ST_IDLE;
				end
			end

			ST_OUT: begin
				ss_in  <= 0;
				shreg  <= nextword;
				bidx   <= bidx + 1'b1;
				bitcnt <= bitcnt + 1'b1;

				// exactly one write statement for buf_mem in the whole design. two
				// conditional writes, even to the same address, stop Quartus inferring
				// M10K: it reported "can't infer memory for variable buf_mem" and put
				// 12800 bits into logic, taking the design to 117 percent of the device.
				// value comes from bufword, the address from addra: one write statement,
				// one read address, which is the shape Quartus needs for block RAM.

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
				// Let go of the memories here, before the chain goes in and not with
				// the last word of the walk. The cartridge applies its bank registers
				// when its select line drops, and that line is (busy && sel == 4):
				// left at 4 it stayed up through the whole chain shift, and the banks
				// landed after the machine had already resumed - a game with no
				// banking never noticed, Super Street Fighter II fetched a few
				// instructions from the wrong half of a five megabyte ROM and died.
				//
				// Not one state earlier: that clock still carries mem_wr for the last
				// word of the walk, and a select that changes with it sends that word
				// to the wrong memory. Signals that qualify a transfer travel with it.
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
				// a real save keeps the machine paused and walks its memories out after
				// the chain. the self test has nowhere to put them and stops here.
				if (saving) begin
					blk_off  <= 0;
					blk_len  <= 0;      // the chain, the chain, whose length the core measured
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

			// one chunk of a memory into the top half of the buffer. three clocks a
			// word: set the address, let the block RAM answer, take the answer.
			// ponytail: 8192 words at three clocks is under a millisecond of pause,
			// pipeline it if that ever shows on screen.
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
						blk_hdr  <= 1;
						save_req <= 1;
						state    <= ST_HDR;
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
									// processors resume with registers that match them.
									//
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
			if (state != ST_IDLE && calibrated) begin
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
		ss_en        <= ss_en_next;
		ss_en_cpu    <= ss_en_next;
		ss_en_vdp_fm <= ss_en_next;
		ss_en_vram   <= ss_en_next;
	end

endmodule
