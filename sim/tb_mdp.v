`timescale 1ns/1ps
module tb_mdp;
	reg clk = 0; always #9.314 clk = ~clk;
	reg reset = 1, active = 0, track_start = 0, stop_request = 0;
	reg osd_pause = 0, resume_request = 0, ddr_hold = 0;
	reg [15:0] buf_wr_ptr = 16'hF000;
	wire [28:0] a; wire [7:0] bc; wire rd, we; wire [63:0] din; wire [7:0] be;
	wire ddr_idle, ddrclk;
	reg  busy = 0, dready = 0; reg [63:0] dout = 64'hDEAD0000BEEF0000;
	wire signed [15:0] al, ar;

	mdp_audio dut (
		.clk(clk), .reset(reset),
		.DDRAM_CLK(ddrclk), .DDRAM_BUSY(busy), .DDRAM_BURSTCNT(bc), .DDRAM_ADDR(a),
		.DDRAM_DOUT(dout), .DDRAM_DOUT_READY(dready), .DDRAM_RD(rd),
		.DDRAM_DIN(din), .DDRAM_BE(be), .DDRAM_WE(we),
		.active(active), .buf_wr_ptr(buf_wr_ptr), .buf_rd_ptr(),
		.ddr_hold(ddr_hold), .ddr_idle(ddr_idle),
		.track_start(track_start), .stop_request(stop_request), .fade_sectors(8'd0),
		.volume(8'd255), .resume_request(resume_request), .osd_pause(osd_pause),
		.audio_l(al), .audio_r(ar)
	);

	// DDR model: a read is taken only when RD is high on a clock with BUSY low.
	integer inflight = 0, taken = 0, lost = 0, lat;
	always @(posedge clk) begin
		dready <= 0;
		if (rd && !busy) begin taken = taken + 1; inflight = 12; end
		else if (rd && busy) lost = lost + 1;
		if (inflight > 0) begin
			inflight = inflight - 1;
			if (inflight == 0) begin dready <= 1; dout <= dout + 64'h1; end
		end
	end

	integer errs = 0;
	task chk(input ok, input [1023:0] what);
		begin if (!ok) begin $display("FAIL: %0s", what); errs = errs + 1; end end
	endtask

	// wait for the FSM to reach DDR_WAIT with a read accepted
	task to_wait; integer g; begin
		g = 0; while (dut.ddr_state !== 3'd2 && g < 20000) begin @(posedge clk); g = g + 1; end
	end endtask

	integer g, taken0;
	initial begin
		repeat (10) @(posedge clk);
		reset = 0; active = 1;
		// clear the 50 ms track mute that never ran: mute_ctr starts at 0 here
		repeat (20) @(posedge clk);

		// --- A: a plain read ------------------------------------------------
		to_wait;
		chk(dut.ddr_state === 3'd2, "never reached DDR_WAIT");
		$display("A in DDR_WAIT : rd_inflight=%0b ddr_idle=%0b taken=%0d", dut.rd_inflight, ddr_idle, taken);
		chk(dut.rd_inflight === 1'b1, "rd_inflight not set on an accepted read");
		chk(ddr_idle === 1'b0, "ddr_idle high with a read in flight");
		g = 0; while (!dready && g < 100) begin @(posedge clk); g = g + 1; end
		@(posedge clk); @(posedge clk); @(posedge clk);
		$display("A after data  : rd_inflight=%0b ddr_state=%0d", dut.rd_inflight, dut.ddr_state);
		chk(dut.rd_inflight === 1'b0, "rd_inflight not cleared by DDRAM_DOUT_READY");

		// --- B: track_start while a read is in flight ------------------------
		to_wait;
		@(negedge clk) track_start = 1; @(negedge clk) track_start = 0;
		@(posedge clk);
		$display("B after track_start: ddr_state=%0d rd_inflight=%0b ddr_idle=%0b",
		         dut.ddr_state, dut.rd_inflight, ddr_idle);
		chk(dut.ddr_state === 3'd0, "track_start did not drop the FSM to idle");
		chk(dut.rd_inflight === 1'b1, "track_start cleared rd_inflight");
		chk(ddr_idle === 1'b0, "ddr_idle lies while the track-changed read is still in flight");
		g = 0; while (!dready && g < 100) begin @(posedge clk); g = g + 1; end
		@(posedge clk); @(posedge clk);
		$display("B after the stale word: rd_inflight=%0b ddr_idle=%0b", dut.rd_inflight, ddr_idle);
		chk(ddr_idle === 1'b1, "ddr_idle never recovered after the stale word");

		// --- C: reset while a read is in flight ------------------------------
		track_start = 1; @(negedge clk); track_start = 0;   // clear the mute counter path
		dut.mute_ctr = 0;
		to_wait;
		// set ddr_hold now, well before D needs it: set right at the IDLE->REQ
		// boundary it races the FSM's own same-edge decision and loses
		ddr_hold = 1;
		@(negedge clk) reset = 1;
		@(posedge clk);
		$display("C after reset : ddr_state=%0d rd_inflight=%0b ddr_idle=%0b  (word still in flight=%0d)",
		         dut.ddr_state, dut.rd_inflight, ddr_idle, inflight);
		chk(dut.rd_inflight === 1'b1, "reset cleared rd_inflight with a word still in flight");
		chk(ddr_idle === 1'b0, "ddr_idle high right after a reset with a word still in flight");
		// hold reset across the full DDR latency (12 clk here), as the ~98k-clk
		// sys_reset does on real hardware: the word must land while reset is high
		repeat (60) @(posedge clk);
		$display("C word landed during reset: rd_inflight=%0b ddr_idle=%0b inflight=%0d",
		         dut.rd_inflight, ddr_idle, inflight);
		chk(dut.rd_inflight === 1'b0, "rd_inflight not cleared by a word landing during reset");
		@(negedge clk) reset = 0;
		@(posedge clk); @(posedge clk);
		$display("C after the stale word: rd_inflight=%0b ddr_idle=%0b", dut.rd_inflight, ddr_idle);
		chk(dut.rd_inflight === 1'b0, "rd_inflight not cleared by the stale word after a reset");
		chk(ddr_idle === 1'b1, "ddr_idle never recovered after reset with a word landing mid-reset");

		// --- D: a foreign DOUT_READY while mdp is held off -------------------
		dut.mute_ctr = 0;
		g = 0; while (dut.ddr_state !== 3'd0 && g < 20000) begin @(posedge clk); g = g + 1; end
		repeat (5) @(posedge clk);
		$display("D held off    : ddr_state=%0d rd_inflight=%0b ddr_idle=%0b", dut.ddr_state, dut.rd_inflight, ddr_idle);
		chk(ddr_idle === 1'b1, "ddr_idle low while mdp is held off and idle");
		begin : foreign
			integer w0, w1;
			w0 = dut.fifo_wr;
			@(negedge clk) dready = 1; @(negedge clk) dready = 0;
			repeat (4) @(posedge clk);
			w1 = dut.fifo_wr;
			$display("D foreign word: fifo_wr %0d -> %0d  rd_inflight=%0b ddr_state=%0d", w0, w1, dut.rd_inflight, dut.ddr_state);
			chk(w0 === w1, "a foreign DDRAM_DOUT_READY was taken into the CDDA fifo");
		end
		ddr_hold = 0;

		// --- E: the RD pulse lands on a busy clock ---------------------------
		dut.mute_ctr = 0;
		g = 0; while (dut.ddr_state !== 3'd1 && g < 20000) begin @(posedge clk); g = g + 1; end
		taken0 = taken;
		// DDR_REQ samples !busy this clock and drives RD on the next one
		@(negedge clk) busy = 1;          // busy rises exactly over the RD pulse
		repeat (3) @(posedge clk);
		@(negedge clk) busy = 0;
		// with playback running the FSM starts another read the moment this one
		// lands, so watch taken rather than a transient idle snapshot: a dropped
		// read never gets retried and taken stops moving for good
		g = 0; while (taken == taken0 && g < 20000) begin @(posedge clk); g = g + 1; end
		$display("E dropped RD  : taken=%0d (was %0d) lost=%0d ddr_state=%0d rd_inflight=%0b ddr_idle=%0b wait=%0d",
		         taken, taken0, lost, dut.ddr_state, dut.rd_inflight, ddr_idle, g);
		if (taken === taken0)
			$display("E RESULT: a dropped RD wedges rd_inflight, ddr_idle stays 0 for good");
		chk(taken != taken0, "an RD pulse that crossed a busy clock was never retried");

		$display("tb_mdp %0s (%0d)", errs ? "FAIL" : "PASS", errs);
		$finish;
	end
endmodule
