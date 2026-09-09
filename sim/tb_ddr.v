`timescale 1ns/1ps

// The dump had no test, and that cost a full build: a settle cycle fell through
// to the accept branch and advanced the word counter without writing anything,
// so 405 words produced zero memory writes. This checks the only things that
// matter: every word is written, in order, once, with the right contents, and
// the memory controller's busy line is respected.

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

	ss_ddr #(.DDR_BASE(29'h7C00000)) dut
	(
		.clk(clk),
		.chain_len(16'd16582),
		.busy(busy), .ddr_busy(ddr_busy),
		.ddr_addr(addr), .ddr_din(din), .ddr_we(we), .ddr_burstcnt(),
		.buf_addr(buf_addr), .buf_q(bufmem), .buf_we(bw), .buf_din(bd),
		.req_save(req_save), .req_load(req_load), .slot(2'd0), .ack(ack),
		.blk_off(16'd0), .blk_len(10'd0), .blk_base(10'd0),
		.blk_hdr(1'b0), .save_sd(1'b1), .hdr_words32(32'd57856), .hdr_present(), .hdr_chain(),
		.ddr_rd(rd), .ddr_dout(dout), .ddr_dout_ready(dout_ready)
	);



	// hold the controller busy in bursts, which is what loses badly written writes
	always begin
		#3000 ddr_busy = 1;
		#700  ddr_busy = 0;
	end

	// second phase: the snapshot copy to a slot. slot 0 starts 1024 words past the
	// mirror, the length comes from chain_len, and the data is the buffer verbatim
	// with no status words in front of it.
	// the payload starts one word past the slot base: word 0 is the header main
	// polls, and the core does not own it
	localparam [28:0] SLOT0 = 29'h7C00000 + 29'd32768 + 29'd1;
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
	always @(posedge clk) begin
		dout_ready <= 0;
		if (rd && !ddr_busy) begin pend_addr <= addr; pend <= 4; end
		else if (pend > 1) pend <= pend - 1;
		else if (pend == 1) begin
			pend       <= 0;
			dout       <= {32'hD0000000, 3'd0, pend_addr};
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

	initial begin

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
		$finish;
	end

endmodule
