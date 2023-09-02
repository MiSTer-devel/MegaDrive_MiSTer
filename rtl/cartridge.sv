//============================================================================
//  Megadrive/Master Cartridge implementation
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

module cartridge
(
	input             clk,
	input             clk_ram,
	input             reset,
	input             reset_sdram,

	output            SDRAM_CLK,
	output            SDRAM_CKE,
	output     [12:0] SDRAM_A,
	output      [1:0] SDRAM_BA,
	inout      [15:0] SDRAM_DQ,
	output            SDRAM_DQML,
	output            SDRAM_DQMH,
	output            SDRAM_nCS,
	output            SDRAM_nCAS,
	output            SDRAM_nRAS,
	output            SDRAM_nWE,

	input             cart_dl,
	input      [24:0] cart_dl_addr,
	input      [15:0] cart_dl_data,
	input             cart_dl_wr,
	output reg        cart_dl_wait,

	input             cart_ms,
	input      [23:1] cart_addr,
	output reg [15:0] cart_data,
	input      [15:0] cart_data_wr,
	input             cart_cs,
	input             cart_oe,
	input             cart_lwr,
	input             cart_uwr,
	input             cart_time,
	output            cart_data_en,
	output            cart_dtack,
	input             cart_dma,

	input      [14:0] save_addr,
	input      [15:0] save_di,
	output     [15:0] save_do,
	input             save_wr,
	output            save_change,

	input             jcart_en,
	input             jcart_mode,

	input             P3_UP,
	input             P3_DOWN,
	input             P3_LEFT,
	input             P3_RIGHT,
	input             P3_A,
	input             P3_B,
	input             P3_C,
	input             P3_START,
	input             P3_MODE,
	input             P3_X,
	input             P3_Y,
	input             P3_Z,

	input             P4_UP,
	input             P4_DOWN,
	input             P4_LEFT,
	input             P4_RIGHT,
	input             P4_A,
	input             P4_B,
	input             P4_C,
	input             P4_START,
	input             P4_MODE,
	input             P4_X,
	input             P4_Y,
	input             P4_Z,

	output reg        gun_type,
	output reg  [7:0] gun_sensor_delay,

	output            ym2612_quirk,

	input             fm_en,
	output     [13:0] fm_audio
);

sdram sdram
(
	.*,
	.init(reset_sdram),
	.clk(clk_ram),

	.addr0(cart_wr_addr),
	.din0({cart_dl_data[7:0], cart_wr_addr0 ? cart_dl_data[7:0] : cart_dl_data[15:8]}),
	.dout0(),
	.wrl0(1),
	.wrh0(1),
	.req0(rom_wr),
	.ack0(rom_wrack),

	.addr1(rom_addr),
	.dout1(rom_data),
	.din1(cart_data_wr),
	.wrl1(cart_lwr & ~rom_rd),
	.wrh1(cart_uwr & ~rom_rd),
	.req1(rom_req),
	.ack1(rom_ack),

	.addr2(rom2_a),
	.din2(0),
	.dout2(rom2_data),
	.wrl2(0),
	.wrh2(0),
	.req2(rom2_req),
	.ack2(rom2_ack)
);

reg        cart_wr_addr0;
reg        rom_wr = 0;
wire       rom_wrack;
reg [24:1] rom_mask;
reg [25:1] rom_sz;
reg [26:0] cart_wr_addr;

always @(posedge clk) begin
	reg old_dl, old_reset;

	old_reset <= reset;
	if(~old_reset && reset) cart_dl_wait <= 0;
	
	old_dl <= cart_dl;
	if(~old_dl & cart_dl) begin
		rom_mask <= 0;
		cart_wr_addr <= 0;
		rom_sz <= 0;
	end

	if (cart_dl & cart_dl_wr) begin
		cart_dl_wait <= 1;
		cart_wr_addr0 <= cart_ms;
		rom_wr <= ~rom_wr;
		cart_wr_addr <= rom_sz;
		rom_mask <= rom_mask | rom_sz[24:1];
		rom_sz <= rom_sz + 1'd1;
	end
	else if(rom_wr == rom_wrack) begin
		if(cart_wr_addr0) begin
			cart_wr_addr0 <= 0;
			rom_wr <= ~rom_wr;
			cart_wr_addr <= rom_sz;
			rom_mask <= rom_mask | rom_sz[24:1];
			rom_sz <= rom_sz + 1'd1;
		end
		else begin
			cart_dl_wait <= 0;
		end
	end
