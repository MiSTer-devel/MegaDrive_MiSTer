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

module pad_io
(
	input        clk,
	input        reset,

	input        MODE,
	input        SMS,

	input        P_UP,
	input        P_DOWN,
	input        P_LEFT,
	input        P_RIGHT,
	input        P_A,
	input        P_B,
	input        P_C,
	input        P_START,
	input        P_MODE,
	input        P_X,
	input        P_Y,
	input        P_Z,

	input        GUN_EN,
	input        GUN_TYPE,
	input        GUN_SENSOR,
	input        GUN_A,
	input        GUN_B,
	input        GUN_C,
	input        GUN_START,

	input        MOUSE_EN,
	input        MOUSE_FLIPY,
	input [24:0] MOUSE,

	output [6:0] port_out,
	input  [6:0] port_in,
	input  [6:0] port_dir
);

assign port_out = (~port_dir & port_in) | (port_dir & (GUN_EN ? gdata : MOUSE_EN ? {2'b00,mdata} : {1'b1, pdata}));

// GAMEPAD ------------------------------------------------------

reg       TH;
reg [1:0] JCNT;
always @(posedge clk) begin
	reg [19:0] JTMR;
	reg [10:0] FLTMR;

	reg THd;

	if(reset) begin
		TH   <= 1;
		JCNT <= 3;
	end
	else begin
		if(~&FLTMR) FLTMR <= FLTMR + 1'd1;
		if(~port_dir[6]) begin
			TH <= port_in[6];
			FLTMR <= 0;
		end
		else if(FLTMR == (210*7)) TH <= 1;
	
		THd <= TH;
		if(JTMR > (11600*7) || ~MODE) JCNT <= 0;
		if(~THd & TH) JCNT <= JCNT + 1'd1;

		if(~&JTMR) JTMR <= JTMR + 1'd1;
		if(THd & ~TH) JTMR <= 0;
	end
end

wire [5:0] pdata;
always @(posedge clk) begin
	priority casex({SMS,JCNT,TH})
		4'b1XXX: pdata <= { ~P_C,     ~P_B, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP}; 
		4'b0100: pdata <= { ~P_START, ~P_A,   1'b0,     1'b0,    1'b0,   1'b0};
		4'b0110: pdata <= { ~P_START, ~P_A,   1'b1,     1'b1,    1'b1,   1'b1};
		4'b0111: pdata <= { ~P_C,     ~P_B, ~P_MODE,  ~P_X,    ~P_Y,    ~P_Z };
		4'b0XX1: pdata <= { ~P_C,     ~P_B, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP};
		4'b0XX0: pdata <= { ~P_START, ~P_A,   1'b0,     1'b0,  ~P_DOWN, ~P_UP};
	endcase
end

// MOUSE ------------------------------------------------------

reg   [8:0] dx,dy;
reg   [4:0] mdata;
reg  [10:0] curdx,curdy;
wire [10:0] newdx = curdx + {{3{MOUSE[4]}},MOUSE[15:8]};
wire [10:0] newdy = MOUSE_FLIPY ? (curdy - {{3{MOUSE[5]}},MOUSE[23:16]}) : (curdy + {{3{MOUSE[5]}},MOUSE[23:16]});

wire MTH = port_in[6] & ~port_dir[6];
wire MTR = port_in[5] & ~port_dir[5];

always @(posedge clk) begin
	reg old_stb;
	reg mtrd,mtrd2;
	reg [3:0] cnt;
	reg [8:0] delay;
	
	if(!delay) begin
		if(mtrd ^ MTR) delay <= 1;
	end
	else begin
		if(&delay) mtrd <= MTR;
		delay <= delay + 1'd1;
	end

	mtrd2 <= mtrd;
	if(mtrd2 ^ mtrd) begin
		if(~&cnt) cnt <= cnt + 1'd1;
		if(!cnt) begin
			dx <= curdx[8:0];
			dy <= curdy[8:0];
			curdx <= 0;
			curdy <= 0;
		end
	end
	else begin
		old_stb <= MOUSE[24];
		if(old_stb != MOUSE[24]) begin
			if($signed(newdx) > $signed(10'd255)) curdx <= 10'd255;
			else if($signed(newdx) < $signed(-10'd255)) curdx <= -10'd255;
			else curdx <= newdx;

			if($signed(newdy) > $signed(10'd255)) curdy <= 10'd255;
			else if($signed(newdy) < $signed(-10'd255)) curdy <= -10'd255;
			else curdy <= newdy;
		end;
	end
	
	case(cnt)
			0: mdata <= 4'b1011;
			1: mdata <= 4'b1111;
			2: mdata <= 4'b1111;
			3: mdata <= {dy[8],dx[8]};
			4: mdata <= MOUSE[2:0] | {P_START,P_C,P_B,P_A};
			5: mdata <= dx[7:4];
			6: mdata <= dx[3:0];
			7: mdata <= dy[7:4];
	default: mdata <= dy[3:0];
	endcase

	if(MTH) begin
		mdata <= 0;
		cnt <= 0;
	end

	mdata[4] <= mtrd2;
end


// GUN ------------------------------------------------------

reg [5:0] mdo; // Menacer
reg [5:0] jdo; // Justifier
reg gth;
reg jth;
reg mth;

wire [6:0] gdata = GUN_TYPE ? {gth & jth, jdo} : {gth & mth, mdo};
wire [6:4] gdi   = port_in[6:4] | port_dir[6:4];

always @(posedge clk) begin
	reg jgunsel; // Justifier blue gun or pink gun.
	reg jgunen;  // Justifier gun enabled.
	reg mrsten;  // Menacer RST signal level

	if(reset) begin
		jth  <= 1;
		mth  <= 1;
	end
	else begin
		gth <= gdi[6];

		// Menacer
		mrsten <= gdi[5];
		if(mrsten & ~gdi[5] & ~gdi[4]) mth <= 1'b1;
		if(GUN_SENSOR) mth <= 1'b0;
		mdo <= {2'b00, GUN_START, GUN_C, GUN_A, GUN_B};

		// Justifier
		jgunsel <= gdi[5];
		jgunen <= gdi[4];
		jdo[5:3] <= {jgunsel, jgunen, 1'b0};
		if(~jgunen) begin
			if(~jgunsel) begin
				// Blue gun
				jdo[2:0] <= {!GUN_SENSOR & gth, !GUN_START,!GUN_A};
				if(GUN_SENSOR) jth <= 1'b0;
			end
			else begin
				// Pink gun (2nd player not supported yet)
				jdo[2:0] <= {gth, 2'b11};
			end
		end
		else begin
			jdo[2:0] <= gth ? 3'b000 : 3'b011;
			jth <= 1;
		end
	end
end

endmodule
