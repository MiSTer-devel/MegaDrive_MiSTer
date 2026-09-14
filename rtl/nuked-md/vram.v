module vram
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input ss_mem_sel,
	input [15:0] ss_mem_addr,
	input [7:0] ss_mem_din,
	input ss_mem_wr,
	output [7:0] ss_mem_dout,

	input MCLK,
	input RAS,
	input CAS,
	input WE,
	input OE,
	input SC,
	input SE,
	input [7:0] AD,
	input [7:0] RD_i,
	output reg [7:0] RD_o,
	output RD_d,
	output [7:0] SD_o,
	output SD_d
	);
	
	reg [15:0] addr = 0;
	reg dt = 0;
	reg [7:0] addr_ser = 0;
	// not in the scan chain: parallel loaded from VRAM, and the VDP reloads it on
	// every read transfer, so a restore is stale for at most one access slot
	reg [2047:0] ser = 0;
	
	reg o_OE = 0;
	reg o_RAS = 0;
	reg o_cas = 0;
	reg o_SC = 0;
	reg o_valid = 0;
	
	wire cas = ~RAS & ~CAS;
	wire wr = ~RAS & ~CAS & ~WE & ~ss_en;
	wire rd = ~RAS & ~CAS & ~OE & ~dt;
	
	wire [15:0] eaddr = ss_mem_sel ? ss_mem_addr : addr;
	wire [7:0] mem_addr = eaddr[15:8];
	wire [31:0] mem_be;
	wire [2047:0] mem_o;
	
	wire [7:0] slice_s[0:255];
	wire [7:0] slice_p[0:255];
	
	genvar i;
	generate
		for (i = 0; i < 32; i = i + 1)
		begin : l1
			assign mem_be[i] = eaddr[4:0] == i;
		end
		for (i = 0; i < 8; i = i + 1)
		begin : l2
			vram_ip mem
				(
				.clock(MCLK),
				.address(mem_addr),
				.byteena(mem_be),
				.data(ss_mem_sel ? {32{ss_mem_din}} : {32{RD_i}}),
				.wren(ss_mem_sel ? (ss_mem_wr & (eaddr[7:5] == i)) : (wr & (addr[7:5] == i))),
				.q(mem_o[(256*(i+1)-1):(256*i)])
				);
		end
		for (i = 0; i < 256; i = i + 1)
		begin : l3
			assign slice_p[i] = mem_o[(8*(i+1)-1):(8*i)];
			assign slice_s[i] = ser[(8*(i+1)-1):(8*i)]; 
		end
	endgenerate
	
	assign RD_d = ~o_valid;
	assign SD_d = SE;
	
	reg [7:0] vram_ser = 0;
	
	assign SD_o = vram_ser;
	
	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			addr_ser <= {addr_ser[6:0], ss_in};
			vram_ser <= {vram_ser[6:0], addr_ser[7]};
			dt <= vram_ser[7];
			addr <= {addr[14:0], dt};
			RD_o <= {RD_o[6:0], addr[15]};
			o_valid <= RD_o[7];
			o_OE <= o_valid;
			o_RAS <= o_OE;
			o_cas <= o_RAS;
			o_SC <= o_cas;
		end
		else
		begin

		if (dt & !o_OE & OE)
		begin
			addr_ser <= addr[7:0];
			ser <= mem_o;
		end
		else if (~o_SC & SC)
		begin
			addr_ser <= addr_ser + 8'h1;
			vram_ser <= slice_s[addr_ser];
		end
		if (o_RAS & ~RAS)
		begin
			dt <= ~OE;
			addr[15:8] <= AD;
		end
		if (~o_cas & cas)
		begin
			addr[7:0] <= AD;
		end
		if (dt & !o_OE & OE)
		begin
			addr_ser <= addr[7:0];
			ser <= mem_o;
		end
		
		if (rd)
		begin
			RD_o <= slice_p[addr[7:0]];
			o_valid <= 1'h1;
		end
		else if (CAS | OE)
		begin
			o_valid <= 1'h0;
		end
		
		o_OE <= OE;
		o_RAS <= RAS;
		o_cas <= cas;
		o_SC <= SC;
			end
end


	assign ss_mem_dout = slice_p[eaddr[7:0]];

	assign ss_out = o_SC;
endmodule
