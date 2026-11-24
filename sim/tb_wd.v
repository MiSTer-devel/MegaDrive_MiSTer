`timescale 1ns/1ps
module wd_rig #(parameter GB = 21) (input clk);
	reg reset = 1, ss_save = 0, ss_load = 0, hold = 0, pblock = 0;
	reg arm_id = 0, arm_hdr = 0, arm_idf = 0, arm_tid = 0, arm_thdr = 0, thold = 0;
	wire busy, cal_busy, cal_failed, pause_req, ss_en, ss_in, save_req, load_req, xfer_ack;
	wire [15:0] chain_len, blk_off, hdr_chain, mem_addr, mem_din;
	wire [9:0] blk_len, blk_base, buf_addr;
	wire blk_hdr, blk_id, hdr_present, mem_wr, mem_wr_hold, buf_we, ssd_busy, ddr_we;
	wire [31:0] hdr_words32;
	wire [3:0] mem_sel;
	wire [63:0] buf_q, buf_din, ddr_din;
	wire [28:0] ddr_addr;
	wire [7:0] ddr_burstcnt, ddr_be;
	wire dbusy = hold | thold;
	// .* below connects this where the controller has the port, so the file
	// also builds against one without it
	wire xfer_busy = ssd_busy;

	reg [199:0] sr = 0;
	always @(posedge clk) if (ss_en) sr <= {sr[198:0], ss_in};

	savestate #(.GUARD_BITS(GB)) ctrl (.clk(clk), .reset(reset), .ss_save(ss_save), .ss_load(ss_load), .busy(busy),
		.cal_busy(cal_busy), .cal_failed(cal_failed), .chain_len(chain_len), .pause_req(pause_req), .bus_free(1'b1),
		.bufb_clk(clk), .bufb_addr(buf_addr), .bufb_q(buf_q), .ss_en(ss_en), .ss_en_cpu(), .ss_en_vdp_fm(), .ss_en_vram(),
		.ss_in(ss_in), .ss_out(sr[199]), .save_req(save_req), .load_req(load_req), .xfer_ack(xfer_ack),
		.blk_hdr(blk_hdr), .blk_id(blk_id), .hdr_words32(hdr_words32), .hdr_present(hdr_present), .hdr_chain(hdr_chain),
		.blk_off(blk_off), .blk_len(blk_len), .blk_base(blk_base),
		.mem_addr(mem_addr), .mem_sel(mem_sel), .mem_din(mem_din), .mem_wr(mem_wr), .mem_wr_hold(mem_wr_hold),
		.mem_dout(16'h0), .bufb_we(buf_we), .bufb_din(buf_din), .load_walk(), .*);
	ss_ddr ssd (.clk(clk), .chain_len(chain_len), .busy(ssd_busy), .ddr_busy(dbusy), .ddr_addr(ddr_addr), .ddr_din(ddr_din),
		.ddr_we(ddr_we), .ddr_burstcnt(ddr_burstcnt), .ddr_be(ddr_be), .buf_addr(buf_addr), .buf_q(buf_q),
		.buf_we(buf_we), .buf_din(buf_din), .req_save(save_req), .req_load(load_req), .slot(2'd0),
		.blk_off(blk_off), .blk_len(blk_len), .blk_base(blk_base), .blk_hdr(blk_hdr), .blk_id(blk_id),
		.save_sd(1'b1), .hdr_words32(hdr_words32), .hdr_present(hdr_present), .hdr_chain(hdr_chain), .ack(xfer_ack),
		.ddr_rd(), .ddr_dout(64'h0), .ddr_dout_ready(1'b0), .port_ok(~pblock));

	localparam [31:0] MAGIC = 32'h4D445353;
	wire [28:0] off = ddr_addr - ssd.slot_base;
	integer nw = 0, n0 = 0, n1 = 0, npay = 0, nidx = 0, first_off = -1;
	reg first_id = 0;
	always @(posedge clk) if (ddr_we && !dbusy) begin
		if (nw == 0) begin first_off = off; first_id = (ddr_din[63:32] == MAGIC); end
		nw = nw + 1;
		if (off == 0) n0 = n0 + 1;
		else if (off == 1) n1 = n1 + 1;
		else npay = npay + 1;
		if (off != 1 && ddr_din[63:32] == MAGIC) nidx = nidx + 1;
	end

	reg wd_fired = 0, wd_blk_id = 0, wd_blk_hdr = 0;
	reg [4:0] wd_state = 0;
	reg save_req_d = 0;
	integer fall_n = -1;
	always @(posedge clk) begin
		save_req_d <= save_req;
		if ((arm_id && ctrl.state == 5'd20) || (arm_hdr && ctrl.state == 5'd17)) begin
			hold <= 1;
			wd_state <= ctrl.state;
		end
		if (hold && !ctrl.calibrated) begin
			hold <= 0; arm_id <= 0; arm_hdr <= 0;
			wd_fired <= 1; wd_blk_id <= blk_id; wd_blk_hdr <= blk_hdr;
		end
		if ((arm_tid && ctrl.state == 5'd20) || (arm_thdr && ctrl.state == 5'd17)) begin
			thold <= 1; arm_tid <= 0; arm_thdr <= 0;
		end
		if (arm_idf && ctrl.state == 5'd20 && !pblock) begin pblock <= 1; arm_idf <= 0; fall_n <= -1; end
		// released only after ss_ddr's two-flop request sync has seen the fall
		if (pblock && save_req_d && !save_req) fall_n <= 0;
		else if (pblock && fall_n >= 0) begin
			fall_n <= fall_n + 1;
			if (fall_n == 7) pblock <= 0;
		end
	end

	reg req_d = 0;
	integer nreq_busy = 0;
	always @(posedge clk) begin
		req_d <= save_req | load_req;
		if ((save_req | load_req) && !req_d && ssd_busy) nreq_busy = nreq_busy + 1;
	end

	task clr;
		begin nw = 0; n0 = 0; n1 = 0; npay = 0; nidx = 0; first_off = -1; first_id = 0; end
	endtask

	task calib(output ok);
		integer k;
		begin
			reset <= 1; repeat (20) @(posedge clk); reset <= 0;
			k = 0;
			while (cal_busy && k < 400000) begin @(posedge clk); k = k + 1; end
			repeat (100) @(posedge clk);
			ok = !cal_busy && chain_len == 16'd200;
			$display("rig GUARD_BITS=%0d calibrated chain_len=%0d", GB, chain_len);
		end
	endtask

	task start_save;
		integer k;
		begin
			k = 0;
			while ((busy || cal_busy) && k < 8000000) begin @(posedge clk); k = k + 1; end
			@(posedge clk); ss_save <= 1;
			k = 0;
			while (!busy && k < 100) begin @(posedge clk); k = k + 1; end
			ss_save <= 0;
		end
	endtask

	task save(output ok);
		integer k;
		begin
			start_save;
			k = 0;
			while (busy && k < 8000000) begin @(posedge clk); k = k + 1; end
			ok = !busy && !cal_busy;
			repeat (50) @(posedge clk);
			$display("  save GUARD_BITS=%0d: clocks=%0d writes=%0d word0=%0d word1=%0d payload=%0d id_elsewhere=%0d first_off=%0d first_is_id=%0d",
				GB, k, nw, n0, n1, npay, nidx, first_off, first_id);
		end
	endtask

	task wd_case(input is_hdr, output ok);
		integer k;
		begin
			wd_fired <= 0;
			if (is_hdr) arm_hdr <= 1; else arm_id <= 1;
			start_save;
			k = 0;
			while (!wd_fired && k < 8000000) begin @(posedge clk); k = k + 1; end
			ok = wd_fired;
			$display("  watchdog fired=%0d in state %0d: blk_id=%b blk_hdr=%b", wd_fired, wd_state, wd_blk_id, wd_blk_hdr);
			k = 0;
			while ((busy || cal_busy) && k < 8000000) begin @(posedge clk); k = k + 1; end
			repeat (200) @(posedge clk);
		end
	endtask

	task hold_case(input is_hdr, input press, input ld, output ok, output acc);
		integer k;
		begin
			if (is_hdr) arm_thdr <= 1; else arm_tid <= 1;
			start_save;
			k = 0;
			while (!thold && k < 8000000) begin @(posedge clk); k = k + 1; end
			k = 0;
			while ((save_req || ctrl.state != 5'd3) && k < 8000000) begin @(posedge clk); k = k + 1; end
			ok = thold && ssd_busy;
			clr;
			nreq_busy = 0;
			acc = 0;
			if (press) begin
				if (ld) ss_load <= 1; else ss_save <= 1;
				repeat (100) begin @(posedge clk); if (busy) acc = 1; end
				ss_load <= 0; ss_save <= 0;
				// past where an accepted press asks ss_ddr for its chain
				repeat (100000) begin @(posedge clk); if (busy) acc = 1; end
			end
			else repeat (20) @(posedge clk);
			thold <= 0;
			k = 0;
			while ((busy || ssd_busy) && k < 8000000) begin @(posedge clk); k = k + 1; end
			repeat (200) @(posedge clk);
		end
	endtask
endmodule

module tb_wd;
	reg clk = 0;
	always #5 clk = ~clk;

	wd_rig #(.GB(21)) ra (.clk(clk));
	wd_rig #(.GB(24)) rb (.clk(clk));

	integer fails = 0, cases = 0;
	integer r_nw, r_n0, r_n1, r_pay, r_first;
	reg r_first_id, normal_done = 0;

	task result(input [8*16-1:0] name, input pass, input [8*160-1:0] why);
		begin
			cases = cases + 1;
			if (pass) $display("RESULT: PASS - %0s", name);
			else begin fails = fails + 1; $display("RESULT: FAIL - %0s: %0s", name, why); end
		end
	endtask

	function same_a; input dummy;
		same_a = ra.nw == r_nw && ra.n0 == r_n0 && ra.n1 == r_n1 && ra.npay == r_pay && ra.first_off == r_first
		         && ra.first_id == r_first_id && ra.nidx == 0;
	endfunction
	function same_b; input dummy;
		same_b = rb.nw == r_nw && rb.n0 == r_n0 && rb.n1 == r_n1 && rb.npay == r_pay && rb.first_off == r_first
		         && rb.first_id == r_first_id && rb.nidx == 0;
	endfunction

	reg ok, ok2, cal_a, cal_b;
	reg [8*160-1:0] why;

	task hold_check(input [8*16-1:0] name, input is_hdr, input press, input ld);
		reg hok, acc, sok, good;
		reg [8*160-1:0] w;
		begin
			rb.hold_case(is_hdr, press, ld, hok, acc);
			good = hok && rb.nw == 1 && (is_hdr ? rb.n0 : rb.n1) == 1 && rb.npay == 0 && !acc && rb.nreq_busy == 0
			       && rb.ctrl.state == 5'd3;
			$sformat(w, "late writes %0d (header %0d, ID %0d, payload %0d); press accepted %b, requests while ss_ddr busy %0d; held %b state %0d",
				rb.nw, rb.n0, rb.n1, rb.npay, acc, rb.nreq_busy, hok, rb.ctrl.state);
			$display("  %0s: %0s", name, w);
			rb.clr;
			rb.save(sok);
			if (good && !(sok && same_b(0)))
				$sformat(w, "save after it differs from NORMAL: writes %0d word0 %0d word1 %0d payload %0d", rb.nw, rb.n0, rb.n1, rb.npay);
			result(name, good && sok && same_b(0), w);
		end
	endtask

	initial begin
		fork
			begin : rig_a
				ra.calib(cal_a);
				ra.clr;
				ra.save(ok);
				r_nw = ra.nw; r_n0 = ra.n0; r_n1 = ra.n1; r_pay = ra.npay; r_first = ra.first_off; r_first_id = ra.first_id;
				result("NORMAL", cal_a && ok && r_n0 == 1 && r_n1 == 1 && r_first == 2 && !r_first_id && ra.nidx == 0 && r_pay > 0,
					"no complete save with one header, one ID and the chain at slot word 2");
				normal_done = 1;

				ra.wd_case(1'b0, ok);
				ra.clr;
				ra.save(ok2);
				$sformat(why, "ID words where the payload goes: %0d; writes %0d word0 %0d word1 %0d payload %0d first_off %0d (NORMAL %0d/%0d/%0d/%0d/%0d)",
					ra.nidx, ra.nw, ra.n0, ra.n1, ra.npay, ra.first_off, r_nw, r_n0, r_n1, r_pay, r_first);
				if (!ok) why = "watchdog did not fire in ST_ID";
				result("WD_ID", ok && ok2 && same_a(0), why);

				ra.wd_case(1'b1, ok);
				ra.clr;
				ra.save(ok2);
				$sformat(why, "header writes at slot word 0: %0d (NORMAL %0d), payload words %0d (NORMAL %0d), writes %0d (NORMAL %0d)",
					ra.n0, r_n0, ra.npay, r_pay, ra.nw, r_nw);
				if (!ok) why = "watchdog did not fire in ST_HDR";
				result("WD_HDR", ok && ok2 && same_a(0), why);
			end
			begin : rig_b
				integer k;
				reg idle;
				rb.calib(cal_b);
				rb.arm_idf <= 1;
				rb.start_save;
				k = 0;
				while (!rb.pblock && k < 8000000) begin @(posedge clk); k = k + 1; end
				rb.clr;
				k = 0;
				while (rb.busy && k < 8000000) begin @(posedge clk); k = k + 1; end
				repeat (400) @(posedge clk);
				idle = !rb.busy && rb.ctrl.state == 5'd3 && !rb.pblock;
				$display("  ID_FAIL: busy=%b state=%0d xfer_ok=%b; writes after the failed ID %0d (header %0d, ID %0d, payload %0d)",
					rb.busy, rb.ctrl.state, rb.ctrl.xfer_ok, rb.nw, rb.n0, rb.n1, rb.npay);
				$sformat(why, "writes after the failed ID: %0d (header %0d, ID %0d, payload %0d); busy=%b state=%0d",
					rb.nw, rb.n0, rb.n1, rb.npay, rb.busy, rb.ctrl.state);
				ok = cal_b && rb.nw == 0 && idle;
				wait (normal_done);
				rb.clr;
				rb.save(ok2);
				if (ok && !(ok2 && same_b(0)))
					$sformat(why, "save after the failure differs from NORMAL: writes %0d word0 %0d word1 %0d payload %0d",
						rb.nw, rb.n0, rb.n1, rb.npay);
				result("ID_FAIL", ok && ok2 && same_b(0), why);
				hold_check("HOLD_ID", 1'b0, 1'b0, 1'b0);
				hold_check("HOLD_HDR", 1'b1, 1'b0, 1'b0);
				hold_check("LATE", 1'b0, 1'b1, 1'b0);
				hold_check("LATE_LOAD", 1'b0, 1'b1, 1'b1);
			end
		join
		if (fails == 0) $display("SUMMARY: PASS %0d of %0d", cases, cases);
		else $display("SUMMARY: FAIL %0d of %0d", fails, cases);
		$finish;
	end

	initial begin
		#(64'd800000000);
		$display("RESULT: FAIL - TIMEOUT");
		$display("SUMMARY: FAIL timeout");
		$finish;
	end
endmodule