end


//--------------------- all carts --------------------------------------

assign cart_dtack   = svp_cs | dtack_ext;
assign cart_data_en = cart_oe & (cart_cs | svp_cs | data_en);
wire   rom_data_req = (cart_cs | ms_rom_cs | cart_cs_ext) & ~svp_norom;

reg data_en;
always @(posedge clk_ram) data_en <= ms_rom_cs | ms_ram_cs | fm_det_cs | pier_eeprom_cs | cart_cs_ext;

reg  [24:1] rom_addr;
reg         rom_req;
wire        rom_ack;
wire [15:0] rom_data;
reg         rom_rd;
reg         dtack_ext;

always @(posedge clk_ram) begin
	reg oe_old, we_old;
	
	if(~cart_oe) dtack_ext <= 0;

	if(rom_req == rom_ack) begin
		if(rom_rd) begin
			cart_data <= rom_data;
			if(cart_cs_ext) dtack_ext <= 1;
		end
		rom_rd <= 0;
	end

	we_old <= rom_we;
	oe_old <= cart_oe;
	if((~oe_old & cart_oe & rom_data_req) || (~we_old & rom_we)) begin
		rom_addr <= (cart_ms ? ms_cart_addr : md_cart_addr) & rom_mask[24:1];
		rom_req <= ~rom_req;
		rom_rd <= cart_oe;
	end

	if(ms_boot_cs)     cart_data <= ms_boot_data;
	if(ms_ram_cs)      cart_data <= sram_q;
	if(fm_det_cs)      cart_data <= fm_det_data;
	if(md_sram_cs)     cart_data <= {sram_q,sram_q};
	if(pier_prot_cs)   cart_data <= pier_prot_data;
	if(pier_eeprom_cs) cart_data <= pier_eeprom_data;
	if(md_eeprom_cs)   cart_data <= md_eeprom_data;
	if(jcart_cs)       cart_data <= jcart_data;
	if(svp_cs)         cart_data <= svp_data;
end

wire [15:0] sram_addr;
wire  [7:0] sram_di;
wire  [7:0] sram_q;
wire        sram_wren;

always_comb begin
	if(cart_ms) begin
		sram_addr = {ms_ram_p & ~ms_addr[14], ms_addr[13:0]};
		sram_di   = cart_data_wr[7:0];
		sram_wren = cart_lwr & ms_ram_cs;
	end
	else if(pier_quirk) begin
		sram_addr = m95_addr;
		sram_di   = m95_di;
		sram_wren = m95_rnw;
	end
	else if(eeprom_quirk) begin
		sram_addr = eeprom_ram_a;
		sram_di   = eeprom_ram_d;
		sram_wren = eeprom_ram_we;
	end
	else begin
		sram_addr = cart_addr[16:1];
		sram_di   = cart_data_wr[7:0];
		sram_wren = md_sram_cs & cart_lwr;
	end
end

wire [15:0] dram_q;

dpram_dif #(17,8,16,16) ram
(
	.clock(clk),
	.address_a(sram_addr),
	.data_a(sram_di),
	.wren_a(sram_wren & ~svp_quirk),
	.q_a(sram_q),

	.address_b(cart_dl ? ram_rst_a : svp_quirk ? svp_dram_a : save_addr),
	.data_b(cart_dl ? (sram00_quirk ? 16'h0000 : 16'hFFFF) : svp_quirk ? svp_dram_do : save_di),
	.wren_b(cart_dl | (svp_quirk ? svp_dram_we : save_wr)),
	.q_b(dram_q)
);

