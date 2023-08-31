//============================================================================
//  HAL for NukedMD-FPGA
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

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	//Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign BUTTONS   = osd_btn;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = '0;  

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = cart_download | sav_pending;

assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;

assign AUDIO_S   = 1;
assign HDMI_FREEZE = 0;

wire  [1:0] ar = status[49:48];

wire       vcrop_en = status[34];
wire [3:0] vcopt    = status[53:50];
reg        en216p;
reg  [4:0] voff;
always @(posedge CLK_VIDEO) begin
	en216p <= ((HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !forced_scandoubler && !scale);
	voff <= (vcopt < 6) ? {vcopt,1'b0} : ({vcopt,1'b0} - 5'd24);
end

wire vga_de;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? arx : (ar - 1'd1)),
	.ARY((!ar) ? ary : 12'd0),
	.CROP_SIZE((en216p & vcrop_en) ? 10'd216 : 10'd0),
	.CROP_OFF(voff),
	.SCALE(status[55:54])
);

`include "build_id.v"
localparam CONF_STR = {
	"MegaDrive;UART31250,MIDI;",
	"FS1,BINGENMD ;",
	"FS2,SMS;",
	"-;",
	"O[7:6],Region,JP,US,EU;",
	"O[9:8],Auto Region,Header,File Ext,Disabled;",
	"D2O[28:27],Priority,US>EU>JP,EU>US>JP,US>JP>EU,JP>US>EU;",
	"d7O[12],TMSS,Disabled,Enabled;",
	
	"-;",
	"C,Cheats;",
	"H1O[24],Cheats Enabled,Yes,No;",
	"-;",
	"O[13],Autosave,Off,On;",
	"H6D0R[16],Load Backup RAM;",
	"H6D0R[17],Save Backup RAM;",
	"-;",

	"P1,Audio & Video;",
	"P1O[49:48],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O[3:1],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"d5P1O[34],Vertical Crop,Disabled,216p(5x);",
	"d5P1O[53:50],Crop Offset,0,2,4,8,10,12,-12,-10,-8,-6,-4,-2;",
	"P1O[55:54],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P1-;",
	"P1O[30],320x224 Aspect,Original,Corrected;",
	"P1O[29],Border,No,Yes;",
	"P1O[46],Composite Blend,Off,On;",
	"P1O[10],CRAM Dots,Off,On;",
	"P1-;",
	"P1O[15:14],Audio Filter,Model 1,Model 2,Minimal,No Filter;",
	"P1O[11],FM Chip,YM2612,YM3438;",
	"P1O[60],SMS FM Chip,Enabled,Disabled;",
	"P1O[58:57],Stereo Mix,None,25%,50%,100%;",

	"P2,Input;",
	"P2-;",
	"P2O[4],Swap Joysticks,No,Yes;",
	"P2O[5],6 Buttons Mode,No,Yes;",
	//"P2O[59],Swap Buttons for SMS,Yes,No;",
	"P2O[39:37],Multitap,Disabled,4-Way,TeamPlayer: Port1,TeamPlayer: Port2,J-Cart;",
	"P2-;",
	"P2O[19:18],Mouse,None,Port1,Port2;",
	"P2O[20],Mouse Flip Y,No,Yes;",
	"P2-;",
	"P2O[41:40],Gun Control,Disabled,Joy1,Joy2,Mouse;",
	"D4P2O[42],Gun Fire,Joy,Mouse;",
	"D4P2O[44:43],Cross,Small,Medium,Big,None;",
	"P2-;",
	"P2O[63:62],SNAC,Off,Port 1,Port 2,Port 3;",

	"- ;",
	"O[61],Pause When OSD is Open,No,Yes;",
	"R[0],Reset;",
	"J1,A,B,C,Start,Mode,X,Y,Z;",
	"jn,A,B,R,Start,Select,X,Y,L;", // name map to SNES layout.
	"jp,Y,B,A,Start,Select,L,X,R;", // positional map to SNES layout (3 button friendly)
	"V,v",`BUILD_DATE
};

///////////////////////////////////////////////////

wire clk_53m, clk_107m, pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_53m),
	.outclk_1(clk_107m),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(pll_locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
reg         cfg_write;
reg   [5:0] cfg_address;
reg  [31:0] cfg_data;

pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

always @(posedge CLK_50M) begin
	reg pald = 0, pald2 = 0;
	reg [2:0] state = 0;
	reg pal_r;

	pald <= PAL;
	pald2 <= pald;

	cfg_write <= 0;
	if(pald2 == pald && pald2 != pal_r) begin
		state <= 1;
		pal_r <= pald2;
	end

	if(!cfg_waitrequest) begin
		if(state) state<=state+1'd1;
		case(state)
			1: begin
					cfg_address <= 0;
					cfg_data <= 0;
					cfg_write <= 1;
				end
			5: begin
					cfg_address <= 7;
					cfg_data <= pal_r ? 2201376125 : 2537930535;
					cfg_write <= 1;
				end
			7: begin
					cfg_address <= 2;
					cfg_data <= 0;
					cfg_write <= 1;
				end
		endcase
	end
end

wire clk_sys     = clk_53m;
wire clk_ram     = clk_107m;
wire clk_md      = clk_107m;
assign CLK_VIDEO = clk_107m;

///////////////////////////////////////////////////

wire[127:0] status;
wire  [1:0] buttons;
wire [11:0] joystick_0,joystick_1,joystick_2,joystick_3,joystick_4;
wire  [7:0] joy0_x,joy0_y,joy1_x,joy1_y;
wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [15:0] ioctl_data;
wire  [7:0] ioctl_index;
wire        ioctl_wait;

reg  [31:0] sd_lba;
reg         sd_rd = 0;
reg         sd_wr = 0;
wire        sd_ack;
wire  [7:0] sd_buff_addr;
wire [15:0] sd_buff_dout;
wire [15:0] sd_buff_din;
wire        sd_buff_wr;
wire        img_mounted;
wire        img_readonly;
wire [63:0] img_size;

wire        forced_scandoubler;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire [21:0] gamma_bus;
wire [15:0] sdram_sz;

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_2(joystick_2),
	.joystick_3(joystick_3),
	.joystick_4(joystick_4),
	.joystick_l_analog_0({joy0_y, joy0_x}),
	.joystick_l_analog_1({joy1_y, joy1_x}),

	.buttons(buttons),
	.forced_scandoubler(forced_scandoubler),
	.new_vmode(new_vmode),

	.status(status),
	.status_in({status[127:8],region_req,status[5:0]}),
	.status_set(region_set),
	.status_menumask({tmss_loaded,status[13],en216p,!gun_mode,1'b0,status[8],~gg_available,~bk_ena}),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_wait(ioctl_wait),

	.sd_lba('{sd_lba}),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din('{sd_buff_din}),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.gamma_bus(gamma_bus),
	.sdram_sz(sdram_sz),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse)
);

wire [1:0] gun_mode = status[41:40];
wire       gun_btn_mode = status[42];

wire cart_download = ioctl_download & (ioctl_index[4:0] == 1 || ioctl_index[4:0] == 2);
wire code_download = ioctl_download & &ioctl_index;
wire tmss_download = ioctl_download & !ioctl_index;

reg cart_ms;
always @(posedge clk_sys) begin
	reg old_download;
	
	old_download <= cart_download;
	if(~old_download & cart_download) begin
		if(ioctl_index[4:0] == 2) cart_ms <= 1;
		if(ioctl_index[4:0] == 1) cart_ms <= 0;
	end
end

reg osd_btn = 0;
always @(posedge clk_sys) begin
	integer timeout = 0;
	reg     has_bootrom = 0;
	reg     last_rst = 0;

	if (RESET) last_rst = 0;
	if (status[0]) last_rst = 1;

	if (cart_download & ioctl_wr & status[0]) has_bootrom <= 1;

	if(last_rst & ~status[0]) begin
		osd_btn <= 0;
		if(timeout < 24000000) begin
			timeout <= timeout + 1;
			osd_btn <= ~has_bootrom;
		end
	end
end

///////////////////////////////////////////////////

wire reset = RESET | status[0] | buttons[1] | region_set_rst;

reg sys_reset;
always @(posedge clk_sys) sys_reset <= reset|cart_download;

reg        md_reset;
reg [15:1] ram_rst_a;
always @(posedge clk_md) begin
	reg [1:0] cnt = 0;
	
	ram_rst_a <= ram_rst_a + 1'd1;
	if(&ram_rst_a & ~&cnt) cnt <= cnt + 1'd1;

	md_reset <= ^cnt | reset;
	if(cart_download) cnt <= 0;
end

reg vclk_en, zclk_en, clk_en;
always @(posedge clk_md) begin
	reg old_vclk, old_zclk;
	
	clk_en <= ~cart_download;
	
	old_vclk <= VCLK;
	if(old_vclk & ~VCLK) vclk_en <= clk_en;

	old_zclk <= ZCLK;
	if(old_zclk & ~ZCLK) zclk_en <= clk_en;
end

always @(posedge clk_md) begin
	reg pause_req;

	pause_req <= OSD_STATUS & status[61];

	if(pause_req & ~md_reset & ~cart_download) begin
		dma_z80_req <= 1;
		if((dma_z80_ack | res_z80) & ~cart_dma) dma_68k_req <= 1;
	end
	else begin
		dma_68k_req <= 0;
		dma_z80_req <= 0;
	end
end

///////////////////////////////////////////////////

wire        PAL = status[7];
wire        JAP = !status[7:6];

wire [15:0] cart_data;
wire [23:1] cart_addr;
wire        cart_cs, cart_oe, cart_lwr, cart_uwr, cart_data_en, cart_dtack, cart_time, cart_dma;
wire [15:0] cart_data_wr;

wire        vdp_hclk1;
wire        vdp_de_h;
wire        vdp_de_v;
wire        vdp_intfield;
wire        vdp_m2, vdp_m5, vdp_rs1;
wire  [7:0] r,g,b;
wire        hs, vs;

wire  [6:0] PA_d, PA_o, PB_d, PB_o, PC_d, PC_o;
wire  [6:0] PA_i, PB_i, PC_i;

wire  [8:0] MOL, MOR;
wire  [9:0] MOL_2612, MOR_2612;
wire [15:0] PSG;
wire        fm_clk1;
wire        fm_sel23;

wire [14:0] ram_68k_address;
wire  [1:0] ram_68k_byteena;
wire [15:0] ram_68k_data;
wire        ram_68k_wren;
wire [15:0] ram_68k_o;
wire [12:0] ram_z80_address;
wire  [7:0] ram_z80_data;
wire        ram_z80_wren;
wire  [7:0] ram_z80_o;
wire [15:0] tmss_data;
wire  [9:0] tmss_address;

wire [23:1] m68k_addr;
wire [15:0] m68k_bus_do;
wire [15:0] z80_addr;
wire  [7:0] z80_bus_do;

reg         dma_68k_req;
reg         dma_z80_req;
wire        dma_z80_ack;
wire        res_z80;

wire        VCLK, ZCLK;

md_board md_board
(
	.MCLK2(clk_md),

	.ext_reset(md_reset),

	// ram
	.ram_68k_address(ram_68k_address),
	.ram_68k_byteena(ram_68k_byteena),
	.ram_68k_data(ram_68k_data),
	.ram_68k_wren(ram_68k_wren),
	.ram_68k_o(ram_68k_o),
	.ram_z80_address(ram_z80_address),
	.ram_z80_data(ram_z80_data),
	.ram_z80_wren(ram_z80_wren),
	.ram_z80_o(ram_z80_o),

	// cheat engine
	.m68k_addr(m68k_addr),
	.m68k_bus_do(m68k_bus_do),
	.m68k_di(m68k_data),
	.z80_addr(z80_addr),
	.z80_bus_do(z80_bus_do),
	.z80_di(z80_data),

	.tmss_enable(tmss_enable & tmss_loaded),
	.tmss_data(tmss_data),
	.tmss_address(tmss_address),

	.ext_VCLK_o(VCLK),
	.ext_ZCLK_o(ZCLK),
	.ext_VCLK_i(VCLK & vclk_en),
	.ext_ZCLK_i(ZCLK & zclk_en),

	// cart
	.M3(~cart_ms),
	.cart_address(cart_addr),
	.cart_data(cart_data),
	.cart_data_en(cart_data_en),
	.cart_data_wr(cart_data_wr),
	.cart_cs(cart_cs),
	.cart_oe(cart_oe),
	.cart_lwr(cart_lwr),
	.cart_uwr(cart_uwr),
	.cart_time(cart_time),
	.cart_m3_pause(joystick_0[7] | joystick_1[7] | joystick_2[7] | joystick_3[7] | joystick_4[7]),
	.cart_dma(cart_dma),
	.ext_dtack(cart_dtack),
	.pal(PAL),
	.jap(JAP),

	// video
	.V_R(r),
	.V_G(g),
	.V_B(b),
	.V_HS(hs),
	.V_VS(vs),
	
	// audio
	.MOL(MOL),
	.MOR(MOR),
	.MOL_2612(MOL_2612),
	.MOR_2612(MOR_2612),
	.PSG(PSG),
	.fm_clk1(fm_clk1),
	.fm_sel23(fm_sel23),

	// pads
	.PA_i(PA_i),
	.PA_o(PA_o),
	.PA_d(PA_d), // 1 - input, 0 - output
	.PB_i(PB_i),
	.PB_o(PB_o),
	.PB_d(PB_d),
	.PC_i(PC_i),
	.PC_o(PC_o),
	.PC_d(PC_d),

	// helpers
	.vdp_hclk1(vdp_hclk1),
	.vdp_intfield(vdp_intfield),
	.vdp_de_h(vdp_de_h),
	.vdp_de_v(vdp_de_v),
	.vdp_m2(vdp_m2),
	.vdp_m5(vdp_m5),
	.vdp_rs1(vdp_rs1),
	.vdp_cramdot_dis(~status[10]),
	.ym2612_status_enable(ym2612_quirk),
	
	.dma_68k_req(dma_68k_req),
	.dma_z80_req(dma_z80_req),
	.dma_z80_ack(dma_z80_ack),
	.res_z80(res_z80)
);

dpram #(15,16) ram_68k
(
	.clock(clk_md),

	.address_a(ram_68k_address),
	.data_a(ram_68k_data),
	.wren_a(ram_68k_wren),
	.byteena_a(ram_68k_byteena),
	.q_a(ram_68k_o),

	.address_b(ram_rst_a),
	.wren_b(md_reset)
);

dpram #(13,8) ram_z80k
(
	.clock(clk_md),

	.address_a(ram_z80_address),
	.data_a(ram_z80_data),
	.wren_a(ram_z80_wren),
	.q_a(ram_z80_o),

	.address_b(ram_rst_a),
	.wren_b(md_reset),
	.data_b(8'hC7) // reset instruction to fix Titan 2 bug
);

dpram_difclk #(10,16,10,16) rom_tmss
(
	.clock_a(clk_md),
	.address_a(tmss_address),
	.q_a(tmss_data),

	.clock_b(clk_sys),
	.address_b(ioctl_addr[10:1]),
	.wren_b(ioctl_wr && tmss_download && !ioctl_addr[24:11]),
	.data_b({ioctl_data[7:0],ioctl_data[15:8]})
);

reg tmss_enable = 0;
reg tmss_loaded = 0;
always @(posedge clk_sys) begin
	if(ioctl_wr & tmss_download) tmss_loaded <= 1;
	if(sys_reset) tmss_enable <= status[12];
end

wire [13:0] sms_fm_audio;
wire        gun_type;
wire  [7:0] gun_sensor_delay;
wire        ym2612_quirk;

cartridge cartridge
(
	.*,

	.clk(clk_sys),
	.clk_ram(clk_ram),
	.reset(sys_reset),
	.reset_sdram(~pll_locked),

	.cart_dl(cart_download),
	.cart_dl_addr(ioctl_addr),
	.cart_dl_data(ioctl_data),
	.cart_dl_wr(ioctl_wr),
	.cart_dl_wait(ioctl_wait),

	.cart_ms(cart_ms),
	.cart_addr(cart_addr),
	.cart_data(cart_data),
	.cart_data_en(cart_data_en),
	.cart_data_wr(cart_data_wr),
	.cart_cs(cart_cs),
	.cart_oe(cart_oe),
	.cart_lwr(cart_lwr),
	.cart_uwr(cart_uwr),
	.cart_time(cart_time),
	.cart_dtack(cart_dtack),
	.cart_dma(cart_dma),

	.save_addr({sd_lba[6:0],sd_buff_addr}),
	.save_di(sd_buff_dout),
	.save_do(sd_buff_din),
	.save_wr(sd_buff_wr & sd_ack),
	.save_change(bk_change),

	.jcart_en(status[39]),
	.jcart_mode(status[5]),
	.P3_UP(joystick_2[3]),
	.P3_DOWN(joystick_2[2]),
	.P3_LEFT(joystick_2[1]),
	.P3_RIGHT(joystick_2[0]),
	.P3_A(joystick_2[4]),
	.P3_B(joystick_2[5]),
	.P3_C(joystick_2[6]),
	.P3_START(joystick_2[7]),
	.P3_MODE(joystick_2[8]),
	.P3_X(joystick_2[9]),
	.P3_Y(joystick_2[10]),
	.P3_Z(joystick_2[11]),
	.P4_UP(joystick_3[3]),
	.P4_DOWN(joystick_3[2]),
	.P4_LEFT(joystick_3[1]),
	.P4_RIGHT(joystick_3[0]),
	.P4_A(joystick_3[4]),
	.P4_B(joystick_3[5]),
	.P4_C(joystick_3[6]),
	.P4_START(joystick_3[7]),
	.P4_MODE(joystick_3[8]),
	.P4_X(joystick_3[9]),
	.P4_Y(joystick_3[10]),
	.P4_Z(joystick_3[11]),

	.gun_type(gun_type),
	.gun_sensor_delay(gun_sensor_delay),

	.ym2612_quirk(ym2612_quirk),

	.fm_en(~status[60]),
	.fm_audio(sms_fm_audio)
);


///////////////////////////////////////////////////

reg new_vmode;
always @(posedge clk_sys) begin
	reg old_pal;
	int to;

	if(~sys_reset) begin
		old_pal <= PAL;
		if(old_pal != PAL) to <= 5000000;
	end
	else to <= 5000000;

	if(to) begin
		to <= to - 1;
		if(to == 1) new_vmode <= ~new_vmode;
	end
end

wire       ce_pix;
wire       f1;
wire       interlace;
wire       vblank_c, hblank_c, hs_c, vs_c;
wire [7:0] r_c, g_c, b_c;
wire[11:0] arx,ary;

video_cond video_cond
(
	.clk(CLK_VIDEO),

	.vdp_hclk1(vdp_hclk1),
	.vdp_de_h(vdp_de_h),
	.vdp_de_v(vdp_de_v),
	.vdp_intfield(vdp_intfield),
	.vdp_m2(vdp_m2),
	.vdp_m5(vdp_m5),
	.vdp_rs1(vdp_rs1),

	.r_in(r),
	.g_in(g),
	.b_in(b),
	.hs_in(hs),
	.vs_in(vs),

	.pal(PAL),
	.border_en(status[29]),
	.h40corr(status[30]),
	.blender(status[46]),

	.arx(arx),
	.ary(ary),

	.ce_pix(ce_pix),
	.interlace(interlace),
	.f1(f1),

	.r_out(r_c),
	.g_out(g_c),
	.b_out(b_c),
	.hs_out(hs_c),
	.vs_out(vs_c),
	.hbl_out(hblank_c),
	.vbl_out(vblank_c)
);

wire [2:0] scale = status[3:1];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;

assign VGA_SL = {~interlace,~interlace}&sl[1:0];
assign VGA_F1 = f1;

video_mixer #(.LINE_LENGTH(400), .GAMMA(1)) video_mixer
(
	.*,

	.scandoubler(~interlace && (scale || forced_scandoubler)),
	.hq2x(scale==1),
	.freeze_sync(),

	.VGA_DE(vga_de),
	.R((lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[0]}} : r_c),
	.G((lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[1]}} : g_c),
	.B((lg_target && gun_mode && (~&status[44:43])) ? {8{lg_target[2]}} : b_c),

	// Positive pulses.
	.HSync(hs_c),
	.VSync(vs_c),
	.HBlank(hblank_c),
	.VBlank(vblank_c)
);


