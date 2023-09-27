`timescale 1ns / 1ps
//
// audio_comb_filter (modified version of both jt12_comb)
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
// Based heavily on Jotego's jt12_genmix suite of modules
//

module audio_comb_filter #(
    parameter IW    = 16, // Input bit width (use CALCW in cic filter module)
    parameter DEPTH = 1   // Depth of comb filter
)
(
    input  logic          clk,
    input  logic          reset,
    input  logic          cen,
    input  logic [IW-1:0] snd_in,
    output logic [IW-1:0] snd_out
);

logic [IW-1:0] prev;
logic [IW-1:0] mem[0:DEPTH-1];
assign prev = mem[DEPTH-1];

// DEPTH-delay stage
generate
    genvar i;
    for (i = 0; i < DEPTH; i = i + 1) begin : mem_gen
        always_ff @(posedge clk) begin
            if (reset) begin
                mem[i] <= {IW{1'b0}};
            end else if (cen) begin
                mem[i] <= (i == 0) ? snd_in : mem[i-1];
            end
        end
    end
endgenerate

// Comb filter at sample rate
always_ff @(posedge clk) begin
    if (reset) begin
        snd_out <= {IW{1'b0}};
    end else if (cen) begin
        snd_out <= snd_in - prev;
    end
end

endmodule
