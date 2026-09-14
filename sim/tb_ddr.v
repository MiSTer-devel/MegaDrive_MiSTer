`timescale 1ns/1ps

// checks that every word is written, in order, once, with the right contents,
// and that the memory controller's busy line is respected

// one DDR port, two masters' requests in FIFO order, one shared ddr_dout_ready:
// a read in flight when the mux switches answers to the wrong master
module ddr_arb(
	input         clk,
	input         gate,      // 1 = master A's request lines reach the port
	input         a_rd, input [28:0] a_addr,
	input         b_rd, input [28:0] b_addr,
	output        dout_ready,
	output [63:0] dout
);
	localparam DEPTH   = 4;
	localparam LATENCY = 10;
	reg [28:0] q_addr [0:DEPTH-1];
	integer    head = 0, tail = 0, count = 0, wait_left = LATENCY;
	reg        dr = 0;
	reg [63:0] dw = 0;
	assign dout_ready = dr;
	assign dout        = dw;

	wire        rd_now   = gate ? a_rd   : b_rd;
	wire [28:0] addr_now = gate ? a_addr : b_addr;

	always @(posedge clk) begin
		dr <= 0;
		if (rd_now && count < DEPTH) begin
			q_addr[tail] <= addr_now;
			tail  <= (tail + 1) % DEPTH;
			count <= count + 1;
		end
		if (count > 0) begin
			if (wait_left > 0) wait_left <= wait_left - 1;
			else begin
				dw        <= {32'hD0000000, 3'd0, q_addr[head]};
				dr        <= 1;
				head      <= (head + 1) % DEPTH;
				count     <= count - 1;
				wait_left <= LATENCY;
			end
		end
		else wait_left <= LATENCY;
	end
endmodule

// GATED=0 ties port_ok high (the race), GATED=1 takes the second master's idle line;
// TRACK_FIX=0 drops the in-flight read on a track change, 1 keeps it until the answer
module race_rig #(parameter GATED = 0, parameter TRACK_FIX = 1, parameter [9:0] NW = 10'd8)
(
	input             clk,
	input             trigger_b,     // the second master's read goes in flight
	input             trigger_track, // a track change lands mid-read
	input             trigger_load,  // req_load pulses
	output reg [28:0] loaded_first  = 0,
	output reg        loaded_ok     = 0,
	output reg        started_early = 0,
	output            ack
);
	localparam [28:0] B_ADDR   = 29'h6000010;
	localparam [28:0] PAYLOAD0 = 29'h7C00000 + 29'd32768 + 29'd1;

	reg  b_rd = 0, b_pend = 0;
	wire b_idle = !b_pend && !b_rd;

	wire        busy, we, rd;
	wire [28:0] addr;
	wire [63:0] din;
	wire  [9:0] buf_addr;
	reg  [63:0] bufmem = 0;
	always @(posedge clk) bufmem <= {32'hB0000000, 22'd0, buf_addr};

	wire dr; wire [63:0] dw;
	ddr_arb arb(.clk(clk), .gate(busy),
		.a_rd(rd), .a_addr(addr), .b_rd(b_rd), .b_addr(B_ADDR),
		.dout_ready(dr), .dout(dw));

	wire       port_ok = GATED ? b_idle : 1'b1;
	wire       bw; wire [63:0] bd;
	reg        req_load = 0;

	ss_ddr #(.DDR_BASE(29'h7C00000)) dut
	(
		.clk(clk), .chain_len(16'd0),
		.busy(busy), .ddr_busy(1'b0),
		.ddr_addr(addr), .ddr_din(din), .ddr_we(we), .ddr_burstcnt(), .ddr_be(),
		.buf_addr(buf_addr), .buf_q(bufmem), .buf_we(bw), .buf_din(bd),
		.req_save(1'b0), .req_load(req_load), .slot(2'd0), .ack(ack),
		.blk_off(16'd0), .blk_len(NW), .blk_base(10'd0),
		.blk_hdr(1'b0), .blk_id(1'b0), .save_sd(1'b1), .hdr_words32(32'd0),
		.hdr_present(), .hdr_chain(),
		.ddr_rd(rd), .ddr_dout(dw), .ddr_dout_ready(dr),
		.port_ok(port_ok)
	);

	reg [63:0] loaded [0:NW-1];
	reg        old_busy = 0;
	reg        ack_d = 0;
	integer    i;

	always @(posedge clk) begin
		b_rd <= 0;
		if (trigger_b) begin b_rd <= 1; b_pend <= 1; end
		if (dr && dw[28:0] == B_ADDR) b_pend <= 0;
		if (trigger_track && !TRACK_FIX) b_pend <= 0;

		if (trigger_load) req_load <= 1;
		if (ack)           req_load <= 0;

		old_busy <= busy;
		if (~old_busy & busy & ~b_idle) started_early <= 1;

		if (bw) begin
			loaded[buf_addr] <= bd;
			if (buf_addr == 0) loaded_first <= bd[28:0];
		end

		ack_d <= ack;
		if (ack_d) begin
			loaded_ok = 1;
			for (i = 0; i < NW; i = i + 1)
				if (loaded[i][28:0] !== (PAYLOAD0 + i[28:0])) loaded_ok = 0;
		end
	end
endmodule

module tb_ddr;

	reg clk = 0;
	always #5 clk = ~clk;

	reg ddr_busy = 0;
	reg req_save = 0, req_load = 0;
	wire ack;
	wire        rd;
	wire        bw;
	wire [63:0] bd;
	reg  [63:0] dout = 0;
	reg         dout_ready = 0;
	wire        we;
	wire [28:0] addr;
	wire [63:0] din;
	wire  [9:0] buf_addr;
	wire        busy;

	// the buffer answers with its own address so a misread shows up as a value
	reg [63:0] bufmem = 0;
	always @(posedge clk) bufmem <= {32'hB0000000, 22'd0, buf_addr};

	reg [15:0] t_off = 0; reg [9:0] t_len = 0, t_base = 0; reg t_hdr = 0, t_id = 0;
	reg save_sd_r = 1;
	wire [7:0] ddr_be_w;
	wire hdr_present_w; wire [15:0] hdr_chain_w;

	ss_ddr #(.DDR_BASE(29'h7C00000)) dut
	(
		.clk(clk),
		.chain_len(16'd16582),
		.busy(busy), .ddr_busy(ddr_busy),
		.ddr_addr(addr), .ddr_din(din), .ddr_we(we), .ddr_burstcnt(), .ddr_be(ddr_be_w),
		.buf_addr(buf_addr), .buf_q(bufmem), .buf_we(bw), .buf_din(bd),
		.req_save(req_save), .req_load(req_load), .slot(2'd0), .ack(ack),
		.blk_off(t_off), .blk_len(t_len), .blk_base(t_base),
		.blk_hdr(t_hdr), .blk_id(t_id), .save_sd(save_sd_r), .hdr_words32(32'd57856),
		.hdr_present(hdr_present_w), .hdr_chain(hdr_chain_w),
		.ddr_rd(rd), .ddr_dout(dout), .ddr_dout_ready(dout_ready),
		.port_ok(1'b1)
	);



	// hold the controller busy in bursts, which is what loses badly written writes
	always begin
		#3000 ddr_busy = 1;
		#700  ddr_busy = 0;
	end

	// slot 0 starts 1024 words past the mirror; the payload starts one word past
	// that, since word 0 is the header main polls and the core does not own it
	localparam [28:0] SLOT0 = 29'h7C00000 + 29'd32768 + 29'd2;
	localparam        NW    = (16582 + 63) / 64;
	integer s_seen = 0, s_bad_addr = 0, s_bad_data = 0;
	reg [28:0] s_expect = SLOT0;
	reg saving = 0;
	always @(posedge clk) if (saving && we && !ddr_busy) begin
		if (addr !== s_expect) s_bad_addr = s_bad_addr + 1;
		if (din[63:32] !== 32'hB0000000 || din[9:0] !== s_seen) s_bad_data = s_bad_data + 1;
		s_seen   = s_seen + 1;
		s_expect = s_expect + 1'b1;
	end

	// a memory model for the read side: answers an accepted read a few clocks
	// later with a word derived from the address, so a misaddressed write shows up
	// as a wrong value rather than as nothing at all.
	reg [28:0] pend_addr = 0;
	integer    pend = 0;
	reg [63:0] hdr_mem = 0; reg [63:0] id_mem = 0;
	localparam [28:0] HDRADDR = 29'h7C00000 + 29'd32768;
	localparam [28:0] IDADDR  = HDRADDR + 29'd1;
	always @(posedge clk) begin
		dout_ready <= 0;
		if (rd && !ddr_busy) begin pend_addr <= addr; pend <= 4; end
		else if (pend > 1) pend <= pend - 1;
		else if (pend == 1) begin
			pend <= 0;
			if (pend_addr == HDRADDR) dout <= hdr_mem;
			else if (pend_addr == IDADDR) dout <= id_mem;
			else dout <= {32'hD0000000, 3'd0, pend_addr};
			dout_ready <= 1;
		end
	end

	// what the load path actually wrote into the buffer, and where
	reg [63:0] loaded [0:511];
	reg [31:0] l_seen = 0;
	integer l_bad = 0;
	// the sum has to be built at 29 bits before it goes into the concatenation:
	// SLOT0 + an integer is self-determined at 32 and the literal then overflows
	// the word, which reads as every single value being wrong.
	reg [28:0] exp_addr;
	always @(posedge clk) if (bw) begin
		loaded[buf_addr] = bd;
		exp_addr = SLOT0 + l_seen[28:0];
		if (bd !== {32'hD0000000, 3'd0, exp_addr}) l_bad = l_bad + 1;
		if (buf_addr !== l_seen[9:0]) l_bad = l_bad + 1;
		l_seen = l_seen + 1;
	end

	integer ack_held = 0;
	reg [7:0] be_on = 0, be_off = 0;

	// a second master with a read in flight when the load request arrives.
	// race_rig(GATED=0) reproduces the bug (port_ok tied high, no hand-over);
	// race_rig(GATED=1) is the fix (port_ok from the second master's idle line).
	reg trig_b = 0, trig_load = 0, trig_track = 0;
	wire [28:0] bug_first, fix_first;
	wire        bug_ok, fix_ok, bug_early, fix_early, bug_ack, fix_ack;

	race_rig #(.GATED(0)) rig_bug (.clk(clk), .trigger_b(trig_b), .trigger_track(1'b0), .trigger_load(trig_load),
		.loaded_first(bug_first), .loaded_ok(bug_ok), .started_early(bug_early), .ack(bug_ack));
	race_rig #(.GATED(1)) rig_fix (.clk(clk), .trigger_b(trig_b), .trigger_track(1'b0), .trigger_load(trig_load),
		.loaded_first(fix_first), .loaded_ok(fix_ok), .started_early(fix_early), .ack(fix_ack));

	// the same race, but with a CDDA track change landing while master B's read
	// is still in flight: TRACK_FIX=0 is mdp_audio's old ddr_idle, TRACK_FIX=1
	// is rd_inflight, port_ok gated on both.
	wire [28:0] tbug_first, tfix_first;
	wire        tbug_ok, tfix_ok, tbug_early, tfix_early, tbug_ack, tfix_ack;

	race_rig #(.GATED(1), .TRACK_FIX(0)) rig_tbug (.clk(clk), .trigger_b(trig_b), .trigger_track(trig_track), .trigger_load(trig_load),
		.loaded_first(tbug_first), .loaded_ok(tbug_ok), .started_early(tbug_early), .ack(tbug_ack));
	race_rig #(.GATED(1), .TRACK_FIX(1)) rig_tfix (.clk(clk), .trigger_b(trig_b), .trigger_track(trig_track), .trigger_load(trig_load),
		.loaded_first(tfix_first), .loaded_ok(tfix_ok), .started_early(tfix_early), .ack(tfix_ack));

	// the four rigs finish at different speeds, so latch each ack rather than
	// wait on the wire directly: a plain wait() can miss a pulse that already
	// came and went while this process was still waiting on an earlier one.
	reg seen_bug = 0, seen_fix = 0, seen_tbug = 0, seen_tfix = 0;
	always @(posedge clk) begin
		if (bug_ack)  seen_bug  <= 1;
		if (fix_ack)  seen_fix  <= 1;
		if (tbug_ack) seen_tbug <= 1;
		if (tfix_ack) seen_tfix <= 1;
	end

	initial begin

		// the chain lives at payload offset 1 now, offset 0 belongs to blk_id
		t_off = 16'd1;
		@(posedge clk); saving = 1; req_save = 1;
		wait (ack);
		// the ack has to stay up while the request does, or the controller in the
		// other clock domain can miss a pulse two of its clocks wide
		repeat (20) @(posedge clk) if (ack) ack_held = ack_held + 1;
		saving = 0;
		req_save = 0;
		repeat (10) @(posedge clk);
		$display("slot words     : %0d (expect %0d)", s_seen, NW);
		$display("wrong address  : %0d", s_bad_addr);
		$display("wrong data     : %0d", s_bad_data);
		$display("ack held for   : %0d of 20 clocks", ack_held);
		$display("ack after req  : %0b (expect 0)", ack);
		if (s_seen != NW || s_bad_addr != 0 || s_bad_data != 0 || ack_held != 20 || ack) begin
			$display("RESULT: FAIL - the slot copy is wrong");
			$finish;
		end
		$display("RESULT: PASS - the capture reaches its slot intact");

		@(posedge clk); req_load = 1;
		wait (ack);
		repeat (5) @(posedge clk);
		req_load = 0;
		repeat (10) @(posedge clk);
		$display("loaded words   : %0d (expect %0d)", l_seen, NW);
		$display("wrong word or address: %0d", l_bad);
		if (l_seen == NW && l_bad == 0)
			$display("RESULT: PASS - the slot comes back into the buffer in order");
		else
			$display("RESULT: FAIL - the restore path is wrong");

		// main writes 0xFFFFFFFF into word 0 after loading a file from SD. The
		// chain identity now lives in its own word, so the restore must still
		// be accepted.
		hdr_mem = {32'd57856, 32'hFFFFFFFF};
		id_mem  = {32'h4D445353, 16'd0, 16'd16582};
		t_hdr = 1;
		@(posedge clk); req_load = 1;
		wait (ack);
		repeat (2) @(posedge clk); req_load = 0; t_hdr = 0;
		repeat (10) @(posedge clk);
		$display("hdr_present after FFFFFFFF word0 : %0b (expect 1)", hdr_present_w);
		t_off = 16'd0;   // the identity word lives at payload offset 0
		t_id = 1;
		@(posedge clk); req_load = 1;
		wait (ack);
		repeat (2) @(posedge clk); req_load = 0; t_id = 0;
		repeat (10) @(posedge clk);
		$display("hdr_chain from id word           : %0d (expect 16582)", hdr_chain_w);
		if (!hdr_present_w || hdr_chain_w !== 16'd16582) begin
			$display("RESULT: FAIL - a file loaded from SD is refused");
			$finish;
		end
		$display("RESULT: PASS - a file loaded from SD is still accepted");

		// ddr_be corollary: with save_sd off, word 0 (main's change detector)
		// must stay untouched, so the header write masks those 4 bytes.
		save_sd_r = 1;
		t_hdr = 1;
		@(posedge clk); req_save = 1;
		wait (we);
		be_on = ddr_be_w;
		wait (ack);
		repeat (2) @(posedge clk); req_save = 0; t_hdr = 0;
		repeat (10) @(posedge clk);

		save_sd_r = 0;
		t_hdr = 1;
		@(posedge clk); req_save = 1;
		wait (we);
		be_off = ddr_be_w;
		wait (ack);
		repeat (2) @(posedge clk); req_save = 0; t_hdr = 0;
		repeat (10) @(posedge clk);

		$display("ddr_be save_sd=1 : %h (expect ff)", be_on);
		$display("ddr_be save_sd=0 : %h (expect f0)", be_off);
		if (be_on !== 8'hFF || be_off !== 8'hF0) begin
			$display("RESULT: FAIL - word 0 is not masked off when save_sd is off");
			$finish;
		end
		$display("RESULT: PASS - word 0 stays untouched when save_sd is off");

		// a second master's read in flight at the load request, a track change inside it;
		// the four rigs run at different speeds, so each ack is latched, not waited on
		@(negedge clk); trig_b = 1;
		@(negedge clk); trig_b = 0; trig_track = 1;
		@(negedge clk); trig_track = 0; trig_load = 1;
		@(negedge clk); trig_load = 0;

		wait (seen_bug && seen_fix && seen_tbug && seen_tfix);
		repeat (4) @(posedge clk);

		$display("bug first word addr : %h (a real answer starts %h)", bug_first, 29'h7c08001);
		$display("fix first word addr : %h", fix_first);
		$display("bug loaded in order : %0b (expect 0)", bug_ok);
		$display("fix loaded in order : %0b (expect 1)", fix_ok);
		$display("bug started early   : %0b (expect 1, the race precondition)", bug_early);
		$display("fix started early   : %0b (expect 0)", fix_early);
		// b_idle for TRACK_FIX=0 clears at the track-change trigger itself, well
		// before req_load even lands, so started_early never fires here the way
		// it does for the plain race above; loaded_ok is what shows the race.
		$display("track-change, old ddr_idle : loaded ok=%0b (expect 0)", tbug_ok);
		$display("track-change, rd_inflight  : loaded ok=%0b (expect 1)", tfix_ok);

		if (!bug_early || bug_ok || bug_first === 29'h7c08001) begin
			$display("RESULT: FAIL - the race did not reproduce a misplaced word");
			$finish;
		end

		if (fix_early || !fix_ok || fix_first !== 29'h7c08001) begin
			$display("RESULT: FAIL - the port hand-over still races the second master");
			$finish;
		end

		if (tbug_ok) begin
			$display("RESULT: FAIL - a track change mid-read did not reproduce the old ddr_idle race");
			$finish;
		end

		if (tfix_early || !tfix_ok) begin
			$display("RESULT: FAIL - a track change mid-read still hands the port over early");
			$finish;
		end
		$display("RESULT: PASS - the port hand-over waits for the second master's read, track change included");
		$finish;
	end

endmodule