assign save_do     = dram_q;
assign save_change = sram_wren & ~svp_quirk;

//---------------------- MD cart ---------------------------------------

reg [5:0] md_bank[8] = '{0,1,2,3,4,5,6,7};
reg       md_bank_sram = 0;
reg       md_bank_use = 0;

always @(posedge clk) begin
	if(reset) begin
		md_bank <= '{0,1,2,3,4,5,6,7};
		md_bank_sram <= 0;
		md_bank_use <= 0;
	end
	else if (cart_lwr && cart_time) begin
		if(rom_mask[24:22]) begin
			if(cart_addr[3:1]) begin
				md_bank_use <= 1;
				if(~pier_quirk) md_bank[cart_addr[3:1]] <= cart_data_wr[5:0]; //SSF2 banks
				else if(cart_addr[3:1] == 4) {ep_cs, ep_hold , ep_sck, ep_si} <= cart_data_wr[3:0]; // Pier EEPROM
				else if(~cart_addr[3]) md_bank[{1'b1,cart_addr[2:1]}] <= cart_data_wr[3:0]; // Pier Banks
			end
			else if(~pier_quirk) md_bank_sram <= cart_data_wr[0];
		end
		else if(~schan_quirk) md_bank_sram <= cart_data_wr[0];
	end
end

wire [24:1] md_cart_addr = svp_dma       ? (cart_addr - 1'd1) :
                           realtec_quirk ? realtec_addr       :
                           md_bank_use   ? {md_bank[cart_addr[21:19]], cart_addr[18:1]} :
                                           cart_addr;


// SVP
wire        svp_dma = svp_quirk & cart_dma;
wire        svp_cs  = svp_quirk & ~svp_dtack_n;
wire        svp_norom = svp_quirk && (cart_addr[23:20] >= 3);

wire [20:1] rom2_a;
wire [15:0] rom2_data;
wire        rom2_req;
wire        rom2_ack;

wire [15:0] svp_data;
wire        svp_dtack_n;

wire [15:0] svp_dram_a;
wire [15:0] svp_dram_do;
wire        svp_dram_we;

reg svp_ce;
always @(posedge clk) svp_ce <= ~reset & ~svp_ce;

SVP svp
(
	.CLK(clk),
	.CE(svp_ce),
	.RST_N(~reset & svp_quirk),
	.ENABLE(1),

	.BUS_A(cart_addr[23:1]),
	.BUS_DO(svp_data),
	.BUS_DI(cart_data_wr),
	.BUS_SEL(cart_oe | cart_lwr),
	.BUS_RNW(~cart_lwr),
	.BUS_DTACK_N(svp_dtack_n),
	.DMA_ACTIVE(cart_dma),

	.ROM_A(rom2_a),
	.ROM_DI(rom2_data),
	.ROM_REQ(rom2_req),
	.ROM_ACK(rom2_ack),

	.DRAM_A(svp_dram_a),
	.DRAM_DI(dram_q),
	.DRAM_DO(svp_dram_do),
	.DRAM_WE(svp_dram_we)
);

// SRAM
reg [16:1] ram_rst_a;
always @(posedge clk) ram_rst_a <= ram_rst_a + 1'd1;

wire md_sram_cs1 = cart_addr[23:21] == 1 && (md_bank_sram || (cart_addr >= rom_sz && ~&cart_addr[20:19] && ~noram_quirk));
wire md_sram_cs2 = (sram_quirk | sram00_quirk) && cart_addr == 'h100000;
wire md_sram_cs  = ~cart_ms & (md_sram_cs1 | md_sram_cs2);

// EEPROM
wire        md_eeprom_cs   = (eeprom_quirk[2:0] && (eeprom_bank || !eeprom_quirk[3])) && cart_addr[23:21] == 3'b001;
wire [15:0] md_eeprom_data = {16{eeprom_sdao & eeprom_sdai}};

reg         eeprom_sdai;
wire        eeprom_sdao;
reg         eeprom_scl;
wire [14:0] eeprom_ram_a;
wire  [7:0] eeprom_ram_d;
wire        eeprom_ram_we;
wire  [7:0] eeprom_ram_q;
reg         eeprom_bank;
always @(posedge clk) begin
	if(reset || !eeprom_quirk) begin
		eeprom_bank <= 0;
		eeprom_sdai <= 1;
		eeprom_scl  <= 1;
	end
	else begin
		if(cart_addr[23:21] == 3'b001 && cart_cs && (cart_lwr | cart_uwr)) begin
			if(cart_lwr & cart_uwr) eeprom_bank <= ~cart_data_wr[0];
			case (eeprom_quirk)
				4'b0001: if(cart_lwr) {eeprom_sdai,eeprom_scl} <= cart_data_wr[7:6];
				4'b0010,
				4'b0011: if(cart_lwr) {eeprom_scl,eeprom_sdai} <= cart_data_wr[1:0];
				4'b1011: if      ( cart_lwr & ~cart_uwr) eeprom_sdai <= cart_data_wr[0];
							else if (~cart_lwr &  cart_uwr) eeprom_scl  <= cart_data_wr[8];
				default: {eeprom_scl,eeprom_sdai} <= '1;//todo 4'b1100-4'b1101
			endcase
		end
	end
end

EPPROM_24CXX e24cxx
(
	.clk(clk),
	.rst(reset),
	.en(md_eeprom_cs && cart_cs),
	
	.mode(eeprom_quirk[2:0] <= 3'b010 ? 2'd0    : 2'd1),
	.mask(eeprom_quirk[2:0] <= 3'b010 ? 13'h07f : 13'h0ff),
	
	.sda_i(eeprom_sdai),
	.sda_o(eeprom_sdao),
	.scl(eeprom_scl),

	.ram_addr(eeprom_ram_a),
	.ram_d(eeprom_ram_d),
	.ram_wr(eeprom_ram_we),
	.ram_q(sram_q)
);


// PIER EEPROM
reg         ep_si, m95_so, ep_sck, ep_hold, ep_cs;
wire  [7:0] m95_di, m95_q;
wire [11:0] m95_addr;
wire        m95_rnw;

STM95XXX pier_eeprom
(
	.clk(clk),
	.enable(pier_quirk),
	.so(m95_so),
	.si(ep_si),
	.sck(ep_sck),
	.hold_n(ep_hold),
	.cs_n(ep_cs),
	.wp_n(1'b1),
	.ram_addr(m95_addr),
	.ram_q(sram_q),
	.ram_di(m95_di),
	.ram_RnW(m95_rnw)
);

wire pier_prot_cs = pier_quirk && (cart_addr == 'hAF3 || cart_addr == 'hAF4);
reg [15:0] pier_prot_data;

always @(posedge clk) begin
	reg [3:0] pier_count;
	reg old_oe;

	old_oe <= cart_oe;
	
	if(reset) pier_count <= 0;
	else if(pier_prot_cs & ~old_oe & cart_oe) begin
		if (pier_count < 6) begin
			pier_count <= pier_count + 1'h1;
			pier_prot_data <= cart_addr[1] ? 16'h0000 : 16'h0010;
		end else begin
			pier_prot_data <= cart_addr[1] ? 16'h0001 : 16'h8010;
		end
	end
end

wire pier_eeprom_cs = pier_quirk && cart_time && cart_addr[3:1] == 'h5;
wire [15:0] pier_eeprom_data = {15'h7FFF, m95_so};

// Sega Channel, 4MB RAM used as ROM
wire rom_we = (cart_lwr || cart_uwr) && !cart_addr[23:22] && ~rom_prot;

reg rom_prot;
always @(posedge clk) begin
	if(reset) rom_prot <= 1;
	else if(schan_quirk && cart_lwr && cart_time && cart_addr[7:1] == 7'b1111000) rom_prot <= cart_data_wr[0];
end

//JCART multitap
wire [15:0] jcart_data;
reg         jcart_th;

pad_io jcart_l
(
	.clk(clk),
	.reset(reset),

	.MODE(jcart_mode),

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

	.MODE(jcart_mode),

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

assign jcart_data[15] = 0;
assign jcart_data[7] = 0;
wire   jcart_cs = ~cart_ms && jcart_en && (cart_addr == 'h1C7FFF || cart_addr == 'h1FFFFF) && cart_addr >= rom_sz;

always @(posedge clk) begin
	if(reset) jcart_th <= 1;
	else if(cart_lwr & jcart_cs) jcart_th <= cart_data_wr[0];
end

// MK3U Trilogy 10MB version (13MB isn't compatible with real HW!)
wire cart_cs_ext = ~cart_ms && (cart_addr[23:22] && cart_addr[23:20]<'hA) && (cart_addr < rom_sz);

// Realtec
reg [21:17] realtec_bank;
reg   [4:0] realtec_mask;
reg         realtec_boot;
always @(posedge clk) begin
	if (reset | ~realtec_quirk) begin
		realtec_bank <= 0;
		realtec_mask <= 0;
		realtec_boot <= 1;
	end
	else begin
		if (cart_addr[23:16] == 8'h40 && !cart_addr[11:1] && cart_uwr) begin
			case(cart_addr[15:12])
				4'h0: begin realtec_bank[21:20] <= cart_data_wr[2:1]; realtec_boot <= ~cart_data_wr[0]; end
				4'h2: begin 
					case (cart_data_wr[5:0])
						6'd0,6'd1:                                      realtec_mask <= 5'b00000;
						6'd2:                                           realtec_mask <= 5'b00001;
						6'd3,6'd4:                                      realtec_mask <= 5'b00011;
						6'd5,6'd6,6'd7,6'd8:                            realtec_mask <= 5'b00111;
						6'd9,6'd10,6'd11,6'd12,6'd13,6'd14,6'd15,6'd16: realtec_mask <= 5'b01111;
						default:                                        realtec_mask <= 5'b11111;
					endcase
				end
				4'h4: begin realtec_bank[19:17] <= cart_data_wr[2:0]; end
			endcase
		end
	end
end

wire [23:1] realtec_addr = realtec_boot ? {11'b00000111111,cart_addr[12:1]} : {2'b00,(cart_addr[21:17] & realtec_mask) + realtec_bank,cart_addr[16:1]};


//---------------------- MS cart ---------------------------------------

wire [15:0] ms_addr = cart_addr[16:1];
wire        mreq_n  = cart_addr[18];
wire        iorq_n  = cart_addr[19];

wire [7:0] ms_boot_data;
spram #(14,8,"rtl/mboot.mif") boot_rom
(
	.clock(clk),
	.address(ms_addr[13:0]),
	.q(ms_boot_data)
);

reg boot_en;
always @(posedge clk) begin
	if(reset) boot_en <= 1;
	else if(cart_lwr && ~iorq_n && !ms_addr[7:6] && !ms_addr[0]) boot_en <= 0;
end

wire ms_boot_cs = !ms_addr[15:14] && boot_en && cart_ms;

wire ms_ram_cs = cart_ms && ~mreq_n && ms_addr[15] && (ms_ram_e[ms_addr[14]] || ((ms_addr[14:13]==1) && ms_ram_c));
wire ms_rom_cs = cart_ms && ~mreq_n && ~&ms_addr[15:14];

reg mapper_codies;
reg mapper_msx;
always @(posedge clk) if(cart_dl && !cart_dl_addr && cart_dl_wr) mapper_msx <= (cart_dl_data == 16'h4241);

reg  [7:0] ms_bank[4];
reg  [7:0] ms_cfg;
wire [1:0] ms_ram_e = ms_cfg[4:3];
wire       ms_ram_p = ms_cfg[2];
reg        ms_ram_c;

always @(posedge clk) begin
	reg lock_mapper_B, mapper_codies_lock;

	if (reset) begin
		ms_bank   <= '{0,1,2,3};
		ms_cfg    <= 0;
		ms_ram_c  <= 0;
		lock_mapper_B <= 0;
		mapper_codies <= 0;
		mapper_codies_lock <= 0;
	end
	else if(cart_lwr && ~mreq_n && rom_mask[24:16]) begin
		if(mapper_msx) begin
			if(!ms_addr[15:2]) ms_bank[ms_addr[1:0]] <= cart_data_wr[7:0];
		end
		else begin
			if(&ms_addr[15:2]) begin
				mapper_codies <= 0;
				if(!ms_addr[1:0]) ms_cfg <= cart_data_wr[7:0];
				else ms_bank[ms_addr[1:0]-1'd1] <= cart_data_wr[7:0];
			end
			if(~ms_ram_e[0]) begin
				case(ms_addr)
					'h0000: 
						if(lock_mapper_B) begin
							ms_bank[0] <= cart_data_wr[7:0];  
							if(cart_data_wr[7:0] && ~mapper_codies_lock) begin
								if(ms_bank[1] == 1) mapper_codies <= 1;
								mapper_codies_lock <= 1;
							end
						end
					'h4000:
						begin
							ms_bank[1] <= cart_data_wr[6:0];
							ms_ram_c <= cart_data_wr[7];
							lock_mapper_B <= 1;
						end
					'h8000:
						begin
							ms_bank[2] <= cart_data_wr[7:0];
							lock_mapper_B <= 1;
						end
					// Korean mapper (Sangokushi 3, Dodgeball King)
					'hA000:
						begin
							if(~mapper_codies) ms_bank[2] <= cart_data_wr[7:0];
						end
				endcase
			end
		end
	end
end

wire [21:0] ms_cart_addr;
always_comb begin
	ms_cart_addr = ms_addr;
	
	if(rom_mask[24:16]) begin
		if(mapper_msx) begin
			case(ms_addr[15:13])
				2,3,4,5: ms_cart_addr[20:13] <= ms_bank[ms_addr[14:13] - 2'd2];
				default:;
			endcase
		end
		else begin
			ms_cart_addr[21:14] = (ms_addr[15:10] || mapper_codies) ? ms_bank[ms_addr[15:14]] : 8'd0;
		end
	end
end

// FM

wire fm_reset = reset | ~fm_en | ~cart_ms;

reg ce_fm;
always @(posedge clk) begin
	reg [3:0] cnt;
	
	cnt <= cnt + 1'd1;
	if(cnt == 14) cnt <= 0;
	ce_fm <= !cnt;
end

reg [7:0] fm_d;
reg       fm_a;
always @(posedge clk) begin
	if(fm_reset) begin
		fm_d <= 0;
		fm_a <= 0;
	end
	else if(cart_ms && cart_lwr && ~iorq_n && ms_addr[7:1] == 7'b1111000) begin
		fm_d <= cart_data_wr[7:0];
		fm_a <= ms_addr[0];
	end
end

opll fm
(
	.xin(clk),
	.xena(ce_fm),
	.d(fm_d),
	.a(fm_a),
	.cs_n(0),
	.we_n(0),
	.ic_n(~fm_reset),
	.mixout(fm_audio)
);

wire fm_det_cs = cart_ms && fm_en && ~iorq_n && ms_addr[7:0] == 8'hF2;

reg [7:0] fm_det_data;
always @(posedge clk) begin
	if(fm_reset) fm_det_data <= 8'hFF;
	else if(cart_lwr & fm_det_cs) fm_det_data[2:0] <= cart_data_wr[2:0];
end

//---------------------- Cart detect ---------------------------------------

reg       sram_quirk, sram00_quirk, fmbusy_quirk, noram_quirk, pier_quirk, svp_quirk, schan_quirk;
reg [3:0] eeprom_quirk;
reg       realtec_quirk;
reg [2:0] sf_quirk;

always @(posedge clk) begin
	reg [87:0] cart_id;
	reg [15:0] crc = 0;
	reg [31:0] realtec_id = 0;
	reg old_dl;
	old_dl <= cart_dl;

	if(~old_dl && cart_dl) begin
		{sram_quirk,sram00_quirk,fmbusy_quirk,noram_quirk,pier_quirk,svp_quirk,schan_quirk,eeprom_quirk,realtec_quirk,sf_quirk} <= 0;
		gun_type <= 0;
		gun_sensor_delay <= 8'd44;
	end

	if(cart_dl_wr & cart_dl & ~cart_ms) begin
		if(cart_dl_addr == 'h180) cart_id[87:72] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h182) cart_id[71:56] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h184) cart_id[55:40] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h186) cart_id[39:24] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h188) cart_id[23:08] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h18A) cart_id[07:00] <= cart_dl_data[7:0];
		if(cart_dl_addr == 'h18E) crc <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h190) begin
			     if(cart_id[63:0] == "T-081276") sram_quirk   <= 1;        // NFL Quarterback Club
			else if(cart_id[63:0] == "T-81406 ") sram_quirk   <= 1;        // NBA Jam TE
			else if(cart_id[63:0] == "T-081586") sram_quirk   <= 1;        // NFL Quarterback Club '96
			else if(cart_id[63:0] == "T-81576 ") sram_quirk   <= 1;        // College Slam
			else if(cart_id[63:0] == "T-81476 ") sram_quirk   <= 1;        // Frank Thomas Big Hurt Baseball
			else if(cart_id[63:0] == "T-50446 ") eeprom_quirk <= 4'b0001; 	// John Madden Football 93
			else if(cart_id[63:0] == "T-50516 ") eeprom_quirk <= 4'b0001; 	// John Madden Football 93 Championship Edition
			else if(cart_id[63:0] == "T-50396 ") eeprom_quirk <= 4'b0001; 	// NHLPA Hockey 93
			else if(cart_id[63:0] == "T-50176 ") eeprom_quirk <= 4'b0001; 	// Rings of Power
			else if(cart_id[63:0] == "T-50606 ") eeprom_quirk <= 4'b0001; 	// Bill Walsh College Football
			else if(cart_id[63:0] == "MK-1215 ") eeprom_quirk <= 4'b0010; 	// Evander Real Deal Holyfield's Boxing
			else if(cart_id[63:0] == "G-4060  ") eeprom_quirk <= 4'b0010; 	// Wonder Boy
			else if(cart_id[63:0] == "00001211") eeprom_quirk <= 4'b0010; 	// Sports Talk Baseball
			else if(cart_id[63:0] == "MK-1228 ") eeprom_quirk <= 4'b0010; 	// Greatest Heavyweights
			else if(cart_id[63:0] == "G-5538  ") eeprom_quirk <= 4'b0010; 	// Greatest Heavyweights JP
			else if(cart_id[63:0] == "00004076") eeprom_quirk <= 4'b0010; 	// Honoo no Toukyuuji Dodge Danpei
			else if(cart_id[63:0] == "T-12046 ") eeprom_quirk <= 4'b0010; 	// Mega Man - The Wily Wars 
			else if(cart_id[63:0] == "T-12053 ") eeprom_quirk <= 4'b0010; 	// Rockman Mega World 
			else if(cart_id[63:0] == "G-4524  ") eeprom_quirk <= 4'b0010; 	// Ninja Burai Densetsu
			else if(cart_id[63:0] == "00054503") eeprom_quirk <= 4'b0010; 	// Game Toshokan
			else if(cart_id[63:0] == "T-81033 ") eeprom_quirk <= 4'b0011; 	// NBA Jam (J)
			else if(cart_id[63:0] == "T-081326") eeprom_quirk <= 4'b0011; 	// NBA Jam (U)(E)
			else if(cart_id[63:0] == "T-081276") eeprom_quirk <= 4'b1011; 	// NFL Quarterback Club
			else if(cart_id[63:0] == "T-81406 ") eeprom_quirk <= 4'b1011; 	// NBA Jam TE
			else if(cart_id[63:0] == "T-081586") eeprom_quirk <= 4'b1100; 	// NFL Quarterback Club '96
			else if(cart_id[63:0] == "T-81576 ") eeprom_quirk <= 4'b1101; 	// College Slam
			else if(cart_id[63:0] == "T-81476 ") eeprom_quirk <= 4'b1101; 	// Frank Thomas Big Hurt Baseball
			else if(cart_id[63:0] == "T-8104B ") eeprom_quirk <= 4'b1011; 	// NBA Jam TE (32X)
			else if(cart_id[63:0] == "T-8102B ") eeprom_quirk <= 4'b1011; 	// NFL Quarterback Club (32X)
			else if(cart_id[63:0] == "T-113016") noram_quirk  <= 1;        // Puggsy fake ram check
			else if(cart_id[63:0] == "T-574023") pier_quirk   <= 1;        // Pier Solar Reprint
			else if(cart_id[63:0] == "T-574013") pier_quirk   <= 1;        // Pier Solar 1st Edition
			else if(cart_id[63:0] == "MK-1229 ") svp_quirk    <= 1;        // Virtua Racing EU/US
			else if(cart_id[63:0] == "G-7001  ") svp_quirk    <= 1;        // Virtua Racing JP
			else if(cart_id[63:0] == "T-35036 ") fmbusy_quirk <= 1;        // Hellfire US
			else if(cart_id[63:0] == "T-25073 ") fmbusy_quirk <= 1;        // Hellfire JP
			else if(cart_id[63:0] == "MK-1137-") fmbusy_quirk <= 1;        // Hellfire EU
			else if(cart_id[63:0] == "G-4034  ") fmbusy_quirk <= 1;        // DAISENPU/TWIN HAWK JP/EU
			else if(cart_id[63:0] == "T-68???-") schan_quirk  <= 1;        // Game no Kanzume Otokuyou
			else if(cart_id[63:0] == " GM 0000") sram00_quirk <= 1;        // Sonic 1 Remastered
			else if(cart_id[87:40] == "SF-001")  sf_quirk     <= {crc == 16'h3E08,2'b01}; // Beggar Prince (Unl), Beggar Prince rev 1 (Unl)
			else if(cart_id[87:40] == "SF-002")  sf_quirk     <= {1'b1,2'b10}; // Legend of Wukong (Unl)
			else if(cart_id[87:40] == "SF-004")  sf_quirk     <= {1'b1,2'b11}; // Star Odyssey (Unl)

			// Lightgun device and timing offsets
			if(cart_id[63:0] == "MK-1533 ") begin						  // Body Count
				gun_type  <= 0;
				gun_sensor_delay <= 8'd100;
			end
			else if(cart_id[63:0] == "T-95096-") begin				  // Lethal Enforcers
				gun_type  <= 1;
				gun_sensor_delay <= 8'd52;
			end
			else if(cart_id[63:0] == "T-95136-") begin				  // Lethal Enforcers II
				gun_type  <= 1;
				gun_sensor_delay <= 8'd30;
			end
			else if(cart_id[63:0] == "MK-1658 ") begin				  // Menacer 6-in-1
				gun_type  <= 0;
				gun_sensor_delay <= 8'd120;
			end
			else if(cart_id[63:0] == "T-081156") begin				  // T2: The Arcade Game
				gun_type  <= 0;
				gun_sensor_delay <= 8'd126;
			end
		end

		if(cart_dl_addr == 'h7E100) realtec_id[31:16] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h7E102) realtec_id[15: 0] <= {cart_dl_data[7:0],cart_dl_data[15:8]};
		if(cart_dl_addr == 'h7E104 && realtec_id == "SEGA") realtec_quirk <= 1; // Earth Defend, Funny World & Balloon Boy, Whac-a-Critter
	end
end

assign ym2612_quirk = fmbusy_quirk;

endmodule
