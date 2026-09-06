// Acceptance gate for savestate scan chain.
//
// Proof obligation: the scanned bits fully determine the machine's future.
//   run R  -> capture chain as S1
//   run M  -> capture chain as S2
//   restore S1, run M -> capture chain as S3
//   S3 must equal S2.
//
// Capture is circular (ss_in fed from ss_out) so reading the chain does not
// disturb it: after SS_CHAIN_LEN shifts the state is back where it started.
`timescale 1ns/1ps
`include "ss_params.vh"

module tb_scan;
	parameter BOOT   = 200;
	parameter RUNCYC = 1600000;  // cpu_reset releases ~1396275 cyc in; must run past that
	parameter STEP   = 5000;     // cycles between captures

	reg MCLK2 = 0; always #4.657 MCLK2 = ~MCLK2;
	reg ext_reset = 1, ext_vres = 1, ext_zres = 1;

	reg  ss_en = 0, ss_in = 0;
	wire ss_out;

	wire [14:0] ra; wire [1:0] rb; wire [15:0] rd, ro; wire rw;
	wire [12:0] za; wire [7:0] zd, zo; wire zw;
	wire [22:0] cart_address;
	wire cart_cs, cart_oe, cart_lwr, cart_uwr, cart_time, cart_cas2, cart_dma;
	wire [15:0] cart_data_wr; wire [9:0] ta;

	reg [15:0] rom [0:4095]; integer i;
	initial begin
		for (i=0;i<4096;i=i+1) rom[i]=16'h4E71;
		rom[0]=16'h0000; rom[1]=16'hFFFE; rom[2]=16'h0000; rom[3]=16'h0200;
		rom[16'h100]=16'h5200;   // ADDQ.B #1,D0
		rom[16'h101]=16'h60FC;   // BRA.S  *-4
	end
	wire [15:0] cart_data = rom[cart_address[11:0]];

	md_board dut (
		.MCLK2(MCLK2), .ext_reset(ext_reset), .reset_button(1'b0),
		.ext_vres(ext_vres), .ext_zres(ext_zres),
		.ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_out),
		.ram_68k_address(ra), .ram_68k_byteena(rb), .ram_68k_data(rd), .ram_68k_wren(rw), .ram_68k_o(ro),
		.ram_z80_address(za), .ram_z80_data(zd), .ram_z80_wren(zw), .ram_z80_o(zo),
		.M3(1'b1), .cart_data(cart_data), .cart_data_en(1'b1),
		.cart_address(cart_address), .cart_cs(cart_cs), .cart_oe(cart_oe),
		.cart_lwr(cart_lwr), .cart_uwr(cart_uwr), .cart_time(cart_time),
		.cart_cas2(cart_cas2), .cart_data_wr(cart_data_wr), .cart_dma(cart_dma),
		.cart_m3_pause(1'b0), .ext_dtack(1'b1), .pal(1'b0), .jap(1'b0),
		.tmss_enable(1'b0), .tmss_data(16'h4E71), .tmss_address(ta),
		.V_R(), .V_G(), .V_B(), .V_HS(), .V_VS(), .V_CS(),
		.A_L(), .A_R(), .A_L_2612(), .A_R_2612(), .MOL(), .MOR(), .MOL_2612(), .MOR_2612(),
		.PSG(), .DAC_ch_index(), .fm_sel23(),
		.PA_i(7'h7F), .PA_o(), .PA_d(), .PB_i(7'h7F), .PB_o(), .PB_d(), .PC_i(7'h7F), .PC_o(), .PC_d(),
		.vdp_hclk1(), .vdp_intfield(), .vdp_de_h(), .vdp_de_v(), .vdp_m5(),
		.vdp_rs1(), .vdp_m2(), .vdp_lcb(), .vdp_psg_clk1(), .vdp_cramdot_dis(1'b0),
		.fm_clk1(), .vdp_hsync2(), .vdp_vsync2(), .ym2612_status_enable(1'b0),
		.dma_68k_req(1'b0), .dma_z80_req(1'b0), .dma_z80_ack(), .res_z80(),
		.vdp_dma_oe_early(), .vdp_dma()
	);

	dpram #(15,16) r68 (.clock(MCLK2), .address_a(ra), .data_a(rd), .wren_a(rw), .byteena_a(rb), .q_a(ro),
		.address_b(15'd0), .data_b(16'd0), .wren_b(1'b0), .byteena_b(2'b11), .q_b());
	dpram #(13,8) rz80 (.clock(MCLK2), .address_a(za), .data_a(zd), .wren_a(zw), .byteena_a(1'b1), .q_a(zo),
		.address_b(13'd0), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b());

	reg [`SS_CHAIN_LEN-1:0] s1, s2, s3, s1b;
	integer n, diff, first, last, runs, xcnt;

	task run_cycles(input integer c);
		integer k;
		begin for (k=0;k<c;k=k+1) @(posedge MCLK2); end
	endtask

	// Driven and sampled on the falling edge. Both tasks used the rising one, the
	// same edge the chain samples on: iverilog resolved the ordering the same wrong
	// way every run, so the bench failed identically on builds that were bit exact
	// on hardware. tb_shift had the same defect and tb_ctrl had it fixed once.
	// destructive read: the chain is filled with zeros as it is shifted out,
	// so every capture must be followed by a restore. no feedback path from
	// ss_out back to ss_in, which is what real hardware does too.
	task capture(output reg [`SS_CHAIN_LEN-1:0] buf_o);
		integer k;
		begin
			// align to a falling edge only when the chain is not already
			// shifting. A wait here between two back-to-back tasks would let one
			// more clock through with ss_en high, which shifts the chain by a bit
			// and loses the last one.
			if (!ss_en) @(negedge MCLK2);
			ss_en = 1; ss_in = 0;
			for (k=0;k<`SS_CHAIN_LEN;k=k+1) begin
				buf_o[k] = ss_out;
				@(negedge MCLK2);
			end
			// leave ss_en high: dropping it here would let the machine run a free
			// clock between capture and restore, which changes state and makes the
			// round-trip look broken when it is not.
			ss_in = 0;
		end
	endtask

	task restore(input reg [`SS_CHAIN_LEN-1:0] buf_i);
		integer k;
		begin
			ss_en = 1;
			for (k=0;k<`SS_CHAIN_LEN;k=k+1) begin
				ss_in = buf_i[k];
				@(negedge MCLK2);
			end
			// leave ss_en high: dropping it here would let the machine run a free
			// clock between capture and restore, which changes state and makes the
			// round-trip look broken when it is not.
			ss_in = 0;
		end
	endtask

	initial begin
		$display("scan chain length = %0d bits (%0d bytes)", `SS_CHAIN_LEN, (`SS_CHAIN_LEN+7)/8);
		run_cycles(BOOT);
		ext_reset = 0; ext_vres = 0; ext_zres = 0;
		run_cycles(RUNCYC);

		capture(s1); restore(s1);

		// sub-test: is the chain itself lossless? read it straight back with no
		// cycles in between. any difference here is a capture/restore defect,
		// not a question of whether the machine resumes identically.
		capture(s1b); restore(s1b);
		diff = 0;
		for (n=0;n<`SS_CHAIN_LEN;n=n+1) if (s1[n] !== s1b[n]) diff = diff + 1;
		$display("round-trip fidelity: %0d/%0d bits differ on immediate re-read", diff, `SS_CHAIN_LEN);

		// ss_en down, or run_cycles shifts the chain instead of running the
		// machine: every "resumes identically" result to date was measured with
		// the enable still high, comparing two chains full of shifted-in zeros.
		ss_en = 0;
		run_cycles(STEP);
		capture(s2); restore(s2);

		restore(s1);
		ss_en = 0;
		run_cycles(STEP);
		capture(s3);

		// X in a capture is simulation, not hardware. The VDP's arrays have no
		// initial content in a bench and the chain carries their output
		// registers; on the chip every flop and every M10K comes up from the
		// bitstream. An X that stays X compares equal to itself under !==, so it
		// cannot hide a divergence below. A chain that has gone mostly X is a
		// different matter, and that is what this checks.
		//
		// This used to be `if (^s1 === 1'bx) $finish`, which aborted every run
		// before the comparison the bench exists for.
		xcnt = 0;
		for (n=0;n<`SS_CHAIN_LEN;n=n+1) if (s1[n] === 1'bx) xcnt = xcnt + 1;
		$display("bits X in the capture: %0d/%0d (simulation only)", xcnt, `SS_CHAIN_LEN);
		if (xcnt * 4 > `SS_CHAIN_LEN) begin
			$display("RESULT: FAIL - %0d bits are X, the chain is not carrying state", xcnt);
			$finish;
		end

		// == returns X when either side has one, and `if (x)` is false, so the
		// vacuity check has to be counted like everything else here
		diff = 0;
		for (n=0;n<`SS_CHAIN_LEN;n=n+1) if (s1[n] !== s2[n]) diff = diff + 1;
		if (diff == 0) begin
			$display("RESULT: FAIL - state did not change over %0d cycles, test is vacuous", STEP);
			$finish;
		end
		$display("state moved over %0d cycles: %0d/%0d bits", STEP, diff, `SS_CHAIN_LEN);

		diff = 0;
		for (n=0;n<`SS_CHAIN_LEN;n=n+1) if (s2[n] !== s3[n]) diff = diff + 1;

		if (diff != 0) begin
			// report where the divergence sits so it can be mapped back to a module
			first = -1; last = -1; runs = 0;
			for (n=0;n<`SS_CHAIN_LEN;n=n+1) begin
				if (s2[n] !== s3[n]) begin
					if (first < 0) first = n;
					if (last >= 0 && n != last+1) begin
						$display("  diverging run: bits %0d..%0d (%0d bits)", first, last, last-first+1);
						first = n; runs = runs + 1;
					end
					last = n;
				end
			end
			if (first >= 0) $display("  diverging run: bits %0d..%0d (%0d bits)", first, last, last-first+1);
		end
		if (diff == 0)
			$display("RESULT: PASS - restored state replays identically (%0d bits)", `SS_CHAIN_LEN);
		else
			$display("RESULT: FAIL - %0d/%0d bits diverge after restore", diff, `SS_CHAIN_LEN);
		$finish;
	end
endmodule
