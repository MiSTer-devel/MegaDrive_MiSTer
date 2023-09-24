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

// same as how nukey handles it but without psg
wire [8:0] MOL_s = MOL - 9'h100;
wire [8:0] MOR_s = MOR - 9'h100;

wire [15:0] md_fm_3438_l = {MOL_s[8], MOL_s,6'h0};
wire [15:0] md_fm_3438_r = {MOR_s[8], MOR_s,6'h0};
wire [15:0] md_fm_2612_l = {MOL_2612[9], MOL_2612,5'h0} + {{2{MOL_2612[9]}}, MOL_2612,4'h0};
wire [15:0] md_fm_2612_r = {MOR_2612[9], MOR_2612,5'h0} + {{2{MOR_2612[9]}}, MOR_2612,4'h0};

wire [15:0] md_fm_l = fm_mode ? md_fm_3438_l : md_fm_2612_l;
wire [15:0] md_fm_r = fm_mode ? md_fm_3438_r : md_fm_2612_r;

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

wire [15:0] fm_select_l = ((lpf_mode == 2'b01)) ? md_fm_lpf_l : md_fm_l;
wire [15:0] fm_select_r = ((lpf_mode == 2'b01)) ? md_fm_lpf_r : md_fm_r;
// wire signed [10:0] psg_adjust = PSG_SND - (PSG_SND >>> 5); // Way that the genesis core adjusted volume before

wire [15:0] pre_lpf_l, pre_lpf_r;

audio_resampler #(.IW(16)) audio_resampler
(
	.clk(clk),
	.reset(reset),
	.psg_in(PSG),            //       223722Hz incoming sample rate
	.smsfm_in(sms_fm_audio), //        49715Hz incoming sample rate
	.fm_l_in(fm_select_l),   //        53267Hz incoming sample rate
	.fm_r_in(fm_select_r),   //        53267Hz incoming sample rate
	.snd_l_out(pre_lpf_l),   // synced 53267Hz outgoing sample rate interpolated to Master Clock
	.snd_r_out(pre_lpf_r)    // synced 53267Hz outgoing sample rate interpolated to Master Clock
);

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
