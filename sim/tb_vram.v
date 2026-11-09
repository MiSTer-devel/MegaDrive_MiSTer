`timescale 1ns/1ps

module tb_vram;
	reg MCLK = 0; always #4.657 MCLK = ~MCLK;

	function [7:0] pat(input [15:0] a);
		pat = a[7:0] ^ a[15:8] ^ 8'hA5;
	endfunction

	reg        RAS = 1, CAS = 1, WE = 1, OE = 1, SC = 1, SE = 1;
	reg  [7:0] AD = 0;
	// sel_port is savestate's decode, sel_q the copy md_board registers from it
	reg        sel_port = 0, sel_q = 0;
	always @(posedge MCLK) sel_q <= sel_port;
	reg [15:0] ss_addr = 0;
	reg  [7:0] ss_din = 0;
	reg        ss_wr = 0;
	wire [7:0] ss_dout, RD_o, SD_o;
	wire       RD_d, SD_d;

	reg        ss_en = 0, ss_in = 0;

	vram dut (
		.ss_en(ss_en), .ss_in(ss_in), .ss_out(),
		.ss_mem_sel(sel_q), .ss_mem_addr(ss_addr), .ss_mem_din(ss_din),
		.ss_mem_wr(ss_wr & sel_port), .ss_mem_dout(ss_dout),
		.MCLK(MCLK), .RAS(RAS), .CAS(CAS), .WE(WE), .OE(OE), .SC(SC), .SE(SE),
		.AD(AD), .RD_i(AD), .RD_o(RD_o), .RD_d(RD_d), .SD_o(SD_o), .SD_d(SD_d)
	);

	integer a, bad, n, changes, reads, rd_bad;
	reg [15:0] va;
	reg  [7:0] held;
	reg        eq_done = 0;

	task walk_read(input [15:0] ad, output [7:0] dq);
		begin
			// ST_MREAD: address at the end of mrd1 (md_board's register), the RAM
			// and ss_ra at mrd2, the column bytes at mrd3, ss_q at mrd4, sampled
			// at the end of mrd5
			@(posedge MCLK); ss_addr <= ad;
			@(posedge MCLK);
			@(posedge MCLK);
			@(posedge MCLK);
			@(posedge MCLK); dq = ss_dout;
		end
	endtask

	task vdp_read(input [15:0] ad);
		begin
			// row on RAS, column on CAS, then OE: RD_o holds the byte from the fifth edge
			@(posedge MCLK); AD <= ad[15:8]; RAS <= 0;
			if (ss_dout !== held) changes = changes + 1;
			@(posedge MCLK); AD <= ad[7:0]; CAS <= 0;
			if (ss_dout !== held) changes = changes + 1;
			@(posedge MCLK); OE <= 0;
			if (ss_dout !== held) changes = changes + 1;
			@(posedge MCLK);
			if (ss_dout !== held) changes = changes + 1;
			@(posedge MCLK);
			if (ss_dout !== held) changes = changes + 1;
			reads = reads + 1;
			if (RD_o !== pat(ad)) rd_bad = rd_bad + 1;
			RAS <= 1; CAS <= 1; OE <= 1;
		end
	endtask

	task vdp_cyc(input [15:0] ad, input integer hold);
		begin
			@(posedge MCLK); AD <= ad[15:8]; RAS <= 0;
			@(posedge MCLK); AD <= ad[7:0]; CAS <= 0;
			@(posedge MCLK); OE <= 0;
			repeat (hold) @(posedge MCLK);
			RAS <= 1; CAS <= 1; OE <= 1;
		end
	endtask

	task walk_word(input [15:0] ad, output [7:0] dq);
		begin
			// D61: addr_q at the end of mrd1, mem_dout_q samples at the end of mrd5,
			// the address stands for seven clocks
			@(posedge MCLK); ss_addr <= ad;
			@(posedge MCLK);
			@(posedge MCLK);
			@(posedge MCLK);
			@(posedge MCLK); dq = ss_dout;
			@(posedge MCLK);
			@(posedge MCLK);
		end
	endtask

	task vdp_write(input [15:0] ad, input [7:0] d);
		begin
			// row on RAS, column on CAS, data on WE: wr is a level, the RAM takes
			// it from the fourth edge
			@(posedge MCLK); AD <= ad[15:8]; RAS <= 0;
			@(posedge MCLK); AD <= ad[7:0]; CAS <= 0;
			@(posedge MCLK); AD <= d; WE <= 0;
			@(posedge MCLK);
			@(posedge MCLK); RAS <= 1; CAS <= 1; WE <= 1;
		end
	endtask

	task walk_write(input [15:0] ad, input [7:0] d);
		begin
			// ST_MWRITE's cadence: address and data with a one-edge strobe
			@(posedge MCLK); ss_addr <= ad; ss_din <= d; ss_wr <= 1;
			@(posedge MCLK); ss_wr <= 0;
			@(posedge MCLK);
			@(posedge MCLK);
		end
	endtask

	reg sel_d = 0;
	always @(posedge MCLK) sel_d <= dut.ss_mem_sel;

	reg        sh_on = 0, sh_ld = 0;
	reg  [7:0] sh_exp = 0;
	integer    sh_loads = 0, sh_bad = 0;
	always @(posedge MCLK) begin
		sh_ld  <= sh_on && !ss_en && dut.rd;
		sh_exp <= dut.slice_p[dut.addr[7:0]];
	end
	always @(negedge MCLK) if (sh_ld) begin
		sh_loads = sh_loads + 1;
		if (RD_o !== sh_exp) begin
			if (sh_bad < 4) $display("  SHIFT %0t RD_o %h expected %h", $time, RD_o, sh_exp);
			sh_bad = sh_bad + 1;
		end
	end

`ifdef VRAM_REF
	// RESYNC's reference: upstream's vram.v on the same VDP lines, its RAM
	// filled with the bytes WALK writes into dut's
	wire [7:0] rRD_o, rSD_o;
	wire       rRD_d, rSD_d;
	vram_up ref_r (
		.MCLK(MCLK), .RAS(RAS), .CAS(CAS), .WE(WE), .OE(OE), .SC(SC), .SE(SE),
		.AD(AD), .RD_i(AD), .RD_o(rRD_o), .RD_d(rRD_d), .SD_o(rSD_o), .SD_d(rSD_d)
	);
	genvar gi;
	generate for (gi = 0; gi < 8; gi = gi + 1) begin : rfill
		integer fr, fc;
		initial begin
			#1;
			for (fr = 0; fr < 256; fr = fr + 1)
				for (fc = 0; fc < 32; fc = fc + 1)
					ref_r.l2[gi].mem.ram.mem[fr][8*fc +: 8] = pat(fr * 256 + gi * 32 + fc);
		end
	end endgenerate

	// a load counts when the select was down in both clocks before its edge:
	// one clock for ss_ra, one for the RAM row
	reg     rs_on = 0, rs_fell = 0, rs_q = 0, rs_arm = 0;
	integer rs_loads = 0, rs_post = 0, rs_clk = 0, rs_bad = 0;
	always @(posedge MCLK) begin
		rs_q <= rs_on && !dut.ss_mem_sel && !sel_d && (dut.rd || ref_r.rd);
		if (rs_on && sel_d && !dut.ss_mem_sel) rs_fell <= 1;
	end
	always @(negedge MCLK) if (rs_on && (rs_q || rs_arm)) begin
		if (rs_q) begin
			rs_loads = rs_loads + 1;
			if (rs_fell) begin rs_post = rs_post + 1; rs_arm = 1; end
		end
		else rs_clk = rs_clk + 1;
		if (RD_o !== rRD_o) begin
			if (rs_bad < 4) $display("  RESYNC %0t RD_o %h upstream %h", $time, RD_o, rRD_o);
			rs_bad = rs_bad + 1;
		end
	end
