// rtl/md_reset.sv, driven through the loop that broke v43.
//
// The device under test is the shipped module, not a copy: the copy is how this
// went wrong once already. md_reset_v43 below is a deliberate copy of the broken
// version, kept so the bench has to fail on something. A bench that does not
// reproduce the fault proves nothing about the fix.
//
// The loop: s_reset feeds sys_reset, sys_reset resets the savestate controller,
// and a reset controller calibrates again. Anything the machine's own controller
// can trigger that reaches sys_reset runs forever.
`timescale 1ns/1ps

// v43, for the control run. Two counters collapsed into one, and md_reset with a
// path to zero and none to one.
module md_reset_v43 #(parameter DIV = 15)
(
	input                clk,
	input                loading,
	input                reset,
	input                cal_busy,
	output reg           md_reset  = 0,
	output reg           s_reset   = 1,
	output reg           btn_reset = 0,
	output reg [DIV:1]   ram_rst_a = 0
);
	reg [4:0] cnt = 0;
	reg       old_reset = 0;
	reg       old_cal = 1;

	always @(posedge clk) begin
		ram_rst_a <= ram_rst_a + 1'd1;
		if(&ram_rst_a & ~&cnt) cnt <= cnt + 1'd1;

		old_reset <= reset;
		if(loading | (~old_reset & reset)) cnt <= 0;

		old_cal <= cal_busy;
		if(old_cal & ~cal_busy) cnt <= 0;

		s_reset <= (cnt < 3);

		if(loading | cal_busy) md_reset <= 1;
		else if(cnt >= 3)      md_reset <= 0;

		if(~old_reset & reset) btn_reset <= 1;
		else if(&cnt)          btn_reset <= 0;
	end
endmodule

// One instance of the block, the sys_reset it drives, and the savestate
// controller that sys_reset resets. VER 0 is the shipped module, 1 is v43.
module rig #(parameter VER = 0, parameter DIV = 4, parameter CAL_LEN = 100)
(
	input      clk,
	input      loading,
	input      reset,
	output     md_reset,
	output     s_reset,
	output     btn_reset,
	output reg cal_busy = 1,
	output reg sys_reset = 1,
	output integer cals = 0
);
	wire [DIV:1] ram_rst_a;

	generate
		if (VER == 0)
			md_reset #(.DIV(DIV)) dut
				(.clk(clk), .loading(loading), .reset(reset), .cal_busy(cal_busy),
				 .md_reset(md_reset), .s_reset(s_reset), .btn_reset(btn_reset),
				 .ram_rst_a(ram_rst_a));
		else
			md_reset_v43 #(.DIV(DIV)) dut
				(.clk(clk), .loading(loading), .reset(reset), .cal_busy(cal_busy),
				 .md_reset(md_reset), .s_reset(s_reset), .btn_reset(btn_reset),
				 .ram_rst_a(ram_rst_a));
	endgenerate

	// sys_reset exactly as MegaDrive.sv builds it, on clk_sys there and on this
	// clock here: the two-stage filter is what matters, not the clock ratio
	reg [1:0] sreset = 3;
	reg [15:0] caltimer = 0;

	always @(posedge clk) begin
		sreset <= {sreset[0], s_reset};
		if(!sreset) sys_reset <= 0;
		if(&sreset) sys_reset <= 1;

		// the savestate controller: calibrated is cleared by its reset, and the
		// measurement then runs again from the top
		if (sys_reset) begin
			cal_busy <= 1;
			caltimer <= 0;
		end
		else if (cal_busy) begin
			caltimer <= caltimer + 1'd1;
			if (caltimer == CAL_LEN) begin
				cal_busy <= 0;
				cals = cals + 1;
			end
		end
	end
endmodule

module tb_reset;
	parameter DIV = 4;
	parameter CAL_LEN = 100;
	localparam TICK = 1 << DIV;           // clocks per ram_rst_a wrap
	// cal_cnt counts three ticks of a divider that never stops, so the window it
	// opens is between two and three full passes depending on the phase the
	// divider was in when calibration finished. Two is the guarantee: one full
	// pass of ram_rst_a is what clears the RAMs.
	localparam WINDOW = TICK * 2;

	reg clk = 0;
	always #1 clk = ~clk;

	reg loading = 0, reset = 0;

	wire md_new, s_new, btn_new, cal_new, sys_new;
	wire md_old, s_old, btn_old, cal_old, sys_old;
	integer cals_new, cals_old;

	rig #(.VER(0), .DIV(DIV), .CAL_LEN(CAL_LEN)) r_new
		(.clk(clk), .loading(loading), .reset(reset), .md_reset(md_new),
		 .s_reset(s_new), .btn_reset(btn_new), .cal_busy(cal_new),
		 .sys_reset(sys_new), .cals(cals_new));
	rig #(.VER(1), .DIV(DIV), .CAL_LEN(CAL_LEN)) r_old
		(.clk(clk), .loading(loading), .reset(reset), .md_reset(md_old),
		 .s_reset(s_old), .btn_reset(btn_old), .cal_busy(cal_old),
		 .sys_reset(sys_old), .cals(cals_old));

	integer errors = 0;
	task fail(input [1023:0] msg);
		begin
			$display("FAIL: %0s", msg);
			errors = errors + 1;
		end
	endtask

	// 1. the machine is never running while the chain is being shifted
	always @(posedge clk)
		if (cal_new && !md_new) fail("machine released while cal_busy is high");

	// 2. the machine is held for the whole window after calibration lets go
	reg old_cal_new = 1;
	integer window = 0;
	always @(posedge clk) begin
		old_cal_new <= cal_new;
		if (old_cal_new & ~cal_new) window = WINDOW;
		else if (window > 0) begin
			window = window - 1;
			if (!md_new) fail("machine released inside its post-calibration window");
		end
	end

	// 3. sys_reset only ever comes back for a reason the core asked for. anything
	//    else is the v43 loop. a two-clock grace covers the filter's own delay.
	reg old_sys_new = 1;
	integer allow_sys = 0;
	always @(posedge clk) begin
		old_sys_new <= sys_new;
		if (loading | reset) allow_sys = WINDOW + TICK + 8;
		else if (allow_sys > 0) allow_sys = allow_sys - 1;
		if (~old_sys_new & sys_new & (allow_sys == 0))
			fail("sys_reset re-asserted with nothing asking for it");
	end

	// 4. once the machine is running, it keeps running
	reg old_md_new = 1;
	integer allow_md = 0;
	always @(posedge clk) begin
		old_md_new <= md_new;
		if (loading | reset) allow_md = WINDOW * 4 + CAL_LEN * 2 + TICK + 8;
		else if (allow_md > 0) allow_md = allow_md - 1;
		if (~old_md_new & md_new & (allow_md == 0))
			fail("machine reset again with nothing asking for it");
	end

	integer cals_at_boot, cals_after_load, cals_after_btn;

	initial begin
		// --- boot with no cartridge -------------------------------------------
		repeat (WINDOW * 2 + CAL_LEN * 3 + 200) @(posedge clk);
		cals_at_boot = cals_new;
		if (cals_new != 1) fail("boot did not calibrate exactly once");
		if (md_new)  fail("machine still held long after boot");
		if (sys_new) fail("core still held long after boot");
		$display("boot:   calibrations=%0d md_reset=%0b sys_reset=%0b", cals_new, md_new, sys_new);

		// --- a ROM is loaded ---------------------------------------------------
		// loading restarts cnt on purpose: the whole core is meant to be reset
		// around a cartridge change, and calibration runs again with it
		@(negedge clk) loading = 1;
		repeat (TICK * 2) @(posedge clk);
		@(negedge clk) loading = 0;
		repeat (WINDOW * 3 + CAL_LEN * 3 + 400) @(posedge clk);
		cals_after_load = cals_new - cals_at_boot;
		if (cals_after_load != 1) begin
			$display("after load: %0d calibrations, expected 1", cals_after_load);
			fail("a ROM load did not calibrate exactly once");
		end
		if (md_new)  fail("machine still held long after a load");
		if (sys_new) fail("core still held long after a load");
		$display("load:   calibrations=%0d md_reset=%0b sys_reset=%0b", cals_after_load, md_new, sys_new);

		// --- the reset button --------------------------------------------------
		@(negedge clk) reset = 1;
		repeat (4) @(posedge clk);
		if (!btn_new) fail("reset button did not reach the machine");
		@(negedge clk) reset = 0;
		repeat (WINDOW * 3 + CAL_LEN * 3 + 400) @(posedge clk);
		cals_after_btn = cals_new - cals_at_boot - cals_after_load;
		if (cals_after_btn != 1) begin
			$display("after button: %0d calibrations, expected 1", cals_after_btn);
			fail("the reset button did not calibrate exactly once");
		end
		if (btn_new) fail("reset button never cleared");
		if (md_new)  fail("machine still held long after the button");
		if (sys_new) fail("core still held long after the button");
		$display("button: calibrations=%0d md_reset=%0b sys_reset=%0b btn=%0b",
		         cals_after_btn, md_new, sys_new, btn_new);

		// --- the control run ---------------------------------------------------
		// v43 in the same rig, over the same time. if this does not run away the
		// bench is not closing the loop and none of the above means anything.
		$display("v43:    calibrations=%0d (must be many)", cals_old);
		if (cals_old < 10) fail("the bench does not reproduce the v43 loop");

		if (errors == 0) $display("tb_reset PASS");
		else begin
			$display("tb_reset FAIL (%0d)", errors);
			$fatal;
		end
		$finish;
	end
endmodule
