//============================================================================
//  Reset sequencing for the gate-level machine and for the rest of the core.
//
//  Lifted out of MegaDrive.sv so a bench can drive the shipped code rather than
//  a copy of it. The copy is how this went wrong the first time: the block is
//  eleven lines, it reads as obviously correct, and it is wired into a loop that
//  is invisible unless the loop is closed in simulation.
//
//  Two counters, and they are not interchangeable:
//
//    cnt      the whole core. Drives s_reset, and through it sys_reset, which
//             resets the SDRAM controller, the video path, the audio path and
//             the savestate controller.
//    cal_cnt  the machine only. The window that holds the machine down after
//             the scan chain has been measured.
//
//  v43 used cnt for both. Calibration finished, s_reset went high, sys_reset
//  reset the savestate controller, the controller calibrated again, and that
//  ran forever: on hardware a loud hum under a rolling picture with no usable
//  OSD. Nothing outside the machine may be reset by something the machine's own
//  controller can trigger.
//============================================================================

module md_reset #(parameter DIV = 15)
(
	input                clk,

	input                loading,     // a ROM is being written into the cartridge
	input                reset,       // the core's own reset, level
	input                cal_busy,    // the savestate controller is measuring the chain

	// powers up asserted, not released: the Cyclone V loads flop power-up values
	// from the bitstream, and a machine that runs for the first clock out of
	// configuration is a machine running on whatever configuration left behind
	output reg           md_reset  = 1,  // the gate-level machine
	output reg           s_reset   = 1,  // everything else, via sys_reset
	output reg           btn_reset = 0,  // edge triggered, into md_board
	output reg [DIV:1]   ram_rst_a = 0   // free-running clear address for the RAMs
);

reg [4:0] cnt = 0;
reg [1:0] cal_cnt = 3;   // 3 means the window is closed
reg       old_reset = 0;
reg       old_cal = 1;   // cal_busy is high from power-up, so no edge at time zero

always @(posedge clk) begin
	ram_rst_a <= ram_rst_a + 1'd1;
	if(&ram_rst_a & ~&cnt) cnt <= cnt + 1'd1;

	old_reset <= reset;
	if(loading | (~old_reset & reset)) cnt <= 0;

	// Calibration shifts the whole machine state out and leaves every flop at
	// zero. Released on the clock the marker arrives, the machine starts from
	// those zeros with no reset sequence over them; on the PSG zero attenuation
	// is full volume and a zero period is a very high note, so a core with no
	// cartridge sang.
	old_cal <= cal_busy;
	if(old_cal & ~cal_busy)         cal_cnt <= 0;
	else if(&ram_rst_a & ~&cal_cnt) cal_cnt <= cal_cnt + 1'd1;

	s_reset <= (cnt < 3);

	// One expression rather than a chain of ifs. v43 had
	//
	//     if(loading | cal_busy) md_reset <= 1;
	//     else if(cnt >= 3)      md_reset <= 0;
	//
	// which has a path to zero and none to one: while cnt is under three neither
	// branch runs and the register holds what it had, on this chip the power-up
	// zero, the machine running, through exactly the window meant to hold it.
	//
	// (old_cal & ~cal_busy) is the clock cal_cnt is being loaded on. Without it
	// md_reset drops for one clock between calibration letting go and the window
	// opening, which is a reset glitch on the machine at 107 MHz.
	md_reset <= loading | cal_busy | (old_cal & ~cal_busy) | ~&cal_cnt | (cnt < 3);

	if(~old_reset & reset) btn_reset <= 1;
	else if(&cnt)          btn_reset <= 0;
end

endmodule