`endif

	reg [7:0] q;
	reg [15:0] wa;
	integer m0, len, w_bad, rd0;
	integer st_bad4, st_eq3;
	reg [15:0] st_hist [1:2000];
	integer wd_wbad, wd_lost, wd_land, wd_vw, wd_ctl;
	reg w_end = 0;
	reg [15:0] wd_wl [0:199];
	reg [15:0] wd_vl [0:2047];
	integer seed = 32'h0D19;
	initial begin
		repeat (4) @(posedge MCLK);

		// WALK: every byte in at ST_MWRITE's cadence (one word per three clocks,
		// a buffer fetch of three clocks before every four), then out at ST_MREAD's
		@(posedge MCLK); sel_port <= 1;
		for (a = 0; a < 65536; a = a + 1) begin
			if (a[1:0] == 2'd0) repeat (3) @(posedge MCLK);
			ss_addr <= a[15:0]; ss_din <= pat(a[15:0]); ss_wr <= 1;
			@(posedge MCLK); ss_wr <= 0;
			@(posedge MCLK);
			@(posedge MCLK);
		end
		@(posedge MCLK);
		repeat (8) @(posedge MCLK); sel_port <= 0;
		repeat (8) @(posedge MCLK); sel_port <= 1;
		bad = 0;
		for (a = 0; a < 65536; a = a + 1) begin
			walk_read(a[15:0], q);
			if (q !== pat(a[15:0])) begin
				if (bad < 4) $display("  WALK addr %h read %h expected %h", a[15:0], q, pat(a[15:0]));
				bad = bad + 1;
			end
		end
		$display("WALK: 65536 bytes written and read back, %0d differ", bad);
		if (bad == 0) $display("RESULT: PASS - WALK: the walk reads back every byte it wrote");
		else          $display("RESULT: FAIL - WALK: the walk does not read back what it wrote");

		// STREAM: a new address on every edge; right after edge e ss_dout must be
		// the byte of the address presented at edge e - 4 (D61's two stages) and
		// mostly not the one at e - 3, which the single-stage walk gave
		st_bad4 = 0; st_eq3 = 0;
		for (n = 1; n <= 2000; n = n + 1) begin
			@(posedge MCLK);
			if (n >= 5) begin
				if (ss_dout !== pat(st_hist[n - 4])) begin
					if (st_bad4 < 4) $display("  STREAM edge %0d: ss_dout %h expected %h (latency 4)", n, ss_dout, pat(st_hist[n - 4]));
					st_bad4 = st_bad4 + 1;
				end
				if (ss_dout === pat(st_hist[n - 3])) st_eq3 = st_eq3 + 1;
			end
			va = $random(seed);
			st_hist[n] = va;
			ss_addr <= va;
		end
		$display("STREAM: 2000 addresses, %0d wrong at latency 4, %0d equal at latency 3", st_bad4, st_eq3);
		if (st_bad4 == 0 && st_eq3 < 1996)
			$display("RESULT: PASS - STREAM: the walk byte arrives four edges after its address");
		else
			$display("RESULT: FAIL - STREAM: the walk byte does not arrive four edges after its address");

		// HOLD: read one byte, let go of the select, then let the VDP read all over
		// the RAM: the walk's output must stay where the walk left it
		walk_read(16'h1234, q);
		@(posedge MCLK); sel_port <= 0;
		repeat (3) @(posedge MCLK);
		held = ss_dout;
		changes = 0; reads = 0; rd_bad = 0;
		for (n = 0; n < 2000; n = n + 1) begin
			va = $random(seed);
			vdp_read(va);
		end
		repeat (2) @(posedge MCLK);
		$display("HOLD: walk byte %h (expected %h), %0d VDP reads (%0d wrong), output changed on %0d clocks",
		         q, pat(16'h1234), reads, rd_bad, changes);
		if (q === pat(16'h1234) && reads == 2000 && rd_bad == 0 && changes == 0)
			$display("RESULT: PASS - HOLD: VDP reads leave the walk output alone");
		else
			$display("RESULT: FAIL - HOLD: the walk output follows the VDP's reads");

		// SHIFT: scan random bits through the chain, the VDP lines held in a read,
		// then VDP reads: every RD_o load is the byte at addr[7:0]
		rd_bad = 0; reads = 0; held = ss_dout;
		@(posedge MCLK); sh_on <= 1;
		for (n = 0; n < 8; n = n + 1) begin
			len = 200 + {$random(seed)} % 1801;
			@(posedge MCLK); ss_en <= 1; RAS <= 0; CAS <= 0; OE <= 0;
			repeat (len) begin
				@(posedge MCLK); ss_in <= $random(seed); AD <= $random(seed);
			end
			@(posedge MCLK); ss_en <= 0; ss_in <= 0;
			repeat (3) @(posedge MCLK);
			RAS <= 1; CAS <= 1; OE <= 1;
			repeat (2) @(posedge MCLK);
			for (a = 0; a < 20; a = a + 1) begin
				va = $random(seed);
				vdp_read(va);
			end
		end
		repeat (2) @(posedge MCLK); sh_on <= 0;
		@(posedge MCLK);
		$display("SHIFT: 8 shifts, %0d RD_o loads (%0d differ), %0d VDP reads (%0d wrong)",
		         sh_loads, sh_bad, reads, rd_bad);
		if (sh_loads > 0 && sh_bad == 0 && reads == 160 && rd_bad == 0)
			$display("RESULT: PASS - SHIFT: after a shift the VDP reads the byte at its address");
		else
			$display("RESULT: FAIL - SHIFT: after a shift the VDP read column is not addr[7:0]");

		// WDW: VDP writes and reads run under a save walk, then a restore walk (walk
		// on the lower half, VDP on the upper): the walk's bytes come back, the
		// VDP's reads are its own and its writes are dropped while the walk owns the RAM
		wd_wbad = 0; wd_lost = 0; wd_land = 0; wd_vw = 0; wd_ctl = 0; w_end = 0;
		reads = 0; rd_bad = 0;
		va = 16'h8321;
		vdp_write(va, ~pat(va));
		@(posedge MCLK); sel_port <= 1;
		repeat (2) @(posedge MCLK);
		walk_read(va, q);
		if (q !== ~pat(va)) wd_ctl = wd_ctl + 1;
		walk_write(va, pat(va));
		fork
			begin
				for (a = 0; a < 200; a = a + 1) begin
					wa = $random(seed); wa[15] = 0;
					walk_word(wa, q);
					if (q !== pat(wa)) wd_wbad = wd_wbad + 1;
				end
				for (a = 0; a < 200; a = a + 1) begin
					wa = $random(seed); wa[15] = 0;
					wd_wl[a] = wa;
					walk_write(wa, ~pat(wa));
				end
				w_end = 1;
			end
			while (!w_end) begin
				va = $random(seed); va[15] = 1;
				if (va[0] && wd_vw < 2048) begin
					wd_vl[wd_vw] = va; wd_vw = wd_vw + 1;
					vdp_write(va, ~pat(va));
				end
				else vdp_read(va);
			end
		join
		for (a = 0; a < 200; a = a + 1) begin
			walk_read(wd_wl[a], q);
			if (q !== ~pat(wd_wl[a])) wd_lost = wd_lost + 1;
		end
		for (a = 0; a < 200; a = a + 1) walk_write(wd_wl[a], pat(wd_wl[a]));
		for (a = 0; a < wd_vw; a = a + 1) begin
			walk_read(wd_vl[a], q);
			if (q !== pat(wd_vl[a])) begin
				if (wd_land < 4) $display("  WDW VDP write at %h landed during the walk: %h", wd_vl[a], q);
				wd_land = wd_land + 1;
			end
		end
		@(posedge MCLK); sel_port <= 0;
		repeat (3) @(posedge MCLK);
		$display("WDW: control %0d, 200 walk reads (%0d wrong), 200 walk writes (%0d lost), %0d VDP reads (%0d wrong), %0d VDP writes (%0d landed)",
		         wd_ctl, wd_wbad, wd_lost, reads, rd_bad, wd_vw, wd_land);
		if (wd_ctl == 0 && wd_wbad == 0 && wd_lost == 0 && reads > 0 && rd_bad == 0 && wd_vw > 0 && wd_land == 0)
			$display("RESULT: PASS - WDW: the VDP's accesses and the walk's do not disturb each other");
		else
			$display("RESULT: FAIL - WDW: a VDP access and the walk disturb each other");

`ifdef VRAM_REF
		// RESYNC: VDP reads run during a walk read; once the select is down the
		// VDP's loads equal upstream's again
		w_bad = 0; w_end = 0;
		@(posedge MCLK); rs_on <= 1;
		for (a = 0; a < 20; a = a + 1) begin
			va = $random(seed);
			vdp_cyc(va, 1 + {$random(seed)} % 6);
		end
		@(posedge MCLK); sel_port <= 1;
		repeat (2) @(posedge MCLK);
		fork
			begin
				for (a = 0; a < 200; a = a + 1) begin
					wa = $random(seed);
					walk_word(wa, q);
					if (q !== pat(wa)) w_bad = w_bad + 1;
				end
				w_end = 1;
			end
			while (!w_end) begin
				va = $random(seed);
				vdp_cyc(va, 1 + {$random(seed)} % 6);
			end
		join
		// a read whose column comes in during the walk and whose OE stays low
		// past the select's fall
		va = $random(seed);
		if (va[7:0] == wa[7:0]) va[7:0] = wa[7:0] ^ 8'h5A;
		@(posedge MCLK); AD <= va[15:8]; RAS <= 0;
		@(posedge MCLK); AD <= va[7:0]; CAS <= 0;
		@(posedge MCLK); OE <= 0;
		@(posedge MCLK); sel_port <= 0;
		repeat (8) @(posedge MCLK);
		RAS <= 1; CAS <= 1; OE <= 1;
		for (a = 0; a < 300; a = a + 1) begin
			va = $random(seed);
			vdp_cyc(va, 1 + {$random(seed)} % 6);
		end
		repeat (2) @(posedge MCLK); rs_on <= 0;
		@(posedge MCLK);
		$display("RESYNC: 200 walk reads (%0d wrong), %0d loads compared (%0d after the walk), %0d later clocks compared, %0d differ",
		         w_bad, rs_loads, rs_post, rs_clk, rs_bad);
		if (w_bad == 0 && rs_post > 0 && rs_bad == 0)
			$display("RESULT: PASS - RESYNC: after the walk the VDP reads equal upstream's");
		else
			$display("RESULT: FAIL - RESYNC: after the walk the VDP reads differ from upstream's");

		wait (eq_done);
