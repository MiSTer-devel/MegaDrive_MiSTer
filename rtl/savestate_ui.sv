module savestate_ui
(
	input            clk,
	input     [10:0] ps2_key,
	input            allow_ss,
	input      [1:0] status_slot,
	input      [1:0] OSD_saveload,
	output reg       ss_save,
	output reg       ss_load,
	output reg       ss_info_req,
	output reg [7:0] ss_info,
	output reg       statusUpdate,
	output     [1:0] selected_slot
);

reg [1:0] ss_base = 0;
reg [1:0] lastOSDsetting = 2'b0;

assign selected_slot = ss_base;

wire pressed = ps2_key[9];

always @(posedge clk) begin
	reg old_state;
	reg alt = 0;
	reg [1:0] old_st;

	old_state <= ps2_key[10];

	ss_save      <= 1'b0;
	ss_load      <= 1'b0;
	ss_info_req  <= 1'b0;
	statusUpdate <= 1'b0;

	if(allow_ss) begin
		if(old_state != ps2_key[10]) begin
			case(ps2_key[7:0])
				'h11: alt <= pressed;
				'h03: begin ss_save <= pressed & alt; ss_load <= pressed & ~alt; ss_base <= 0; statusUpdate <= 1'b1; end // F5
				'h0B: begin ss_save <= pressed & alt; ss_load <= pressed & ~alt; ss_base <= 1; statusUpdate <= 1'b1; end // F6
				'h83: begin ss_save <= pressed & alt; ss_load <= pressed & ~alt; ss_base <= 2; statusUpdate <= 1'b1; end // F7
				'h0A: begin ss_save <= pressed & alt; ss_load <= pressed & ~alt; ss_base <= 3; statusUpdate <= 1'b1; end // F8
			endcase
		end

		old_st <= OSD_saveload;
		if(old_st[0] ^ OSD_saveload[0]) ss_save <= OSD_saveload[0];
		if(old_st[1] ^ OSD_saveload[1]) ss_load <= OSD_saveload[1];

		if(ss_load | ss_save) begin
			ss_info     <= 7'd1 + {ss_base, ss_load};
			ss_info_req <= 1'b1;
		end
	end

	// followed even with savestates off: every status write carries ss_base, so a
	// stale one would put the old slot back into the menu
	lastOSDsetting <= status_slot;
	if (lastOSDsetting != status_slot) begin
		ss_base      <= status_slot;
		statusUpdate <= 1'b1;
	end
end

endmodule
