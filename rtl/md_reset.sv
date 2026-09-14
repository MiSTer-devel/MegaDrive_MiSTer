// cnt resets the whole core (through sys_reset); cal_cnt holds the machine only
// after the scan chain is measured. Keep them separate: mixing them lets the
// machine's own controller reset the rest of the core and calibration loops forever.
module md_reset #(parameter DIV = 15)
(
	input                clk,

	input                loading,     
	input                reset,       // level, not edge
	input                cal_busy,    // savestate controller is mid-calibration
	input                hold,

	// all power up asserted: the Cyclone V loads flop values from the bitstream,
	// and the first clock out of configuration must not run the machine unreset
	output reg           md_reset  = 1,  
	output reg           s_reset   = 1,  // via sys_reset
	output reg           btn_reset = 0,  // edge triggered, into md_board
	output reg           ss_reset  = 1,
	output reg [DIV:1]   ram_rst_a = 0   // free-running clear address for the RAMs
);

reg [4:0] cnt = 0;
reg [1:0] cal_cnt = 3;   // 3 means the window is closed
reg       cold = 1;      
reg       old_reset = 0;
reg       old_cal = 1;   // starts high: cal_busy is high at power-up, no edge at t=0
reg       old_hold = 0;
reg       pend_reset = 0;   

always @(posedge clk) begin
	ram_rst_a <= ram_rst_a + 1'd1;
	if(&ram_rst_a & ~&cnt) cnt <= cnt + 1'd1;

	old_reset <= reset;
	old_hold  <= hold;
	if(~old_reset & reset & hold)          pend_reset <= 1;
	else if(old_hold & ~hold & pend_reset) pend_reset <= 0;

	if(loading | (~old_reset & reset & ~hold) | (old_hold & ~hold & pend_reset)) cnt <= 0;

	if(loading)       cold <= 1;
	else if(cnt == 3) cold <= 0;

	// scan-out leaves every flop zero with no reset sequence run over it; on the
	// PSG zero attenuation is full volume, so an unreset core sings
	old_cal <= cal_busy;
	if(old_cal & ~cal_busy)         cal_cnt <= 0;
	else if(&ram_rst_a & ~&cal_cnt) cal_cnt <= cal_cnt + 1'd1;

	s_reset <= (cnt < 3);

	// one expression, not if/else: a two-branch if/else leaves a window where neither
	// fires and md_reset holds a stale value instead of staying asserted.
	// (old_cal & ~cal_busy) covers the clock cal_cnt loads on, else md_reset glitches.
	md_reset <= loading | cal_busy | (old_cal & ~cal_busy) | ~&cal_cnt | (cnt < 3 & cold);
	ss_reset <= loading | (cnt < 3 & cold);

	if((~old_reset & reset & ~hold) | (old_hold & ~hold & pend_reset)) btn_reset <= 1;
	else if(&cnt)                                                      btn_reset <= 0;
end

endmodule
