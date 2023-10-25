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

module teamplayer
(
	input clk,
	input reset,

	input PORT,
	input MODE,

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

	input P5_UP,
	input P5_DOWN,
	input P5_LEFT,
	input P5_RIGHT,
	input P5_A,
	input P5_B,
	input P5_C,
	input P5_START,
	input P5_MODE,
	input P5_X,
	input P5_Y,
	input P5_Z,

	output [6:0] port1_out,
	input  [6:0] port1_in,
	input  [6:0] port1_dir,

	output [6:0] port2_out,
	input  [6:0] port2_in,
	input  [6:0] port2_dir
);

wire [3:0] pad1qp_i[3] = '{~{P1_RIGHT,P1_LEFT,P1_DOWN,P1_UP}, ~{P1_START,P1_A,P1_C,P1_B}, ~{P1_MODE,P1_X,P1_Y,P1_Z}};
wire [3:0] pad2qp_i[3] = '{~{P2_RIGHT,P2_LEFT,P2_DOWN,P2_UP}, ~{P2_START,P2_A,P2_C,P2_B}, ~{P2_MODE,P2_X,P2_Y,P2_Z}};
wire [3:0] pad3qp_i[3] = '{~{P3_RIGHT,P3_LEFT,P3_DOWN,P3_UP}, ~{P3_START,P3_A,P3_C,P3_B}, ~{P3_MODE,P3_X,P3_Y,P3_Z}};
wire [3:0] pad4qp_i[3] = '{~{P4_RIGHT,P4_LEFT,P4_DOWN,P4_UP}, ~{P4_START,P4_A,P4_C,P4_B}, ~{P4_MODE,P4_X,P4_Y,P4_Z}};
wire [3:0] pad5qp_i[3] = '{~{P5_RIGHT,P5_LEFT,P5_DOWN,P5_UP}, ~{P5_START,P5_A,P5_C,P5_B}, ~{P5_MODE,P5_X,P5_Y,P5_Z}};

wire [3:0] pad1qp[3] = PORT ? pad2qp_i : pad1qp_i;
wire [3:0] pad2qp[3] = PORT ? pad3qp_i : pad2qp_i;
wire [3:0] pad3qp[3] = PORT ? pad4qp_i : pad3qp_i;
wire [3:0] pad4qp[3] = PORT ? pad5qp_i : pad4qp_i;

wire [3:0] pad_3btn[8]  = '{pad1qp[0],pad1qp[1],pad2qp[0],pad2qp[1],pad3qp[0],pad3qp[1],pad4qp[0],pad4qp[1]};
wire [3:0] pad_6btn[12] = '{pad1qp[0],pad1qp[1],pad1qp[2],pad2qp[0],pad2qp[1],pad2qp[2],pad3qp[0],pad3qp[1],pad3qp[2],pad4qp[0],pad4qp[1],pad4qp[2]};

wire [1:0] new_state = PORT ? (port2_in[6:5] | port2_dir[6:5]) : (port1_in[6:5] | port1_dir[6:5]);

assign port1_out = (~port1_dir & port1_in) | (port1_dir & out);
assign port2_out = (~port2_dir & port2_in) | (port2_dir & out);

reg [6:0] out;
always @(posedge clk) begin

	reg [4:0] cnt;
	reg [1:0] state;
	
	if(reset) begin
		cnt  <= 0;
		state<= 3;
	end
	else begin
		if(state != new_state) begin
			if(~&cnt) cnt <= cnt + 1'd1;
			if(~state[1] & new_state[1]) cnt <= 0;
			state <= new_state;
		end
		case(cnt)
					0: out <= {state, state[0], 4'b0011};
					1: out <= {state, state[0], 4'b1111};
				 2,3: out <= {state, state[0], 4'b0000};
			4,5,6,7: out <= {state, state[0], 3'b000, MODE};
			default: out <= {state, state[0], ~MODE ? pad_3btn[cnt[2:0]] : pad_6btn[cnt[3:0]-4'd8]};
		endcase
	end
end

endmodule
