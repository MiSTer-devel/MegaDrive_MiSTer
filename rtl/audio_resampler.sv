`timescale 1ns / 1ps
//
// audio_resampler.sv (restructured version of jt12_genmix)
//
/* This file is part of JT12.

    JT12 program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT12 program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT12.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 11-12-2018

    Each channel can use the full range of the DAC as they do not
    get summed in the real chip.

    Operator data is summed up without adding extra bits. This is
    the case of real YM3438, which was used on Megadrive 2 models.

*/
//
// Many methods here are taken from jotego's excellent work on jt12_genmix.
// I wrote it all my own way so I could understand each step better.
// Math values from Jotego's method --> https://github.com/jotego/jt12/blob/master/hdl/mixer/jt12_genmix.v
// His method was to align the PSG output to the FM synth rate while filtering out artifacts/aliasing
// Then do a lot of interpolating to bring both PSG and FM together uprated to mclk
// He used a CIC comb filter for each decim/interp step, so maybe FIR/IIR isn't worth it at all.
//
// PSG CIC Comb prefilter Stages
//                                                          MCLK DIV   #STAGES   #COMB_DEPTH
// PSG  223722                                               240
//      223722 * 5 = 1118610 (First interpolation stages)     48       2         4
//     1118610 / 3 =  372870 (First decimation stages)       144       3         2
//      372870 / 7 =   53267 (Second decimation stages)     1008       1         1
//
// SMS FM Comb prefilter stages - sms fm * 15 then /7 then /2 to align with MD FM sample rate of 53267
//                                                          MCLK DIV   #STAGES   #COMB_DEPTH
// SMSFM 49715                                              1080
//       49715 * 15 = 745725                                  72       ?         ?
//      745725 / 7  = 106532                                 504       ?         ?
//      106532 / 2  =  53266                                1008       ?         ?
//
// FM + PSG Interpolation Stages to synchronize with the MCLK rate
//
// FM    53267                                              1008
//       53267 * 4 =   213068 (First interpolation stages)   252       1         1
//      213068 * 4 =   852272 (Second interpolation stages)   63       3         1
//      852272 * 4 =  5965904 (Third interpolation stages)     9       2         2
//     5965904 * 9 = 53693136 (Fourth interpolation stages)            2         2
//
// not sure if i need to do Unsigned --> Signed conversion
// assign signed_sample   = unsigned_sample - (1 << (IW-1));
// Then just convert back before output (or not, we can just convert all to signed in this module's instantiations)
// assign unsigned_sample = signed_sample   + (1 << (IW-1));

module audio_resampler #(
    parameter IW   = 16 // Input width of signals and coefficients
)
(
    input  logic                 clk,       // Input clock
    input  logic                 reset,     // Active-high reset
    input  logic signed [IW-1:0] psg_in,    // PSG
    input  logic signed [IW-1:0] smsfm_in,  // Sega Master System FM
    input  logic signed [IW-1:0] fm_l_in,   // FM synth Left
    input  logic signed [IW-1:0] fm_r_in,   // FM synth right
    output logic signed [IW-1:0] snd_l_out, // IW-bit output sound left channel
    output logic signed [IW-1:0] snd_r_out  // IW-bit output sound right channel
);

// Clock Generation
logic cen240psg, cen48psg, cen144psg, cen1008psg, cen1080sms, cen72sms, cen504sms, cen1008sms, cen252fm, cen63fm, cen9fm, cen1008; // cen# = divider value

// PSG Clocks
cegen #(.CNT_DIV( 240)) cegen240psg  (.clk(clk), .reset(reset), .cen(cen240psg), ); // Incoming PSG sample rate     ( 53693136Hz / 240 =  223722Hz )
cegen #(.CNT_DIV(  48)) cegen48psg   (.clk(clk), .reset(reset), .cen(cen48psg),  ); // First PSG Interpolation rate (   223722Hz * 5   = 1118610Hz )
cegen #(.CNT_DIV( 144)) cegen144psg  (.clk(clk), .reset(reset), .cen(cen144psg), ); // First PSG Decimation rate    (  1118610Hz / 3   =  372870Hz )
// cegen #(.CNT_DIV(1008)) cegen1008psg (.clk(clk), .reset(reset), .cen(cen1008psg),); // Second PSG Decimation rate   (   372870Hz / 7   =   53267Hz )

// SMS FM Clocks
cegen #(.CNT_DIV(1080)) cegen1080sms (.clk(clk), .reset(reset), .cen(cen1080sms),); // SMS FM Incoming sample rate   ( 53693136Hz / 72 =  49715Hz )
cegen #(.CNT_DIV(  72)) cegen72sms   (.clk(clk), .reset(reset), .cen(cen72sms),  ); // SMS FM Interpolation rate     (    49715Hz * 15 = 745725Hz )
cegen #(.CNT_DIV( 504)) cegen504sms  (.clk(clk), .reset(reset), .cen(cen504sms), ); // SMS FM First Decimation rate  (   745725Hz / 7  = 106532Hz )
// cegen #(.CNT_DIV(1008)) cegen1008sms (.clk(clk), .reset(reset), .cen(cen1008sms),); // SMS FM Second Decimation rate (   106532Hz / 2  =  53266Hz )

// MD FM Clocks
cegen #(.CNT_DIV(1008)) cegen1008fm  (.clk(clk), .reset(reset), .cen(cen1008),   ); // Incoming FM Sample rate          (   372870Hz / 7 =    53267Hz )
cegen #(.CNT_DIV( 252)) cegen252fm   (.clk(clk), .reset(reset), .cen(cen252fm),  ); // First FM+PSG Interpolation rate  (    53267Hz * 4 =   213068Hz )
cegen #(.CNT_DIV(  63)) cegen63fm    (.clk(clk), .reset(reset), .cen(cen63fm),   ); // Second FM+PSG Interpolation rate (   852272Hz * 4 =  5965904Hz )
cegen #(.CNT_DIV(   9)) cegen9fm     (.clk(clk), .reset(reset), .cen(cen9fm),    ); // Third FM+PSG Interpolation rate  (  5965904Hz * 9 = 53693136Hz )

// Interpolation/decimation stages
// Then jotego sets up the interpolation/decimation stages. He expanded psg and fm by 1 bit (probably overflow prevention)
// I don't understand why he used the signed audio bit's MSB to alternate between muting audio if it's 0 or what, probably for overflow detection?
// Maybe his jt48 does this on purpose so there was a specific reason. I dunno.
// logic signed [IW:0] psg1, psg2, psg3, psg4;
// assign psg1 = { psg_in[IW], psg_in };


// MD and SMS PSG alignment to MD FM sample rate
logic signed [IW-1:0] psg1, psg2, psg3;

// Interpolate PSG by a factor of 5 with 2 stages and a filter depth of 4
audio_cic_filter #(.TYPE(0),  .CALCW(IW+8),  .IW(IW),            .STAGES(2),          .DEPTH(4),       .RATE(5)      )
interpolate_psg1  (.clk(clk), .reset(reset), .cen_in(cen240psg), .cen_out(cen48psg),  .snd_in(psg_in), .snd_out(psg1));
// Decimate PSG by a factor of 3 with 3 stages and a filter depth of 2
audio_cic_filter #(.TYPE(1),  .CALCW(IW+8),  .IW(IW),            .STAGES(3),          .DEPTH(2),       .RATE(3)      )
decimate_psg1     (.clk(clk), .reset(reset), .cen_in(cen48psg),  .cen_out(cen144psg), .snd_in(psg1),   .snd_out(psg2));
// Decimate PSG by a factor of 7 with 1 stage and a filter depth of 1 (aligned with FM sample rate)
audio_cic_filter #(.TYPE(1),  .CALCW(IW+4),  .IW(IW),            .STAGES(1),          .DEPTH(1),       .RATE(7)      )
decimate_psg2     (.clk(clk), .reset(reset), .cen_in(cen144psg), .cen_out(cen1008),   .snd_in(psg2),   .snd_out(psg3));


// SMS FM Alignment to MD FM sample rate
logic signed [IW-1:0] smsfm1, smsfm2, smsfm3;

// Interpolate SMS FM by a factor of 15 with ? stages and a filter depth of ?
audio_cic_filter #(.TYPE(0),  .CALCW(IW+8),  .IW(IW),             .STAGES(1),          .DEPTH(1),         .RATE(15)       )
interpolate_smsfm (.clk(clk), .reset(reset), .cen_in(cen1080sms), .cen_out(cen72sms),  .snd_in(smsfm_in), .snd_out(smsfm1));
// Decimate SMS FM by a factor of 7 with ? stages and a filter depth of ?
audio_cic_filter #(.TYPE(1),  .CALCW(IW+8),  .IW(IW),             .STAGES(1),          .DEPTH(1),         .RATE(7)        )
decimate_smsfm1   (.clk(clk), .reset(reset), .cen_in(cen72sms),   .cen_out(cen504sms), .snd_in(smsfm1),   .snd_out(smsfm2));
// Decimate SMS FM by a factor of 2 with ? stages and a filter depth of ?
audio_cic_filter #(.TYPE(1),  .CALCW(IW+8),  .IW(IW),             .STAGES(1),          .DEPTH(1),         .RATE(2)        )
decimate_smsfm2   (.clk(clk), .reset(reset), .cen_in(cen504sms),  .cen_out(cen1008),   .snd_in(smsfm2),   .snd_out(smsfm3));


// Mix FM and PSG now that PSG and SMS FM is downsampled to the same sample rate as FM
logic [IW-1:0] mixed_l, mixed_r; // should this be unsigned? jotego had it as unsigned...
logic signed [IW-1:0] mixed_l_2, mixed_l_3, mixed_l_4, mixed_r_2, mixed_r_3, mixed_r_4;
// always_ff @(posedge clk) mixed_l <= fm_l_in + {{1{psg3[IW]}},psg3};  // jotego method for some reason maybe for volume increase?
// always_ff @(posedge clk) mixed_r <= fm_r_in + {{1{psg3[IW]}},psg3};
always_ff @(posedge clk) mixed_l <= fm_l_in + psg3 + smsfm3;
always_ff @(posedge clk) mixed_r <= fm_r_in + psg3 + smsfm3;

// Interpolate FM+PSG left audio
// Interpolate by a factor of 4 with 1 stage and a filter depth of 1
audio_cic_filter #(.TYPE(0),  .CALCW(IW+1),  .IW(IW),           .STAGES(1),         .DEPTH(1),          .RATE(4)           )
interpolate_L_1   (.clk(clk), .reset(reset), .cen_in(cen1008),  .cen_out(cen252fm), .snd_in(mixed_l),   .snd_out(mixed_l_2));
// Interpolate by a factor of 4 with 3 stages and a filter depth of 1
audio_cic_filter #(.TYPE(0),  .CALCW(IW+3),  .IW(IW),           .STAGES(3),         .DEPTH(1),          .RATE(4)           )
interpolate_L_2   (.clk(clk), .reset(reset), .cen_in(cen252fm), .cen_out(cen63fm),  .snd_in(mixed_l_2), .snd_out(mixed_l_3));
// Interpolate by a factor of 4 with 2 stages and a filter depth of 2
audio_cic_filter #(.TYPE(0),  .CALCW(IW+5),  .IW(IW),           .STAGES(2),         .DEPTH(2),          .RATE(4)           )
interpolate_L_3   (.clk(clk), .reset(reset), .cen_in(cen63fm),  .cen_out(cen9fm),   .snd_in(mixed_l_3), .snd_out(mixed_l_4));
// Interpolate by a factor of 9 with 2 stages and a filter depth of 2
audio_cic_filter #(.TYPE(0),  .CALCW(IW+5),  .IW(IW),           .STAGES(2),         .DEPTH(2),          .RATE(9)           )
interpolate_L_4   (.clk(clk), .reset(reset), .cen_in(cen9fm),   .cen_out(1'b1),     .snd_in(mixed_l_4), .snd_out(snd_l_out));

// Interpolate FM+PSG right audio
// Interpolate by a factor of 4 with 1 stage and a filter depth of 1
audio_cic_filter #(.TYPE(0),  .CALCW(IW+1),  .IW(IW),           .STAGES(1),         .DEPTH(1),          .RATE(4)           )
interpolate_R_1   (.clk(clk), .reset(reset), .cen_in(cen1008),  .cen_out(cen252fm), .snd_in(mixed_r),   .snd_out(mixed_r_2));
// Interpolate by a factor of 4 with 3 stages and a filter depth of 1
audio_cic_filter #(.TYPE(0),  .CALCW(IW+3),  .IW(IW),           .STAGES(3),         .DEPTH(1),          .RATE(4)           )
interpolate_R_2   (.clk(clk), .reset(reset), .cen_in(cen252fm), .cen_out(cen63fm),  .snd_in(mixed_r_2), .snd_out(mixed_r_3));
// Interpolate by a factor of 4 with 2 stages and a filter depth of 2
audio_cic_filter #(.TYPE(0),  .CALCW(IW+5),  .IW(IW),           .STAGES(2),         .DEPTH(2),          .RATE(4)           )
interpolate_R_3   (.clk(clk), .reset(reset), .cen_in(cen63fm),  .cen_out(cen9fm),   .snd_in(mixed_r_3), .snd_out(mixed_r_4));
// Interpolate by a factor of 9 with 2 stages and a filter depth of 2
audio_cic_filter #(.TYPE(0),  .CALCW(IW+5),  .IW(IW),           .STAGES(2),         .DEPTH(2),          .RATE(9)           )
interpolate_R_4   (.clk(clk), .reset(reset), .cen_in(cen9fm),   .cen_out(1'b1),     .snd_in(mixed_r_4), .snd_out(snd_r_out));


endmodule
