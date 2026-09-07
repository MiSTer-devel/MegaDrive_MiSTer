// Exercises the savestate controller against the real core, which is what the
// chain tests never did: they drove ss_en by hand. Here the controller drives
// it, so calibration, the shift count and the release are all under test.
//
// The bar is simple and matches what the hardware showed us: after a snapshot
// the machine must still be running. A core that stops fetching is a core that
// stopped generating video, which on a TV looks like snow.
`timescale 1ns/1ps

module tb_ctrl;
	parameter BOOT = 1500000;

	reg MCLK2 = 0; always #4.657 MCLK2 = ~MCLK2;
	reg ext_reset = 1, ext_vres = 1, ext_zres = 1;

	// the controller has its own reset in the real core (sys_reset), separate
	// from the machine reset it holds down during calibration. tying them
	// together here deadlocks: the controller never starts measuring.
	reg ctrl_reset = 1;

	wire ss_en, ss_in, ss_out, ss_busy;
	wire ss_en_cpu, ss_en_vdp_fm, ss_en_vram;
	// Check both enable edges after nonblocking updates, on every controller cycle.
	always @(negedge MCLK2)
		if ({ss_en_cpu, ss_en_vdp_fm, ss_en_vram} !== {3{ss_en}})
			$fatal(1, "scan enable replicas differ");
	wire cal_busy;
	reg  ss_save = 0, ss_load = 0;

	wire [14:0] ra; wire [1:0] rb; wire [15:0] rd, ro; wire rw;
	wire [12:0] za; wire [7:0] zd, zo; wire zw;
	wire [22:0] ca; wire [9:0] ta;
	wire cart_cs;

	reg [15:0] rom [0:4095]; integer i;
	wire [15:0] blk_off;
	wire  [9:0] blk_len;
	wire  [9:0] blk_base;
	wire [15:0] mem_addr, mem_din;
	wire        mem_wr, mem_wr_hold;
	wire [15:0] mem_dout;
	wire  [3:0] mem_sel;
	wire [15:0] ss_wq;
	wire  [7:0] ss_zq;
	wire [15:0] arr_q;
	wire [15:0] cart_q;
	reg  [15:0] cartmodel [0:15];
	integer ci;
	initial for (ci = 0; ci < 16; ci = ci + 1) cartmodel[ci] = ci * 16'h1111 + 16'h37;
	reg [15:0] cq = 0;
	always @(posedge MCLK2) begin
		if (mem_wr && mem_sel == 4'd4) cartmodel[mem_addr[3:0]] <= mem_din;
		cq <= cartmodel[mem_addr[3:0]];
	end
	assign cart_q = cq;

	// The cartridge is the one savestate memory that does not run on the
	// controller's clock: it is on clk_sys, half of clk_md, both rising together
	// out of the same PLL. A write pulse one clock wide at 107 MHz therefore
	// lands between two 53.69 MHz edges whenever it starts on an even clock, and
	// which words start on an even clock is fixed by the walk, so the same half
	// of the cartridge vector was dropped on every restore. This model samples
	// the same stream on the slow clock and has to end up with what the fast one
	// has.
	reg clk53 = 0;
	initial begin
		#4.657;
		forever begin clk53 = 1; #9.314; clk53 = 0; #9.314; end
	end
	reg [15:0] cart_slow [0:15];
	integer cs_i;
	initial for (cs_i = 0; cs_i < 16; cs_i = cs_i + 1) cart_slow[cs_i] = 16'hDEAD;
	always @(posedge clk53)
		if (mem_wr_hold && mem_sel == 4'd4) cart_slow[mem_addr[3:0]] <= mem_din;
	reg   [9:0] dmp_addr = 0;
	wire [63:0] dmp_q;
	reg         dmp_we = 0;
	reg  [63:0] dmp_din = 0;
	// nothing may be written to a memory while the chain is shifting. the flops
	// all come back exactly, but the memories are not in the chain, so a stray
	// write survives the restore and the game dies on it seconds later.
	integer wr_during_scan = 0;
	always @(posedge MCLK2) if (ss_en) begin
		if (rw) wr_during_scan = wr_during_scan + 1;
		if (zw) wr_during_scan = wr_during_scan + 1;
	end

	// The VDP arrays cannot be checked from here: iverilog will not bind a
	// hierarchical reference into a memory, with a variable index or a constant one.
	// They are guarded structurally instead - tools/gen_scan.sh refuses to write RTL
	// in which an always block that assigns to an array is not wrapped in
	// if (ss_en) - which is a stronger check than a simulation that only ever sees
	// one machine state.

	initial begin
		for (i=0;i<4096;i=i+1) rom[i]=16'h4E71;
		rom[0]=16'h0000; rom[1]=16'hFFFE; rom[2]=16'h0000; rom[3]=16'h0200;
		rom[16'h100]=16'h5200; rom[16'h101]=16'h60FC;
	end
	wire [15:0] cart_data = rom[ca[11:0]];

	md_board #(.SS_EN_SPLIT(1)) dut (
		.MCLK2(MCLK2), .ext_reset(ext_reset), .reset_button(1'b0),
		.ext_vres(ext_vres), .ext_zres(ext_zres),
		.ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_out),
		.ss_en_cpu(ss_en_cpu), .ss_en_vdp_fm(ss_en_vdp_fm), .ss_en_vram(ss_en_vram),
		.ss_arr_sel(mem_sel == 4'd3), .ss_arr_addr(mem_addr), .ss_arr_din(mem_din),
		.ss_arr_wr(mem_wr & (mem_sel == 4'd3)), .ss_arr_dout(arr_q),
		.ss_mem_sel(mem_sel == 4'd2), .ss_mem_addr(mem_addr),
		.ss_mem_din(mem_din[7:0]), .ss_mem_wr(mem_wr & (mem_sel == 4'd2)),
		.ss_mem_dout(),
		.ram_68k_address(ra), .ram_68k_byteena(rb), .ram_68k_data(rd), .ram_68k_wren(rw), .ram_68k_o(ro),
		.ram_z80_address(za), .ram_z80_data(zd), .ram_z80_wren(zw), .ram_z80_o(zo),
		.M3(1'b1), .cart_data(cart_data), .cart_data_en(1'b1),
		.cart_address(ca), .cart_cs(cart_cs), .cart_oe(), .cart_lwr(), .cart_uwr(),
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
		.address_b(mem_addr[14:0]), .data_b(mem_din),
		.wren_b(mem_wr & (mem_sel == 4'd0)), .byteena_b(2'b11), .q_b(ss_wq));
	dpram #(13,8) rz (.clock(MCLK2), .address_a(za), .data_a(zd), .wren_a(zw), .byteena_a(1'b1), .q_a(zo),
		.address_b(mem_addr[12:0]), .data_b(mem_din[7:0]),
		.wren_b(mem_wr & (mem_sel == 4'd1)), .byteena_b(1'b1), .q_b(ss_zq));

	// VRAM stands in as a plain byte memory here: the real one shares the machine's
	// single port, which this bench has no way to exercise, but the walk over it is
	// the same and that is what is under test.
	reg [7:0] vmodel [0:65535];
	reg [7:0] vq = 0;
	integer vi;
	// filled with a pattern so the data comparison bites: the other two models are
	// dpram instances this bench cannot preload, and an x on both sides compares
	// equal, which makes their data check vacuous.
	initial for (vi = 0; vi < 65536; vi = vi + 1) vmodel[vi] = vi[7:0] ^ 8'hA5;
	always @(posedge MCLK2) begin
		if (mem_wr && mem_sel == 4'd2) vmodel[mem_addr] <= mem_din[7:0];
		vq <= vmodel[mem_addr];
	end

	// the VDP's palette and scroll answer through the real ym7101 port, so this
	// one is not a model: it reads what the chip holds. Only 104 of the 1024 words
	// in its window mean anything, the rest read zero and go nowhere, and both
	// sides see the same thing, so the comparison stays honest.
	assign mem_dout = (mem_sel == 4'd0) ? ss_wq :
	                  (mem_sel == 4'd1) ? {8'd0, ss_zq} :
	                  (mem_sel == 4'd2) ? {8'd0, vq} :
	                  (mem_sel == 4'd3) ? arr_q : cart_q;

	// stand in for ss_ddr: answer either request after a while and hold the ack
	// up until the request drops, which is the handshake the real module uses. it
	// deliberately leaves the buffer alone, so a restore here replays whatever the
	// last capture put there - which is what makes the check below meaningful.
	wire save_req, load_req;
	wire blk_hdr;
	wire [31:0] hdr_words32;
	reg  xfer_ack = 0;
	integer saw_save_req = 0, saw_load_req = 0;
	always @(posedge MCLK2) begin
		if (save_req) saw_save_req = saw_save_req + 1;
		if (load_req) saw_load_req = saw_load_req + 1;
	end
	// a model of the slot in DDR3, and a walk over the buffer's port B that moves
	// a block either way. answering a request without moving anything would let a
	// restore replay the capture that is still sitting in the buffer and pass a
	// test it never earned.
	reg [63:0] ddrmodel [0:65535];
	reg [63:0] hdrmodel = 0;         // slot word 0, the header main polls
	reg  [9:0] xn = 0;
	reg  [1:0] xs = 0;
	wire [9:0] xlen  = (blk_len == 0) ? ((ctrl.chain_len + 16'd63) >> 6) : blk_len;
	wire [9:0] xcnt  = blk_hdr ? 10'd1 : xlen;
	// main zeroes a slot it has no file for, so a size of zero is what an empty
	// slot looks like. this one has a state in it.
	wire       hdr_present = |hdrmodel[63:32];
	integer    hdr_writes = 0, hdr_reads = 0;
	reg [63:0] hdr_written = 0;
	// ss_ddr is on the other clock and answers through a synchroniser, so a
	// request that is dropped again after a clock or two never reaches it. The
	// model used to act on the first clock of a request, which made a stale
	// acknowledge invisible here and let the header write pass in simulation
	// while doing nothing at all on the board.
	reg [2:0] xhold = 0;
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
			if (save_req && blk_hdr) begin
				hdrmodel    = {hdr_words32, 32'd1};
				hdr_written = hdrmodel;
				hdr_writes  = hdr_writes + 1;
				xfer_ack   <= 1;
			end
			else if (load_req && blk_hdr) begin
				hdr_reads <= hdr_reads + 1;
				xfer_ack  <= 1;
			end
			else if (save_req) begin
				// two clocks for the buffer to answer, then take the word
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

	// port B of the buffer, so the bench can read back what the controller stored
	// and stand in for the transfers ss_ddr would do


	// what the save read out of the memory, and what the restore wrote back. the
	// restore has to touch the same addresses in the same order with the same
	// values: that covers the address arithmetic, the packing into 64-bit words
	// and the two-clock latency of the block RAM in one comparison.
	reg [19:0] sav_a [0:131071];
	reg [15:0] sav_d [0:131071];
	reg [19:0] ld_a  [0:131071];
	reg [15:0] ld_d  [0:131071];
	integer    sav_n = 0, ld_n = 0;
	always @(posedge MCLK2) begin
		if (ctrl.state == 5'd12 && ctrl.mrd == 2'd2) begin
			sav_a[sav_n] = {mem_sel, mem_addr};
			sav_d[sav_n] = mem_dout;
			sav_n = sav_n + 1;
		end
		if (mem_wr) begin
			ld_a[ld_n] = {mem_sel, mem_addr};
			ld_d[ld_n] = mem_din;
			ld_n = ld_n + 1;
		end
	end

	// every bit the controller pushes into the chain during a restore, in order.
	// the chain samples ss_in on the clock after ST_IN drives it, so the value is
	// recorded one cycle late on purpose.
	reg  [3:0] st_d = 0;
	// sized well past any chain this will ever measure. at 16383 it silently
	// dropped everything past bit 16384 and the comparison called it a
	// mismatch, which reads exactly like a broken restore.
	reg        instream [0:65535];
	integer    in_n = 0;
	always @(posedge MCLK2) begin
		st_d <= ctrl.state;
		if (st_d == 4'd5) begin
			instream[in_n] = ss_in;
			in_n = in_n + 1;
		end
	end

	savestate ctrl (
		.clk(MCLK2), .reset(ctrl_reset),
		.ss_save(ss_save), .ss_load(ss_load), .busy(ss_busy), .cal_busy(cal_busy),
		.ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_out),
		.ss_en_cpu(ss_en_cpu), .ss_en_vdp_fm(ss_en_vdp_fm), .ss_en_vram(ss_en_vram),
		.bus_free(1'b1),
		.pause_req(),
		.bufb_clk(MCLK2), .bufb_addr(dmp_addr), .bufb_q(dmp_q),
		.bufb_we(dmp_we), .bufb_din(dmp_din),
		.save_req(save_req), .load_req(load_req), .xfer_ack(xfer_ack),
		.blk_off(blk_off), .blk_len(blk_len), .blk_base(blk_base),
		.blk_hdr(blk_hdr), .hdr_words32(hdr_words32), .hdr_present(hdr_present),
		.mem_addr(mem_addr), .mem_sel(mem_sel), .mem_din(mem_din),
		.mem_wr(mem_wr), .mem_wr_hold(mem_wr_hold), .mem_dout(mem_dout)
	);

	// The first transfer of a restore has to be the chain: offset 0 in the slot,
	// length 0 (which ss_ddr reads as "the measured chain length"), into buffer
	// word 0. It used to be whatever descriptor the previous operation left
	// behind - after a save, the last memory chunk at offset 28672 into buffer
	// word 512 - so the chain was never fetched at all and the shift ran on
	// whatever the last save had left in the bottom of the buffer. Restoring the
	// slot you had just saved worked by accident; restoring any other one put
	// that slot's memories under the other slot's registers.
	reg     ld_seen = 0;
	reg     old_ldreq = 0;
	integer ld_errors = 0;
	reg     ld_hdr_first = 0;

	// The cartridge puts its bank registers back when its select line drops, so
	// the walk has to let go of the memories before the machine resumes - not
	// after, which is what made Super Street Fighter II fetch a few instructions
	// from the wrong half of its ROM and die. Checked where the chain shift
	// starts: everything after that is the shift itself, sixteen thousand clocks
	// of it, and the machine is still frozen for all of them.
	reg [4:0] st_prev = 0;
	always @(posedge MCLK2) begin
		st_prev <= ctrl.state;
		if (st_prev != 5'd5 && ctrl.state == 5'd5 && ctrl.loading && mem_sel == 4'd4) begin
			$display("FAIL: the chain goes in with the cartridge still selected");
			ld_errors = ld_errors + 1;
		end
	end
	always @(posedge MCLK2) begin
		old_ldreq <= load_req;
		if (!old_ldreq && load_req && !ld_seen) begin
			// the first transfer of a restore is the header, the second is the chain
			if (blk_hdr) ld_hdr_first = 1;
			else begin
				ld_seen = 1;
				$display("restore, first payload transfer: off=%0d len=%0d base=%0d",
				         blk_off, blk_len, blk_base);
				if (blk_off !== 16'd0 || blk_len !== 10'd0 || blk_base !== 10'd0) begin
					$display("FAIL: a restore must fetch its chain first, from 0/0/0");
					ld_errors = ld_errors + 1;
				end
			end
		end
	end

	// the hardware counter measures work-RAM writes, so the bench has to show the
	// same signal actually moves before that number means anything on the board.
	integer rw_before = 0;
	reg rw_d = 0;
	always @(posedge MCLK2) begin
		rw_d <= rw;
		if (rw && !rw_d && !ss_busy) rw_before = rw_before + 1;
	end

	integer acc_before = 0, acc_during = 0, acc_after = 0, k;
	integer bad;
	integer lastbad = -1;
	reg [15:0] b;
	reg cs_d = 1;
	always @(posedge MCLK2) begin
		cs_d <= cart_cs;
		if (cs_d && !cart_cs) begin
			if (!ss_busy && acc_after == 0 && ss_save === 1'b0 && acc_during == 0) acc_before = acc_before + 1;
			else if (ss_busy) acc_during = acc_during + 1;
			else acc_after = acc_after + 1;
		end
	end

	initial begin
		// the real core holds reset until calibration finishes, because the
		// measurement shifts the whole machine state out. release it the same way
		// here, otherwise this test never exercises the boot that hardware does.
		repeat (200) @(posedge MCLK2);
		ctrl_reset = 0;
		while (cal_busy) @(posedge MCLK2);
		repeat (200) @(posedge MCLK2);
		ext_reset = 0; ext_vres = 0; ext_zres = 0;
		$display("calibration finished before reset release");

		repeat (BOOT) @(posedge MCLK2);
		$display("calibrated chain length : %0d", ctrl.chain_len);
		$display("calibrated flag         : %0d", ctrl.calibrated);
		acc_before = 0; rw_before = 0;
		repeat (20000) @(posedge MCLK2);
		$display("bus cycles before save  : %0d", acc_before);

		$display("work-RAM writes in that window: %0d", rw_before);
		$display("state before save       : %0d busy=%0b", ctrl.state, ss_busy);
		// drive the request off the falling edge. driving it on the rising edge is a
		// race with the controller sampling it there, and the request was silently
		// lost: the snapshot never started and every counter below then read zero,
		// which looks exactly like a snapshot that did nothing wrong.
		@(negedge MCLK2); ss_save = 1;
		repeat (4) @(negedge MCLK2); ss_save = 0;
		k = 0;
		while (!ss_busy && k < 1000) begin @(posedge MCLK2); k = k + 1; end
		if (!ss_busy) begin
			$display("RESULT: FAIL - the controller never accepted the request");
			$finish;
		end
		k = 0;
		while (ss_busy && k < 2000000) begin @(posedge MCLK2); k = k + 1; end
		$display("snapshot took           : %0d cycles", k);
		if (ss_busy) begin
			$display("RESULT: FAIL - controller never released, machine stays frozen");
			$finish;
		end

		acc_after = 0;
		repeat (20000) @(posedge MCLK2);
		$display("bus cycles after save   : %0d", acc_after);
		$display("save_req asserted for: %0d clocks (must be > 0 and finished)", saw_save_req);
		if (saw_save_req == 0 || save_req) begin
			$display("RESULT: FAIL - the snapshot never asked for its slot, or never let go");
			$finish;
		end
		$display("memory writes while scanning: %0d (must be 0)", wr_during_scan);
		if (wr_during_scan != 0) begin
			$display("RESULT: FAIL - a memory was written while the chain was shifting");
			$finish;
		end

		// a machine that resumed correctly should run at the same rate as
		// before. a large drop means the restored state is subtly wrong even
		// though the core has not stopped outright.
		if (acc_after * 4 < acc_before) begin
			$display("RESULT: FAIL - machine runs %0dx slower after the snapshot", acc_before/acc_after);
			$finish;
		end

		if (acc_after == 0) begin
			$display("RESULT: FAIL - machine stopped after the snapshot");
			$finish;
		end
		$display("RESULT: PASS - machine still running after the snapshot");

		// restore. the stand-in answers the fetch without touching the buffer, so
		// what gets shifted in is the capture that is still sitting there, and the
		// bit stream on ss_in has to match it word for word.
		in_n = 0;
		@(negedge MCLK2); ss_load = 1;
		repeat (4) @(negedge MCLK2); ss_load = 0;
		k = 0;
		while (!ss_busy && k < 1000) begin @(posedge MCLK2); k = k + 1; end
		if (!ss_busy) begin
			$display("RESULT: FAIL - the restore was never accepted");
			$finish;
		end
		k = 0;
		while (ss_busy && k < 2000000) begin @(posedge MCLK2); k = k + 1; end
		$display("restore took            : %0d cycles", k);
		$display("load_req asserted for   : %0d clocks", saw_load_req);
		$display("bits shifted in         : %0d (expect %0d)", in_n, ctrl.chain_len);

		bad = 0;
		for (b = 0; b < ctrl.chain_len; b = b + 1) begin
			if (b[5:0] == 0) begin
				dmp_addr = b >> 6;
				@(posedge MCLK2); @(posedge MCLK2);
			end
			if (instream[b] !== dmp_q[63 - b[5:0]]) begin
				if (bad < 12) $display("  mismatch at bit %0d (word %0d, bit %0d)", b, b >> 6, 63 - b[5:0]);
				bad = bad + 1;
				lastbad = b;
			end
		end
		$display("bits not matching buffer: %0d, last at %0d of %0d", bad, lastbad, ctrl.chain_len);
		if (!(saw_load_req > 0 && in_n == ctrl.chain_len && bad == 0)) begin
			$display("RESULT: FAIL - the restore does not replay the buffer");
			$finish;
		end
		$display("RESULT: PASS - the restore shifts the buffer back in, in order");

		bad = 0;
		for (i = 0; i < 16; i = i + 1)
			if (cart_slow[i] !== cartmodel[i]) begin
				if (bad < 8) $display("  cartridge word %0d: on clk_md %h, on clk_sys %h", i, cartmodel[i], cart_slow[i]);
				bad = bad + 1;
			end
		$display("cartridge words lost across the clocks: %0d of 16", bad);
		if (bad != 0) begin
			$display("RESULT: FAIL - the cartridge vector does not survive the clock crossing");
			$finish;
		end

		$display("memory words read on save : %0d (expect 108544)", sav_n);
		$display("memory words written back : %0d (expect 108544)", ld_n);
		for (i = 0; i < 4; i = i + 1)
			$display("  save[%0d] sel=%0h addr=%0h data=%0h   load[%0d] sel=%0h addr=%0h data=%0h",
				i, sav_a[i][19:16], sav_a[i][15:0], sav_d[i],
				i, ld_a[i][19:16], ld_a[i][15:0], ld_d[i]);
		$display("  last save entry: sel=%0h addr=%0h", sav_a[sav_n-1][19:16], sav_a[sav_n-1][15:0]);
		$display("  last load entry: sel=%0h addr=%0h", ld_a[ld_n-1][19:16], ld_a[ld_n-1][15:0]);
		bad = 0;
		for (i = 0; i < sav_n && i < ld_n; i = i + 1) begin
			if (sav_a[i] !== ld_a[i]) begin
				if (bad < 3) $display("  first addr mismatch at %0d: save %0h load %0h", i, sav_a[i], ld_a[i]);
				bad = bad + 1;
			end
			else if (sav_d[i] !== ld_d[i]) begin
				if (bad < 3) $display("  first data mismatch at %0d: save %0h load %0h", i, sav_d[i], ld_d[i]);
				bad = bad + 1;
			end
		end
		$display("addresses or values differing: %0d", bad);
		if (!ld_seen) begin
			$display("FAIL: no restore transfer was ever requested");
			ld_errors = ld_errors + 1;
		end
		// main only writes a file when the change detector moves, and only ever
		// reads a size out of the header, so both halves have to be there
		$display("header: %0d written, %0d read, value %h (size %0d words of 32 bits)",
		         hdr_writes, hdr_reads, hdr_written, hdr_written[63:32]);
		if (hdr_writes != 1) begin
			$display("FAIL: a save must write the header exactly once");
			ld_errors = ld_errors + 1;
		end
		if (!ld_hdr_first) begin
			$display("FAIL: a restore must read the header before anything else");
			ld_errors = ld_errors + 1;
		end
		// the payload is 28928 words of 64 bits; main counts in 32-bit words
		if (hdr_written[63:32] !== 32'd57856) begin
			$display("FAIL: header size is %0d, expected 57856", hdr_written[63:32]);
			ld_errors = ld_errors + 1;
		end
		if (sav_n == 108544 && ld_n == 108544 && bad == 0 && ld_errors == 0)
			$display("RESULT: PASS - every memory goes out and comes back word for word");
		else
			$display("RESULT: FAIL - the memory walk does not round trip");
		$finish;
	end
endmodule
