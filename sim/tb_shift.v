// structural test, no machine state: shift a known pattern in, shift it straight
// back out, and expect the exact pattern back from a plain SS_CHAIN_LEN-bit shift.
`timescale 1ns/1ps
`include "ss_params.vh"

module tb_shift;
	reg MCLK2 = 0; always #4.657 MCLK2 = ~MCLK2;
	reg ss_en = 0, ss_in = 0;
	wire ss_out;
	wire [14:0] ra; wire [1:0] rb; wire [15:0] rd, ro; wire rw;
	wire [12:0] za; wire [7:0] zd, zo; wire zw;
	wire [22:0] ca; wire [9:0] ta;

	md_board dut (
		.MCLK2(MCLK2), .ext_reset(1'b1), .reset_button(1'b0),
		.ext_vres(1'b1), .ext_zres(1'b1),
		.ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_out),
		.ss_sat_sel(1'b0), .ss_sat_addr(16'd0), .ss_sat_din(16'd0), .ss_sat_wr(1'b0), .ss_sat_dout(),
		.ram_68k_address(ra), .ram_68k_byteena(rb), .ram_68k_data(rd), .ram_68k_wren(rw), .ram_68k_o(16'h0),
		.ram_z80_address(za), .ram_z80_data(zd), .ram_z80_wren(zw), .ram_z80_o(8'h0),
		.M3(1'b1), .cart_data(16'h4E71), .cart_data_en(1'b1),
		.cart_address(ca), .cart_cs(), .cart_oe(), .cart_lwr(), .cart_uwr(),
		.cart_time(), .cart_cas2(), .cart_data_wr(), .cart_dma(),
		.cart_m3_pause(1'b0), .ext_dtack(1'b0), .pal(1'b0), .jap(1'b0),
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
	dpram #(13,8) rz (.clock(MCLK2), .address_a(za), .data_a(zd), .wren_a(zw), .byteena_a(1'b1), .q_a(zo),
		.address_b(13'd0), .data_b(8'd0), .wren_b(1'b0), .byteena_b(1'b1), .q_b());

	reg [`SS_CHAIN_LEN-1:0] pat, got;
	integer i, bad, first, last;

	initial begin
		for (i = 0; i < `SS_CHAIN_LEN; i = i + 1) pat[i] = ($random >> 3) & 1;

		repeat (50) @(posedge MCLK2);

		// drive and sample on the falling edge: on the rising edge, the same one the
		// chain samples on, event ordering decides whether the DUT sees old or new.
		@(negedge MCLK2) ss_en = 1; ss_in = 0;
		repeat (`SS_CHAIN_LEN) @(negedge MCLK2);
		for (i = 0; i < `SS_CHAIN_LEN; i = i + 1) begin
			ss_in = pat[i];
			@(negedge MCLK2);
		end
		// read it straight back
		ss_in = 0;
		for (i = 0; i < `SS_CHAIN_LEN; i = i + 1) begin
			got[i] = ss_out;
			@(negedge MCLK2);
		end
		ss_en = 0;

		bad = 0; first = -1; last = -1;
		for (i = 0; i < `SS_CHAIN_LEN; i = i + 1)
			if (pat[i] !== got[i]) begin
				bad = bad + 1;
				if (first < 0) first = i;
				last = i;
			end

		$display("chain length      : %0d bits", `SS_CHAIN_LEN);
		$display("bits corrupted    : %0d", bad);
		if (bad) $display("first bad bit     : %0d, last bad bit: %0d", first, last);
		if (bad == 0) $display("RESULT: PASS - chain is a clean shift register");
		else          $display("RESULT: FAIL - chain does not shift cleanly");
		$finish;
	end
endmodule
