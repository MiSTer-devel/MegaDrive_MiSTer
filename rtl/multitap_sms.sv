//
// Copyright (c) 2019-2023 Alexey Melnikov
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.

module multitap_sms
(
	input clk,
	input reset,

	input P1_UP,
	input P1_DOWN,
	input P1_LEFT,
	input P1_RIGHT,
	input P1_A,
	input P1_B,
	input P1_C,
	input P1_START,
	input P1_MODE,
	input P1_X,
	input P1_Y,
	input P1_Z,

	input P2_UP,
	input P2_DOWN,
	input P2_LEFT,
	input P2_RIGHT,
	input P2_A,
	input P2_B,
	input P2_C,
	input P2_START,
	input P2_MODE,
	input P2_X,
	input P2_Y,
	input P2_Z,

	input P3_UP,
	input P3_DOWN,
	input P3_LEFT,
	input P3_RIGHT,
	input P3_A,
	input P3_B,
	input P3_C,
	input P3_START,
	input P3_MODE,
	input P3_X,
	input P3_Y,
	input P3_Z,

	input P4_UP,
	input P4_DOWN,
	input P4_LEFT,
	input P4_RIGHT,
	input P4_A,
	input P4_B,
	input P4_C,
	input P4_START,
	input P4_MODE,
	input P4_X,
	input P4_Y,
	input P4_Z,

	output [6:0] port_out,
	input  [6:0] port_in,
	input  [6:0] port_dir
);

localparam tmr_max = 57000*15;

assign port_out = (~port_dir & port_in) | (port_dir & {1'b1, ~pad[jcnt]});

wire [5:0] pad[4] = '{
	{P1_B,P1_A,P1_RIGHT,P1_LEFT,P1_DOWN,P1_UP},
	{P2_B,P2_A,P2_RIGHT,P2_LEFT,P2_DOWN,P2_UP},
	{P3_B,P3_A,P3_RIGHT,P3_LEFT,P3_DOWN,P3_UP},
	{P4_B,P4_A,P4_RIGHT,P4_LEFT,P4_DOWN,P4_UP}
};

wire th = port_dir[6] | port_in[6];

reg  [1:0] jcnt = 0;
always @(posedge clk) begin
	reg        old_th;
	reg [23:0] tmr;

	if(tmr > tmr_max) jcnt <= 0;
	else if(th) tmr <= tmr + 1'd1;

	old_th <= th;
	if(old_th & ~th) begin
		tmr <= 0;
		if(tmr < tmr_max) jcnt <= jcnt + 1'd1;
	end

	if(reset) jcnt <= 0;
end

endmodule