///////////////////////////////////////////////////

audio_cond audio_cond
(
	.clk(clk_sys),
	.reset(sys_reset | ~clk_en | dma_z80_req),

	.lpf_mode(status[15:14]),
	.fm_mode(status[11]),

	.fm_clk1(fm_clk1),
	.fm_sel23(fm_sel23),
	.MOL(MOL),
	.MOR(MOR),
	.MOL_2612(MOL_2612),
	.MOR_2612(MOR_2612),
	.PSG(PSG),
	.sms_fm_audio(sms_fm_audio),

	.AUDIO_L(AUDIO_L),
	.AUDIO_R(AUDIO_R)
);

assign AUDIO_MIX = status[58:57];


///////////////////////////////////////////////////

reg  [1:0] region_req;
reg        region_set = 0;
reg        region_set_rst = 0;

wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state, old_ready = 0;
	old_state <= ps2_key[10];

	if(old_state != ps2_key[10]) begin
		casex(code)
			'h005: begin region_req <= 0; region_set_rst <= pressed; region_set <= pressed; end // F1
			'h006: begin region_req <= 1; region_set_rst <= pressed; region_set <= pressed; end // F2
			'h004: begin region_req <= 2; region_set_rst <= pressed; region_set <= pressed; end // F3
		endcase
	end

	old_ready <= cart_hdr_ready;
	if(~cart_ms & ~status[9] & ~old_ready & cart_hdr_ready) begin
		if(~status[8]) begin
			region_set <= 1;
			case(status[28:27])
				0: if(hdr_u) region_req <= 1;
					else if(hdr_e) region_req <= 2;
					else if(hdr_j) region_req <= 0;
					else region_req <= 1;

				1: if(hdr_e) region_req <= 2;
					else if(hdr_u) region_req <= 1;
					else if(hdr_j) region_req <= 0;
					else region_req <= 2;

				2: if(hdr_u) region_req <= 1;
					else if(hdr_j) region_req <= 0;
					else if(hdr_e) region_req <= 2;
					else region_req <= 1;

				3: if(hdr_j) region_req <= 0;
					else if(hdr_u) region_req <= 1;
					else if(hdr_e) region_req <= 2;
					else region_req <= 0;
			endcase
		end
		else begin
			region_set <= |ioctl_index;
			region_req <= ioctl_index[7:6];
		end
	end

	if(old_ready & ~cart_hdr_ready) region_set <= 0;
