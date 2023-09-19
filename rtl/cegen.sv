`timescale 1ns / 1ps
//
// cegen.sv
//
// Copyright (c) 2023 Kevin Coleman (kcoleman@misterfpga.co)
//
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//
// Simple synchronous 50% duty cycle clock generator in SystemVerilog
// Parameterized gated clock feature with gate condition input
//

module cegen #(
    parameter CNT_DIV     = 240  // Clock divider value
)
(
    input  logic clk,      // Clock input
    input  logic reset,    // Active-high reset
    output logic cen      // Generated clock enable
);

localparam DIV_LENGTH = $clog2(CNT_DIV + 1); // Calculate bits required for counter based on DIV value.
logic [DIV_LENGTH-1:0] counter;
logic ce;

always_ff @(posedge clk or posedge reset) begin
    if (reset) begin
        counter <= '0;
        ce <= 0;
    end else if (counter == CNT_DIV) begin
        counter <= '0;
        ce <= ~ce;
    end else begin
        counter <= counter + 1'b1;
    end
end

assign cen = ce;

endmodule
