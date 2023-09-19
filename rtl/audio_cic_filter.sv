`timescale 1ns / 1ps
//
// audio_cic_filter.sv (modified verison of both jt12_interpol and jt12_decim)
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
    Date: 10-12-2018

*/
//
// Based heavily on Jotego's jt12_genmix suite of modules
//

module audio_cic_filter #(
    parameter TYPE   = 0,  // 0 for Interpolation, 1 for Decimation
    parameter CALCW  = 18, // For difference calculations when compared against IW
    parameter IW     = 16, // Input width
    parameter STAGES = 2,  // Number of stages
    parameter DEPTH  = 1,  // Depth of the comb filter
    parameter RATE   = 2   // How many zeros to stuff in interpolation (0 is invalid!)
)
(
    input  logic                 clk,     // master clock
    input  logic                 reset,   // active-high reset
    input  logic                 cen_in,  // incoming sample rate
    input  logic                 cen_out, // what the target sample rate should be
    input  logic signed [IW-1:0] snd_in,  // signed audio in
    output logic signed [IW-1:0] snd_out  // signed audio out
);

localparam WDIFF = CALCW - IW;

logic cen_select;
assign cen_select = (TYPE == 0) ? cen_in : cen_out;

logic signed [CALCW-1:0] inter6, integ_op, comb_op;

logic [CALCW-1:0] comb_data[0:STAGES];
assign comb_data[0] = (TYPE == 0) ? {{WDIFF{snd_in[IW-1]}}, snd_in} : inter6;
assign comb_op = comb_data[STAGES];

generate
    genvar j;
    for (j = 0; j < STAGES; j = j + 1) begin : comb_gen
        audio_comb_filter #(.IW(CALCW), .DEPTH(DEPTH)) audio_comb_filter
        (
            .clk    (clk),
            .reset  (reset),
            .cen    (cen_select),
            .snd_in (comb_data[j]),
            .snd_out(comb_data[j+1])
        );
    end
endgenerate

logic [RATE-1:0] inter_cnt;

// Interpolator or Decimator (see TYPE param)
always_ff @(posedge clk) begin
    if (reset) begin
        inter6 <= {CALCW{1'b0}};
        inter_cnt <= (TYPE == 0) ? {{(RATE-1){1'b0}}, 1'b1} : '0 ;
    end else if (cen_out) begin
        inter6 <= (TYPE == 0) ? (inter_cnt[0] ? comb_op : {CALCW{1'b0}}) : integ_op;
        inter_cnt <= (TYPE == 0) ? {inter_cnt[0], inter_cnt[RATE-1:1]} : '0;
    end
end

// Integrator at clk * cen sample rate
generate
    genvar k;
    logic [CALCW-1:0] integ_data[0:STAGES];
    assign integ_op = integ_data[STAGES];
    always_comb integ_data[0] = (TYPE == 0) ? inter6 : {{WDIFF{snd_in[IW-1]}}, snd_in};
    for (k = 1; k <= STAGES; k = k + 1) begin : integ_gen
        always_ff @(posedge clk) begin
            if (reset) begin
                integ_data[k] <= {CALCW{1'b0}};
            end else if (cen_select) begin
                integ_data[k] <= integ_data[k] + integ_data[k-1];
            end
        end
    end
endgenerate

always_ff @(posedge clk) begin
    if (reset) begin
        snd_out <= {IW{1'b0}};
    end else if (cen_out) begin
        snd_out <= (TYPE == 0) ? integ_op[CALCW-1:WDIFF] : comb_op[CALCW-1:WDIFF];
    end
end

endmodule
