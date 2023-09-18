//============================================================================
//  MegaDrive input implementation
//  Copyright (c) 2023 Alexey Melnikov
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module md_io
(
	input        clk,
	input        reset,

	input        MODE,
	input        SMS,
	input  [1:0] MULTITAP,

	input        P1_UP,
	input        P1_DOWN,
	input        P1_LEFT,
	input        P1_RIGHT,
	input        P1_A,
	input        P1_B,
	input        P1_C,
	input        P1_START,
	input        P1_MODE,
	input        P1_X,
	input        P1_Y,
	input        P1_Z,

	input        P2_UP,
	input        P2_DOWN,
	input        P2_LEFT,
	input        P2_RIGHT,
	input        P2_A,
	input        P2_B,
	input        P2_C,
	input        P2_START,
	input        P2_MODE,
	input        P2_X,
	input        P2_Y,
	input        P2_Z,

	input        P3_UP,
	input        P3_DOWN,
	input        P3_LEFT,
	input        P3_RIGHT,
	input        P3_A,
	input        P3_B,
	input        P3_C,
	input        P3_START,
	input        P3_MODE,
	input        P3_X,
	input        P3_Y,
	input        P3_Z,

	input        P4_UP,
	input        P4_DOWN,
	input        P4_LEFT,
	input        P4_RIGHT,
	input        P4_A,
	input        P4_B,
	input        P4_C,
	input        P4_START,
	input        P4_MODE,
	input        P4_X,
	input        P4_Y,
	input        P4_Z,

	input        P5_UP,
	input        P5_DOWN,
	input        P5_LEFT,
	input        P5_RIGHT,
	input        P5_A,
	input        P5_B,
	input        P5_C,
	input        P5_START,
	input        P5_MODE,
	input        P5_X,
	input        P5_Y,
	input        P5_Z,

	input        GUN_OPT,
	input        GUN_TYPE,
	input        GUN_SENSOR,
	input        GUN_A,
	input        GUN_B,
	input        GUN_C,
	input        GUN_START,

	input  [2:0] MOUSE_OPT,
	input [24:0] MOUSE,

	output[15:0] jcart_data,
	input        jcart_th,

	output reg [6:0] port1_out,
	input      [6:0] port1_in,
	input      [6:0] port1_dir,

	output reg [6:0] port2_out,
	input      [6:0] port2_in,
	input      [6:0] port2_dir
);

wire [6:0] port1_fw,port2_fw;
fourway fourway
(
	.*,
	.port1_out(port1_fw),
	.port2_out(port2_fw)
);

wire [6:0] port1_tp,port2_tp;
teamplayer teamplayer
(
	.*,
	.PORT(MULTITAP[0]),
	.port1_out(port1_tp),
	.port2_out(port2_tp)
);

wire [6:0] port_ms;
multitap_sms multitap_sms
(
	.*,
	.port_out(port_ms),
	.port_in(port1_in),
	.port_dir(port1_dir)
);

wire [6:0] port1_pad;
pad_io input1
(
	.clk(clk),
	.reset(reset),

	.MODE(MODE),
	.SMS(SMS),

	.P_UP(P1_UP),
	.P_DOWN(P1_DOWN),
	.P_LEFT(P1_LEFT),
	.P_RIGHT(P1_RIGHT),
	.P_A(P1_A),
	.P_B(P1_B),
	.P_C(P1_C),
	.P_START(P1_START),
	.P_MODE(P1_MODE),
	.P_X(P1_X),
	.P_Y(P1_Y),
	.P_Z(P1_Z),

	.MOUSE_EN(MOUSE_OPT[0]),
	.MOUSE_FLIPY(MOUSE_OPT[2]),
	.MOUSE(MOUSE),

	.port_out(port1_pad),
	.port_in(port1_in),
	.port_dir(port1_dir)
);

wire [6:0] port2_pad;
pad_io input2
(
	.clk(clk),
	.reset(reset),

	.MODE(MODE),
	.SMS(SMS),

	.P_UP   (MULTITAP[1] ? P5_UP    : P2_UP    ),
	.P_DOWN (MULTITAP[1] ? P5_DOWN  : P2_DOWN  ),
	.P_LEFT (MULTITAP[1] ? P5_LEFT  : P2_LEFT  ),
	.P_RIGHT(MULTITAP[1] ? P5_RIGHT : P2_RIGHT ),
	.P_A    (MULTITAP[1] ? P5_A     : P2_A     ),
	.P_B    (MULTITAP[1] ? P5_B     : P2_B     ),
	.P_C    (MULTITAP[1] ? P5_C     : P2_C     ),
	.P_START(MULTITAP[1] ? P5_START : P2_START ),
	.P_MODE (MULTITAP[1] ? P5_MODE  : P2_MODE  ),
	.P_X    (MULTITAP[1] ? P5_X     : P2_X     ),
	.P_Y    (MULTITAP[1] ? P5_Y     : P2_Y     ),
	.P_Z    (MULTITAP[1] ? P5_Z     : P2_Z     ),

	.GUN_EN(GUN_OPT),
	.GUN_TYPE(GUN_TYPE),
	.GUN_SENSOR(GUN_SENSOR),
	.GUN_A(GUN_A),
	.GUN_B(GUN_B),
	.GUN_C(GUN_C),
	.GUN_START(GUN_START),

	.MOUSE_EN(MOUSE_OPT[1]),
	.MOUSE_FLIPY(MOUSE_OPT[2]),
	.MOUSE(MOUSE),

	.port_out(port2_pad),
	.port_in(port2_in),
	.port_dir(port2_dir)
);

pad_io jcart_l
(
	.clk(clk),
	.reset(reset),

	.MODE(MODE),

	.P_UP(P3_UP),
	.P_DOWN(P3_DOWN),
	.P_LEFT(P3_LEFT),
	.P_RIGHT(P3_RIGHT),
	.P_A(P3_A),
	.P_B(P3_B),
	.P_C(P3_C),
	.P_START(P3_START),
	.P_MODE(P3_MODE),
	.P_X(P3_X),
	.P_Y(P3_Y),
	.P_Z(P3_Z),

	.port_in({jcart_th,6'd0}),
	.port_dir(7'b0111111),
	.port_out(jcart_data[6:0])
);

pad_io jcart_u
(
	.clk(clk),
	.reset(reset),

	.MODE(MODE),

	.P_UP(P4_UP),
	.P_DOWN(P4_DOWN),
	.P_LEFT(P4_LEFT),
	.P_RIGHT(P4_RIGHT),
	.P_A(P4_A),
	.P_B(P4_B),
	.P_C(P4_C),
	.P_START(P4_START),
	.P_MODE(P4_MODE),
	.P_X(P4_X),
	.P_Y(P4_Y),
	.P_Z(P4_Z),

	.port_in({jcart_th,6'd0}),
	.port_dir(7'b0111111),
	.port_out(jcart_data[14:8])
);

assign jcart_data[7]  = 0;
assign jcart_data[15] = 0;

always @(posedge clk) begin
	case(MULTITAP)
		0: {port2_out,port1_out} <= {port2_pad, port1_pad};
		1: {port2_out,port1_out} <= {port2_fw,  port1_fw };
		2: {port2_out,port1_out} <= {port2_pad, SMS ? port_ms : port1_tp};
		3: {port2_out,port1_out} <= {port2_tp,  port1_pad};
	endcase
end

endmodule