`endif
		$finish;
	end

`ifdef VRAM_REF
	// EQ: with the savestate port idle, the VDP side is upstream's vram.v
	reg        eRAS = 1, eCAS = 1, eWE = 1, eOE = 1, eSC = 1, eSE = 1;
	reg  [7:0] eAD = 0;
	reg [15:0] e_saddr = 0;
	reg  [7:0] e_sdin = 0;
	reg        e_swr = 0;
	wire [7:0] eRD_o, eSD_o, uRD_o, uSD_o;
	wire       eRD_d, eSD_d, uRD_d, uSD_d;

	vram dut_e (
		.ss_en(1'b0), .ss_in(1'b0), .ss_out(),
		.ss_mem_sel(1'b0), .ss_mem_addr(e_saddr), .ss_mem_din(e_sdin),
		.ss_mem_wr(e_swr), .ss_mem_dout(),
		.MCLK(MCLK), .RAS(eRAS), .CAS(eCAS), .WE(eWE), .OE(eOE), .SC(eSC), .SE(eSE),
		.AD(eAD), .RD_i(eAD), .RD_o(eRD_o), .RD_d(eRD_d), .SD_o(eSD_o), .SD_d(eSD_d)
	);
	vram_up ref_e (
		.MCLK(MCLK), .RAS(eRAS), .CAS(eCAS), .WE(eWE), .OE(eOE), .SC(eSC), .SE(eSE),
		.AD(eAD), .RD_i(eAD), .RD_o(uRD_o), .RD_d(uRD_d), .SD_o(uSD_o), .SD_d(uSD_d)
	);

	// upstream's registers have no initial values; give them the zeros the
	// savestate copy declares, as the FPGA powers both up
	initial begin
		ref_e.addr = 0; ref_e.dt = 0; ref_e.addr_ser = 0; ref_e.ser = 0;
		ref_e.o_OE = 0; ref_e.o_RAS = 0; ref_e.o_cas = 0; ref_e.o_SC = 0; ref_e.o_valid = 0;
		ref_e.vram_ser = 0;
	end

	integer ec = 0, e_bad = 0, e_valid = 0, e_sdchg = 0, eseed = 32'h0E19;
	reg [7:0] e_sd_last = 0;
	reg [31:0] r;
	always @(posedge MCLK) if (!eq_done) begin
		if ({eRD_o, eRD_d, eSD_o, eSD_d} !== {uRD_o, uRD_d, uSD_o, uSD_d}) begin
			if (e_bad < 4)
				$display("  EQ clock %0d: RD_o %h/%h RD_d %b/%b SD_o %h/%h SD_d %b/%b",
				         ec, eRD_o, uRD_o, eRD_d, uRD_d, eSD_o, uSD_o, eSD_d, uSD_d);
			e_bad = e_bad + 1;
		end
		if (!uRD_d) e_valid = e_valid + 1;
		if (uSD_o !== e_sd_last) e_sdchg = e_sdchg + 1;
		e_sd_last <= uSD_o;
		r = $random(eseed);
		{eRAS, eCAS, eWE, eOE, eSC, eSE} <= r[5:0];
		eAD     <= r[13:6];
		e_saddr <= $random(eseed);
		e_sdin  <= r[21:14];
		e_swr   <= r[22];
		ec = ec + 1;
		if (ec == 200000) begin
			$display("EQ: 200000 clocks, RD valid on %0d, SD_o changed on %0d, %0d differ",
			         e_valid, e_sdchg, e_bad);
			if (e_bad == 0 && e_valid > 0 && e_sdchg > 0)
				$display("RESULT: PASS - EQ: the VDP side equals upstream's vram.v");
			else
				$display("RESULT: FAIL - EQ: the VDP side differs from upstream's vram.v");
			eq_done <= 1;
		end
	end
`endif
endmodule
