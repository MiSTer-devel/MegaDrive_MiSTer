//
// audio_cond.sv
//
// Copyright (c) 2023 Alexey Melnikov
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module audio_cond
(
	input         clk,
	input         reset,
	input         mute,

	input   [1:0] lpf_mode,
	input         fm_mode,

	input         fm_clk1,
	input         fm_sel23,
	input   [8:0] MOL,
	input   [8:0] MOR,
	input   [9:0] MOL_2612,
	input   [9:0] MOR_2612,
	input  [15:0] PSG,
	input  [13:0] sms_fm_audio,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R
);

reg  [15:0] md_fm_l, md_fm_r;
always @(posedge clk) begin
	reg [13:0] out_l, out_r;
	reg [13:0] MOL3_s,MOR3_s,MOL2_s,MOR2_s;
	reg [13:0] fm_l,fm_r;
	reg        clk_d1, clk_d2, clk_d3, sel23_d1, sel23_d2;
	
	MOL3_s <= {{6{~MOL[8]}},MOL[7:0]};
	MOR3_s <= {{6{~MOR[8]}},MOR[7:0]};
	MOL2_s <= {{5{MOL_2612[9]}},MOL_2612[8:0]} + {{5{MOL_2612[9]}},MOL_2612[8:0]} + {{5{MOL_2612[9]}},MOL_2612[8:0]};
	MOR2_s <= {{5{MOR_2612[9]}},MOR_2612[8:0]} + {{5{MOR_2612[9]}},MOR_2612[8:0]} + {{5{MOR_2612[9]}},MOR_2612[8:0]};
	fm_l   <= fm_mode ? MOL3_s : MOL2_s;
	fm_r   <= fm_mode ? MOR3_s : MOR2_s;

	clk_d1 <= fm_clk1;
	clk_d2 <= clk_d1;

	sel23_d1 <= fm_sel23;
	sel23_d2 <= sel23_d1;

	clk_d3 <= clk_d2;
	if(clk_d3 & ~clk_d2) begin
		out_l <= out_l + fm_l;
		out_r <= out_r + fm_r;
		if(sel23_d2) begin
			md_fm_l <= {out_l + fm_l,2'b00};
			md_fm_r <= {out_r + fm_r,2'b00};
			out_l <= 0;
			out_r <= 0;
		end
	end
end

wire [15:0] md_fm_lpf_l;
wire [15:0] md_fm_lpf_r;

genesis_fm_lpf fm_lpf_l
(
	.clk(clk),
	.reset(reset),

	.in(md_fm_l),
	.out(md_fm_lpf_l)
);

genesis_fm_lpf fm_lpf_r
(
	.clk(clk),
	.reset(reset),

	.in(md_fm_r),
	.out(md_fm_lpf_r)
);

wire ce_flt;
CEGen fltce
(
	.CLK(clk),
	.RST_N(~reset),

	.IN_CLK(53693175),
	.OUT_CLK(7056000),

	.CE(ce_flt)
);

wire [15:0] psg_amp = PSG + PSG[15:1];

// 8KHz 2tap
IIR_filter
#(
	.use_params(1),
	.stereo(0),
	.coeff_x (0.0000943),
	.coeff_x0(2),
	.coeff_x1(1),
	.coeff_x2(0),
	.coeff_y0(-1.98992552008492529225),
	.coeff_y1( 0.98997601394542067421),
	.coeff_y2(0) 
)
psg_iir
(
	.clk(clk),
	.reset(reset),

	.ce(ce_flt),
	.sample_ce(1),

	.input_l(psg_amp),
	.output_l(psg)
);

wire [15:0] psg;

reg [15:0] pre_lpf_l,pre_lpf_r;
always @(posedge clk) begin
	reg [15:0] sms_fm;
	reg [15:0] al,ar;

	sms_fm <= ^sms_fm_audio[13:12] ? {{2{sms_fm_audio[13]}}, {12{sms_fm_audio[12]}}, 2'b00} : {sms_fm_audio[12],sms_fm_audio[12:0], 2'b00};

	al <= ((lpf_mode == 1) ? md_fm_lpf_l : md_fm_l) + sms_fm + ((lpf_mode == 3) ? psg_amp : psg);
	ar <= ((lpf_mode == 1) ? md_fm_lpf_r : md_fm_r) + sms_fm + ((lpf_mode == 3) ? psg_amp : psg);

	pre_lpf_l <= ^al[15:14] ? {al[15],{15{al[14]}}} : {al[14:0], 1'b0};
	pre_lpf_r <= ^ar[15:14] ? {ar[15],{15{ar[14]}}} : {ar[14:0], 1'b0};
end

wire [15:0] audio_l, audio_r;
genesis_lpf lpf_left
(
	.clk(clk),
	.reset(reset),

	.lpf_mode(lpf_mode),
	.in(pre_lpf_l),
	.out(audio_l)
);

genesis_lpf lpf_right
(
	.clk(clk),
	.reset(reset),

	.lpf_mode(lpf_mode),
	.in(pre_lpf_r),
	.out(audio_r)
);

assign AUDIO_L = mute ? 16'd0 : audio_l;
assign AUDIO_R = mute ? 16'd0 : audio_r;

endmodule