end

wire [3:0] hrgn = ioctl_data[3:0] - 4'd7;

reg cart_hdr_ready = 0;
reg hdr_j=0,hdr_u=0,hdr_e=0;
always @(posedge clk_sys) begin
	reg old_download;
	old_download <= cart_download;

	if(~old_download && cart_download) {hdr_j,hdr_u,hdr_e} <= 0;
	if(old_download && ~cart_download) cart_hdr_ready <= 0;

	if(ioctl_wr & cart_download) begin
		if(ioctl_addr == 'h1F0) begin
			if(ioctl_data[7:0] == "J") hdr_j <= 1;
			else if(ioctl_data[7:0] == "U") hdr_u <= 1;
			else if(ioctl_data[7:0] == "E") hdr_e <= 1;
			else if(ioctl_data[7:0] >= "0" && ioctl_data[7:0] <= "9") {hdr_e, hdr_u, hdr_j} <= {ioctl_data[3], ioctl_data[2], ioctl_data[0]};
			else if(ioctl_data[7:0] >= "A" && ioctl_data[7:0] <= "F") {hdr_e, hdr_u, hdr_j} <= {      hrgn[3],       hrgn[2],       hrgn[0]};
		end
		if(ioctl_addr == 'h1F2) begin
			if(ioctl_data[7:0] == "J") hdr_j <= 1;
			else if(ioctl_data[7:0] == "U") hdr_u <= 1;
			else if(ioctl_data[7:0] == "E") hdr_e <= 1;
		end
		if(ioctl_addr == 'h1F0) begin
			if(ioctl_data[15:8] == "J") hdr_j <= 1;
			else if(ioctl_data[15:8] == "U") hdr_u <= 1;
			else if(ioctl_data[15:8] == "E") hdr_e <= 1;
		end
		if(ioctl_addr == 'h200) cart_hdr_ready <= 1;
	end
end

///////////////////////////////////////////////////

wire [11:0] joy0 = status[4] ? joystick_1[11:0] : joystick_0[11:0];
wire [11:0] joy1 = status[4] ? joystick_0[11:0] : joystick_1[11:0];

wire [6:0] md_io_port1, md_io_port2;

md_io md_io
(
	.clk(clk_sys),
	.reset(sys_reset),

	.MODE(status[5]),
	.SMS(cart_ms /*& ~status[59]*/),
	.MULTITAP(cart_ms ? {|status[39:37], 1'b0} : status[38:37]),

	.P1_UP(joy0[3]),
	.P1_DOWN(joy0[2]),
	.P1_LEFT(joy0[1]),
	.P1_RIGHT(joy0[0]),
	.P1_A(joy0[4]),
	.P1_B(joy0[5]),
	.P1_C(joy0[6]),
	.P1_START(joy0[7]),
	.P1_MODE(joy0[8]),
	.P1_X(joy0[9]),
	.P1_Y(joy0[10]),
	.P1_Z(joy0[11]),

	.P2_UP(joy1[3]),
	.P2_DOWN(joy1[2]),
	.P2_LEFT(joy1[1]),
	.P2_RIGHT(joy1[0]),
	.P2_A(joy1[4]),
	.P2_B(joy1[5]),
	.P2_C(joy1[6]),
	.P2_START(joy1[7]),
	.P2_MODE(joy1[8]),
	.P2_X(joy1[9]),
	.P2_Y(joy1[10]),
	.P2_Z(joy1[11]),

	.P3_UP(joystick_2[3]),
	.P3_DOWN(joystick_2[2]),
	.P3_LEFT(joystick_2[1]),
	.P3_RIGHT(joystick_2[0]),
	.P3_A(joystick_2[4]),
	.P3_B(joystick_2[5]),
	.P3_C(joystick_2[6]),
	.P3_START(joystick_2[7]),
	.P3_MODE(joystick_2[8]),
	.P3_X(joystick_2[9]),
	.P3_Y(joystick_2[10]),
	.P3_Z(joystick_2[11]),

	.P4_UP(joystick_3[3]),
	.P4_DOWN(joystick_3[2]),
	.P4_LEFT(joystick_3[1]),
	.P4_RIGHT(joystick_3[0]),
	.P4_A(joystick_3[4]),
	.P4_B(joystick_3[5]),
	.P4_C(joystick_3[6]),
	.P4_START(joystick_3[7]),
	.P4_MODE(joystick_3[8]),
	.P4_X(joystick_3[9]),
	.P4_Y(joystick_3[10]),
	.P4_Z(joystick_3[11]),

	.P5_UP(joystick_4[3]),
	.P5_DOWN(joystick_4[2]),
	.P5_LEFT(joystick_4[1]),
	.P5_RIGHT(joystick_4[0]),
	.P5_A(joystick_4[4]),
	.P5_B(joystick_4[5]),
	.P5_C(joystick_4[6]),
	.P5_START(joystick_4[7]),
	.P5_MODE(joystick_4[8]),
	.P5_X(joystick_4[9]),
	.P5_Y(joystick_4[10]),
	.P5_Z(joystick_4[11]),

	.GUN_OPT(|gun_mode),
	.GUN_TYPE(gun_type),
	.GUN_SENSOR(lg_sensor),
	.GUN_A(lg_a),
	.GUN_B(lg_b),
	.GUN_C(lg_c),
	.GUN_START(lg_start),

	.MOUSE(ps2_mouse),
	.MOUSE_OPT(status[20:18]),

	.port1_out(md_io_port1),
	.port1_in(PA_o  | {7{snac_port1}}),
	.port1_dir(PA_d | {7{snac_port1}}),

	.port2_out(md_io_port2),
	.port2_in(PB_o  | {7{snac_port2}}),
	.port2_dir(PB_d | {7{snac_port2}})
);

wire [2:0] lg_target;
wire       lg_sensor;
wire       lg_a;
wire       lg_b;
wire       lg_c;
wire       lg_start;

lightgun lightgun
(
	.CLK(clk_sys),
	.RESET(sys_reset),

	.MOUSE(ps2_mouse),
	.MOUSE_XY(&gun_mode),

	.JOY_X(gun_mode[0] ? joy0_x : joy1_x),
	.JOY_Y(gun_mode[0] ? joy0_y : joy1_y),
	.JOY(gun_mode[0] ? joystick_0 : joystick_1),

	.RELOAD(gun_type),

	.HDE(~hblank_c),
	.VDE(~vblank_c),
	.CE_PIX(ce_pix),
	.H40(vdp_rs1),

	.BTN_MODE(gun_btn_mode),
	.SIZE(status[44:43]),
	.SENSOR_DELAY(gun_sensor_delay),

	.TARGET(lg_target),
	.SENSOR(lg_sensor),
	.BTN_A(lg_a),
	.BTN_B(lg_b),
	.BTN_C(lg_c),
	.BTN_START(lg_start)
);

wire [6:0] SNAC_IN;
wire [6:0] SNAC_OUT;
always_comb begin
	SNAC_IN[0]  = USER_IN[1]; //up
	SNAC_IN[1]  = USER_IN[0]; //down
	SNAC_IN[2]  = USER_IN[5]; //left
	SNAC_IN[3]  = USER_IN[3]; //right
	SNAC_IN[4]  = USER_IN[2]; //b TL
	SNAC_IN[5]  = USER_IN[6]; //c TR GPIO7
	SNAC_IN[6]  = USER_IN[4]; //  TH
	USER_OUT[1] = SNAC_OUT[0];
	USER_OUT[0] = SNAC_OUT[1];
	USER_OUT[5] = SNAC_OUT[2];
	USER_OUT[3] = SNAC_OUT[3];
	USER_OUT[2] = SNAC_OUT[4];
	USER_OUT[6] = SNAC_OUT[5];
	USER_OUT[4] = SNAC_OUT[6];
end

wire snac_port1 = (status[63:62] == 1);
assign PA_i = snac_port1 ? SNAC_IN : md_io_port1;

wire snac_port2 = (status[63:62] == 2);
assign PB_i = snac_port2 ? SNAC_IN : md_io_port1;

wire snac_port3 = (status[63:62] == 3);
assign PC_i = snac_port3 ? SNAC_IN : (PC_d | PC_o);

assign SNAC_OUT = snac_port1 ? (PA_d | PA_o) : snac_port2 ? (PB_d | PB_o) : snac_port3 ? (PC_d | PC_o) : 7'h7F;

/////////////////////////  BRAM SAVE/LOAD  /////////////////////////////

wire downloading = cart_download;

reg bk_ena = 0;
reg sav_pending = 0;
wire bk_change;

always @(posedge clk_sys) begin
	reg old_downloading = 0;
	reg old_change = 0;

	old_downloading <= downloading;
	if(~old_downloading & downloading) bk_ena <= 0;

	//Save file always mounted in the end of downloading state.
	if(downloading && img_mounted && !img_readonly) bk_ena <= 1;

	old_change <= bk_change;
	if (~old_change & bk_change & ~OSD_STATUS) sav_pending <= status[13];
	else if (bk_state) sav_pending <= 0;
end

wire bk_load    = status[16];
wire bk_save    = status[17] | (sav_pending & OSD_STATUS);
reg  bk_loading = 0;
reg  bk_state   = 0;

always @(posedge clk_sys) begin
	reg old_downloading = 0;
	reg old_load = 0, old_save = 0, old_ack;

	old_downloading <= downloading;

	old_load <= bk_load;
	old_save <= bk_save;
	old_ack  <= sd_ack;

	if(~old_ack & sd_ack) {sd_rd, sd_wr} <= 0;

	if(!bk_state) begin
		if(bk_ena & ((~old_load & bk_load) | (~old_save & bk_save))) begin
			bk_state <= 1;
			bk_loading <= bk_load;
			sd_lba <= 0;
			sd_rd <=  bk_load;
			sd_wr <= ~bk_load;
		end
		if(old_downloading & ~downloading & |img_size & bk_ena) begin
			bk_state <= 1;
			bk_loading <= 1;
			sd_lba <= 0;
			sd_rd <= 1;
			sd_wr <= 0;
		end
	end else begin
		if(old_ack & ~sd_ack) begin
			if(&sd_lba[6:0]) begin
				bk_loading <= 0;
				bk_state <= 0;
			end else begin
				sd_lba <= sd_lba + 1'd1;
				sd_rd  <=  bk_loading;
				sd_wr  <= ~bk_loading;
			end
		end
	end
end


///////////////////////////////////////////////////
// Cheat codes loading for WIDE IO (16 bit)
reg [128:0] gg_code;
wire        gg_available;

// Code layout:
// {clock bit, code flags,     32'b address, 32'b compare, 32'b replace}
//  128        127:96          95:64         63:32         31:0
// Integer values are in BIG endian byte order, so it up to the loader
// or generator of the code to re-arrange them correctly.

always_ff @(posedge clk_sys) begin
	gg_code[128] <= 1'b0;

	if (code_download & ioctl_wr) begin
		case (ioctl_addr[3:0])
			0:  gg_code[111:96]  <= ioctl_data; // Flags Bottom Word
			2:  gg_code[127:112] <= ioctl_data; // Flags Top Word
			4:  gg_code[79:64]   <= ioctl_data; // Address Bottom Word
			6:  gg_code[95:80]   <= ioctl_data; // Address Top Word
			8:  gg_code[47:32]   <= ioctl_data; // Compare Bottom Word
			10: gg_code[63:48]   <= ioctl_data; // Compare top Word
			12: gg_code[15:0]    <= ioctl_data; // Replace Bottom Word
			14: begin
				gg_code[31:16]   <= ioctl_data; // Replace Top Word
				gg_code[128]     <=  1'b1;      // Clock it in
			end
		endcase
	end
end

reg [15:0] m68k_data;
always @(posedge clk_md) m68k_data <= m68k_genie_data;

wire [15:0] m68k_genie_data;
CODES #(.ADDR_WIDTH(24), .DATA_WIDTH(16), .BIG_ENDIAN(1)) codes_68k
(
	.clk(clk_sys),
	.reset(cart_download | (code_download && ioctl_wr && !ioctl_addr)),
	.enable(~status[24] & ~cart_ms),
	.code(gg_code),
	.available(gg_available),
	.addr_in({m68k_addr, 1'b0}),
	.data_in(m68k_bus_do),
	.data_out(m68k_genie_data)
);

reg [7:0] z80_data;
always @(posedge clk_md) z80_data <= z80_genie_data;

wire [7:0] z80_genie_data;
CODES #(.ADDR_WIDTH(16), .DATA_WIDTH(8)) codes_z80
(
	.clk(clk_sys),
	.reset(cart_download | (code_download && ioctl_wr && !ioctl_addr)),
	.enable(~status[24] & cart_ms),
	.code(gg_code),
	.addr_in(z80_addr),
	.data_in(z80_bus_do),
	.data_out(z80_genie_data)
);

endmodule
