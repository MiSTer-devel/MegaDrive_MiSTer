`timescale 1ns/1ps

module tb_vdw;
	parameter BOOT = 1700000;

	reg MCLK2 = 0; always #4.657 MCLK2 = ~MCLK2;
	reg ext_reset = 1, ext_vres = 1, ext_zres = 1;
	reg ctrl_reset = 1;
	wire reset_button;
	md_reset #(.DIV(3)) rstgen (
		.clk(MCLK2), .loading(1'b0), .reset(1'b0), .cal_busy(1'b0), .hold(1'b0),
		.md_reset(), .s_reset(), .btn_reset(reset_button), .ss_reset(), .ram_rst_a()
	);

	wire ss_en, ss_in, ss_out, ss_busy, cal_busy;
	wire ss_en_cpu, ss_en_vdp_fm, ss_en_vram;
	reg  ss_save = 0, ss_load = 0;

	wire [14:0] ra; wire [1:0] rb; wire [15:0] rd, ro; wire rw;
	wire [12:0] za; wire [7:0] zd, zo; wire zw;
	wire [22:0] ca; wire [9:0] ta;

	wire [15:0] mem_addr, mem_din, mem_dout;
	wire  [3:0] mem_sel;
	wire        mem_wr;
	wire [15:0] ss_wq, arr_q, sat_q;
	wire  [7:0] ss_zq, vram_q;
	// .* below connects load_walk and xfer_busy where the controller has the ports;
	// tri0 reads 0 where it does not, so this file also builds against one without them
	tri0        load_walk, xfer_busy;

	// MegaDrive.sv's selects and strobes
	wire vram_sel = ss_busy & ((mem_sel == 4'd2) | load_walk);
	wire arr_sel  = ss_busy & ((mem_sel == 4'd3) | load_walk);
	wire sat_sel  = ss_busy & ((mem_sel == 4'd5) | load_walk);

	reg [15:0] rom [0:4095]; integer i;
	wire [15:0] cart_data = rom[ca[11:0]];

	md_board #(.SS_EN_SPLIT(1)) dut (
		.MCLK2(MCLK2), .ext_reset(ext_reset), .reset_button(reset_button),
		.ext_vres(ext_vres), .ext_zres(ext_zres),
		.ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_out),
		.ss_en_cpu(ss_en_cpu), .ss_en_vdp_fm(ss_en_vdp_fm), .ss_en_vram(ss_en_vram),
		.ss_arr_sel(arr_sel), .ss_arr_addr(mem_addr), .ss_arr_din(mem_din),
		.ss_arr_wr(mem_wr & (mem_sel == 4'd3)), .ss_arr_dout(arr_q),
		.ss_sat_sel(sat_sel), .ss_sat_addr(mem_addr), .ss_sat_din(mem_din),
		.ss_sat_wr(mem_wr & (mem_sel == 4'd5)), .ss_sat_dout(sat_q),
		.ss_mem_sel(vram_sel), .ss_mem_addr(mem_addr),
		.ss_mem_din(mem_din[7:0]), .ss_mem_wr(mem_wr & (mem_sel == 4'd2)),
		.ss_mem_dout(vram_q),
		.ram_68k_address(ra), .ram_68k_byteena(rb), .ram_68k_data(rd), .ram_68k_wren(rw), .ram_68k_o(ro),
		.ram_z80_address(za), .ram_z80_data(zd), .ram_z80_wren(zw), .ram_z80_o(zo),
		.M3(1'b1), .cart_data(cart_data), .cart_data_en(1'b1),
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

	reg r68_wr_b = 0;
	always @(posedge MCLK2) r68_wr_b <= mem_wr & (mem_sel == 4'd0);
	dpram #(15,16) r68 (.clock(MCLK2), .address_a(ra), .data_a(rd), .wren_a(rw & ~ss_en), .byteena_a(rb), .q_a(ro),
		.address_b(mem_addr[14:0]), .data_b(mem_din),
		.wren_b(r68_wr_b), .byteena_b(2'b11), .q_b(ss_wq));
	dpram #(13,8) rz (.clock(MCLK2), .address_a(za), .data_a(zd), .wren_a(zw & ~ss_en), .byteena_a(1'b1), .q_a(zo),
		.address_b(mem_addr[12:0]), .data_b(mem_din[7:0]),
		.wren_b(mem_wr & (mem_sel == 4'd1)), .byteena_b(1'b1), .q_b(ss_zq));

	reg [15:0] cartmodel [0:15];
	reg [15:0] cq = 0;
	initial for (i = 0; i < 16; i = i + 1) cartmodel[i] = i * 16'h1111 + 16'h37;
	always @(posedge MCLK2) begin
		if (mem_wr && mem_sel == 4'd4) cartmodel[mem_addr[3:0]] <= mem_din;
		cq <= cartmodel[mem_addr[3:0]];
	end

	assign mem_dout = (mem_sel == 4'd0) ? ss_wq :
	                  (mem_sel == 4'd1) ? {8'd0, ss_zq} :
	                  (mem_sel == 4'd2) ? {8'd0, vram_q} :
	                  (mem_sel == 4'd3) ? arr_q :
	                  (mem_sel == 4'd4) ? cq : sat_q;

	// the slot in DDR3, moved over the buffer's port B as ss_ddr does
	wire        save_req, load_req, blk_hdr, blk_id;
	wire [15:0] blk_off;
	wire  [9:0] blk_len, blk_base;
	wire [31:0] hdr_words32;
	wire [63:0] dmp_q;
	reg   [9:0] dmp_addr = 0;
	reg         dmp_we = 0;
	reg  [63:0] dmp_din = 0;
	reg         xfer_ack = 0;
	reg  [63:0] ddrmodel [0:65535];
	reg  [63:0] hdrmodel = 0, idmodel = 0;
	reg   [9:0] xn = 0;
	reg   [1:0] xs = 0;
	reg   [2:0] xhold = 0;
	wire  [9:0] xlen = (blk_len == 0) ? ((ctrl.chain_len + 16'd63) >> 6) : blk_len;
	wire  [9:0] xcnt = blk_hdr ? 10'd1 : xlen;
	wire        hdr_present = |hdrmodel[63:32];
	wire [15:0] hdr_chain = (idmodel[63:32] == 32'h4D445353) ? idmodel[15:0] : 16'd0;
	always @(posedge MCLK2) begin
		dmp_we <= 0;
		if (!save_req && !load_req) begin
			xfer_ack <= 0;
			xn       <= 0;
			xs       <= 0;
			xhold    <= 0;
		end
		else if (xhold != 3'd4) xhold <= xhold + 1'b1;
		else if (!xfer_ack) begin
			if (blk_hdr) begin
				if (save_req) hdrmodel = {hdr_words32, 16'd0, 16'd1};
				xfer_ack <= 1;
			end
			else if (blk_id) begin
				if (save_req) idmodel = {32'h4D445353, 16'd0, ctrl.chain_len};
				xfer_ack <= 1;
			end
			else if (save_req) begin
				dmp_addr <= blk_base + xn;
				xs       <= xs + 1'b1;
				if (xs == 2'd2) begin
					ddrmodel[blk_off + xn] = dmp_q;
					xs <= 0;
					if (xn + 1'b1 == xcnt) xfer_ack <= 1;
					else xn <= xn + 1'b1;
				end
			end
			else begin
				dmp_addr <= blk_base + xn;
				dmp_din  <= ddrmodel[blk_off + xn];
				dmp_we   <= 1;
				if (xn + 1'b1 == xcnt) xfer_ack <= 1;
				else xn <= xn + 1'b1;
			end
		end
	end

	savestate #(.GUARD_BITS(20)) ctrl (
		.clk(MCLK2), .reset(ctrl_reset),
		.ss_save(ss_save), .ss_load(ss_load), .busy(ss_busy), .cal_busy(cal_busy),
		.cal_failed(), .chain_len(),
		.ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_out),
		.ss_en_cpu(ss_en_cpu), .ss_en_vdp_fm(ss_en_vdp_fm), .ss_en_vram(ss_en_vram),
		.bus_free(1'b1), .pause_req(),
		.bufb_clk(MCLK2), .bufb_addr(dmp_addr), .bufb_q(dmp_q),
		.bufb_we(dmp_we), .bufb_din(dmp_din),
		.save_req(save_req), .load_req(load_req), .xfer_ack(xfer_ack),
		.blk_off(blk_off), .blk_len(blk_len), .blk_base(blk_base),
		.blk_hdr(blk_hdr), .blk_id(blk_id), .hdr_words32(hdr_words32), .hdr_present(hdr_present),
		.hdr_chain(hdr_chain),
		.mem_addr(mem_addr), .mem_sel(mem_sel), .mem_din(mem_din),
		.mem_wr(mem_wr), .mem_wr_hold(), .mem_dout(mem_dout),
		.*
	);

	function [7:0] pv(input [15:0] a); pv = a[7:0] ^ a[15:8] ^ 8'h3C; endfunction
	function [7:0] peekv(input [15:0] a);
		case (a[7:5])
		0: peekv = dut.vram1.l2[0].mem.ram.mem[a[15:8]][8*a[4:0] +: 8];
		1: peekv = dut.vram1.l2[1].mem.ram.mem[a[15:8]][8*a[4:0] +: 8];
		2: peekv = dut.vram1.l2[2].mem.ram.mem[a[15:8]][8*a[4:0] +: 8];
		3: peekv = dut.vram1.l2[3].mem.ram.mem[a[15:8]][8*a[4:0] +: 8];
		4: peekv = dut.vram1.l2[4].mem.ram.mem[a[15:8]][8*a[4:0] +: 8];
		5: peekv = dut.vram1.l2[5].mem.ram.mem[a[15:8]][8*a[4:0] +: 8];
		6: peekv = dut.vram1.l2[6].mem.ram.mem[a[15:8]][8*a[4:0] +: 8];
		7: peekv = dut.vram1.l2[7].mem.ram.mem[a[15:8]][8*a[4:0] +: 8];
		endcase
	endfunction
	task pokev(input [15:0] a, input [7:0] v);
		case (a[7:5])
		0: dut.vram1.l2[0].mem.ram.mem[a[15:8]][8*a[4:0] +: 8] = v;
		1: dut.vram1.l2[1].mem.ram.mem[a[15:8]][8*a[4:0] +: 8] = v;
		2: dut.vram1.l2[2].mem.ram.mem[a[15:8]][8*a[4:0] +: 8] = v;
		3: dut.vram1.l2[3].mem.ram.mem[a[15:8]][8*a[4:0] +: 8] = v;
		4: dut.vram1.l2[4].mem.ram.mem[a[15:8]][8*a[4:0] +: 8] = v;
		5: dut.vram1.l2[5].mem.ram.mem[a[15:8]][8*a[4:0] +: 8] = v;
		6: dut.vram1.l2[6].mem.ram.mem[a[15:8]][8*a[4:0] +: 8] = v;
		7: dut.vram1.l2[7].mem.ram.mem[a[15:8]][8*a[4:0] +: 8] = v;
		endcase
	endtask

	reg  [8:0] g_cram [0:63];
	reg [10:0] g_vsram [0:39];
	reg [20:0] g_sat [0:79];
	integer n, k, nvr, ncr, nvs, nsa;
	reg [15:0] aa;

	task poke_all;
		begin
			for (n = 0; n < 65536; n = n + 1) begin aa = n; pokev(aa, pv(aa)); end
			for (n = 0; n < 64; n = n + 1) begin g_cram[n] = (n*7+1) & 9'h1FF; dut.ym.vdp.color_ram[n] = g_cram[n]; end
			for (n = 0; n < 40; n = n + 1) begin g_vsram[n] = (n*13+3) & 11'h7FF; dut.ym.vdp.vsram[n] = g_vsram[n]; end
			for (n = 0; n < 80; n = n + 1) begin g_sat[n] = 21'h100000 + n; dut.ym.vdp.sat[n] = g_sat[n]; end
		end
	endtask
	task compare_all(input [8*12:1] tag);
		begin
			nvr = 0; ncr = 0; nvs = 0; nsa = 0;
			for (n = 0; n < 65536; n = n + 1) begin aa = n; if (peekv(aa) !== pv(aa)) begin if (nvr < 3) $display("  %0s vram[%h]=%h want %h", tag, aa, peekv(aa), pv(aa)); nvr = nvr + 1; end end
			for (n = 0; n < 64; n = n + 1) if (dut.ym.vdp.color_ram[n] !== g_cram[n]) begin if (ncr < 3) $display("  %0s cram[%0d]=%h want %h", tag, n, dut.ym.vdp.color_ram[n], g_cram[n]); ncr = ncr + 1; end
			for (n = 0; n < 40; n = n + 1) if (dut.ym.vdp.vsram[n] !== g_vsram[n]) begin if (nvs < 3) $display("  %0s vsram[%0d]=%h want %h", tag, n, dut.ym.vdp.vsram[n], g_vsram[n]); nvs = nvs + 1; end
			for (n = 0; n < 80; n = n + 1) if (dut.ym.vdp.sat[n] !== g_sat[n]) begin if (nsa < 3) $display("  %0s sat[%0d]=%h want %h", tag, n, dut.ym.vdp.sat[n], g_sat[n]); nsa = nsa + 1; end
			$display("COMPARE %0s: vram diffs %0d, cram %0d, vsram %0d, sat %0d", tag, nvr, ncr, nvs, nsa);
		end
	endtask

	// the VDP's own write strobes while the load walks the memories: a case only
	// counts if the DMA it starts is still writing its target then
	wire in_walk = ss_busy & ctrl.loading & ((ctrl.state == 5'd14) | (ctrl.state == 5'd15));
	integer try_vram = 0, try_cram = 0, try_vsram = 0, try_sat = 0;
	always @(posedge MCLK2) if (in_walk) begin
		if (dut.vram1.wr) try_vram = try_vram + 1;
		if (dut.ym.vdp.hclk1 & (dut.ym.vdp.l601 | dut.ym.vdp.l602)) try_cram = try_cram + 1;
		if (dut.ym.vdp.hclk1 & (dut.ym.vdp.l210 | dut.ym.vdp.l211)) try_vsram = try_vsram + 1;
		if (dut.ym.vdp.hclk1 & (dut.ym.vdp.w687 | dut.ym.vdp.w688 | dut.ym.vdp.w689 | dut.ym.vdp.w690)) try_sat = try_sat + 1;
	end

	task req(input is_save);
		begin
			@(negedge MCLK2); if (is_save) ss_save = 1; else ss_load = 1;
			repeat (4) @(negedge MCLK2); ss_save = 0; ss_load = 0;
			k = 0;
			while (!ss_busy && k < 1000) begin @(posedge MCLK2); k = k + 1; end
			if (!ss_busy) begin $display("RESULT: FAIL - request not accepted"); $finish; end
			k = 0;
			while (ss_busy && k < 3000000) begin @(posedge MCLK2); k = k + 1; end
			if (ss_busy) begin $display("RESULT: FAIL - request never finished"); $finish; end
		end
	endtask

	// mode 0: VRAM fill, increment 1; 1: VRAM fill at the sprite table, increment 0;
	// 2: CRAM fill; 3: VSRAM fill
	integer mode = 0, tries;
	reg [8*6:1] name;
	initial begin
		if (!$value$plusargs("mode=%d", mode)) mode = 0;
		name = (mode == 0) ? "VRAM" : (mode == 1) ? "SAT" : (mode == 2) ? "CRAM" : "VSRAM";
		for (i = 0; i < 4096; i = i + 1) rom[i] = 16'h4E71;
		rom[0] = 16'h0000; rom[1] = 16'hFFFE; rom[2] = 16'h0000; rom[3] = 16'h0200;
		// wait for the word at 0x1E00, then set up and start a fill DMA
		rom[16'h100] = 16'h4A78; rom[16'h101] = 16'h1E00; rom[16'h102] = 16'h67FA;
		// mode 5 first: the VDP ignores registers above 10 in mode 4
		rom[16'h103] = 16'h33FC; rom[16'h104] = 16'h8154;                         rom[16'h105] = 16'h00C0; rom[16'h106] = 16'h0004;
		rom[16'h107] = 16'h33FC; rom[16'h108] = (mode == 0) ? 16'h8F01 : 16'h8F00; rom[16'h109] = 16'h00C0; rom[16'h10A] = 16'h0004;
		rom[16'h10B] = 16'h33FC; rom[16'h10C] = 16'h9780; rom[16'h10D] = 16'h00C0; rom[16'h10E] = 16'h0004;
		rom[16'h10F] = 16'h33FC; rom[16'h110] = 16'h93FF; rom[16'h111] = 16'h00C0; rom[16'h112] = 16'h0004;
		rom[16'h113] = 16'h33FC; rom[16'h114] = 16'h94FF; rom[16'h115] = 16'h00C0; rom[16'h116] = 16'h0004;
		rom[16'h117] = 16'h23FC;
		rom[16'h118] = (mode == 2) ? 16'hC000 : 16'h4000;
		rom[16'h119] = (mode == 3) ? 16'h0090 : 16'h0080;
		rom[16'h11A] = 16'h00C0; rom[16'h11B] = 16'h0004;
		rom[16'h11C] = 16'h33FC; rom[16'h11D] = 16'hABAB; rom[16'h11E] = 16'h00C0; rom[16'h11F] = 16'h0000;
		rom[16'h120] = 16'h5200; rom[16'h121] = 16'h60FC;
		rom[16'hF00] = 16'h0000;
		$display("MODE %0d %0s", mode, name);

		repeat (200) @(posedge MCLK2);
		ctrl_reset = 0;
		while (cal_busy) @(posedge MCLK2);
		repeat (200) @(posedge MCLK2);
		ext_reset = 0; ext_vres = 0; ext_zres = 0;
		repeat (BOOT) @(posedge MCLK2);
		$display("chain %0d", ctrl.chain_len);

		// known content, saved with nothing in flight
		@(negedge MCLK2); poke_all;
		req(1);
		compare_all("after save");
		if (nvr + ncr + nvs + nsa != 0) begin $display("RESULT: FAIL - %0s: the save itself changed a memory", name); $finish; end

		// a fill DMA takes no bus, so it keeps running through the load's pause
		rom[16'hF00] = 16'h0001;
		repeat (40000) @(posedge MCLK2);
		rom[16'hF00] = 16'h0000;
		req(0);
		$display("VDP write strobes during the load walk: vram %0d, cram %0d, vsram %0d, sat %0d", try_vram, try_cram, try_vsram, try_sat);
		compare_all("after load");
		tries = (mode == 0) ? try_vram : (mode == 1) ? try_sat : (mode == 2) ? try_cram : try_vsram;
		if (tries == 0)
			$display("RESULT: FAIL - %0s: the fill was not writing during the load walk", name);
		else if (nvr + ncr + nvs + nsa != 0)
			$display("RESULT: FAIL - %0s: a VDP write during the load walk survives the restore", name);
		else
			$display("RESULT: PASS - %0s: the load restores every memory over a running fill", name);
		$finish;
	end
endmodule
