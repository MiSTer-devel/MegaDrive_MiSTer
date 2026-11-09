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
	
	wire [7:0] mem_addr = addr[15:8];
	wire [31:0] mem_be;
	wire [2047:0] mem_o;
	wire [31:0] ss_be;
	wire [2047:0] ss_mem_o;
	
	wire [7:0] slice_s[0:255];
	wire [7:0] slice_p[0:255];
	wire [7:0] ss_slice[0:255];
	
	genvar i;
	generate
		for (i = 0; i < 32; i = i + 1)
		begin : l1
			assign mem_be[i] = addr[4:0] == i;
			assign ss_be[i] = ss_mem_addr[4:0] == i;
		end
		for (i = 0; i < 8; i = i + 1)
		begin : l2
			// port A is the VDP's, port B the walk's; the VDP's writes stay dropped
			// while the walk owns the RAM (R33), its reads are its own now
			vram_ip2 mem
				(
				.clock(MCLK),
				.address_a(mem_addr),
				.byteena_a(mem_be),
				.data_a({32{RD_i}}),
				.wren_a(wr & ~ss_mem_sel & (addr[7:5] == i)),
				.q_a(mem_o[(256*(i+1)-1):(256*i)]),
				.address_b(ss_mem_addr[15:8]),
				.byteena_b(ss_be),
				.data_b({32{ss_mem_din}}),
				.wren_b(ss_mem_sel & ss_mem_wr & (ss_mem_addr[7:5] == i)),
				.q_b(ss_mem_o[(256*(i+1)-1):(256*i)])
				);
		end
		for (i = 0; i < 256; i = i + 1)
		begin : l3
			assign slice_p[i] = mem_o[(8*(i+1)-1):(8*i)];
			assign ss_slice[i] = ss_mem_o[(8*(i+1)-1):(8*i)];
			assign slice_s[i] = ser[(8*(i+1)-1):(8*i)]; 
		end
	endgenerate
	
	assign RD_d = ~o_valid;
	assign SD_d = SE;
	
	reg [7:0] vram_ser = 0;
	reg [7:0] ss_ra = 0;
	reg [63:0] ss_q_col = 0;
	reg [2:0] ss_q_hi = 0;
	reg [7:0] ss_q = 0;
	wire [7:0] ss_col [0:7];
	generate
		for (i = 0; i < 8; i = i + 1)
		begin : l4
			assign ss_col[i] = ss_slice[32*i + ss_ra[4:0]];
		end
	endgenerate
	
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


	always @(posedge MCLK) if (ss_mem_sel) ss_ra <= ss_mem_addr[7:0];
	// the walk reads the eight column bytes first and picks the RAM a clock
	// later, so its single-cycle path ends at one RAM's 32:1
	always @(posedge MCLK) if (ss_mem_sel)
	begin
		ss_q_col[7:0]   <= ss_col[0];
		ss_q_col[15:8]  <= ss_col[1];
		ss_q_col[23:16] <= ss_col[2];
		ss_q_col[31:24] <= ss_col[3];
		ss_q_col[39:32] <= ss_col[4];
		ss_q_col[47:40] <= ss_col[5];
		ss_q_col[55:48] <= ss_col[6];
		ss_q_col[63:56] <= ss_col[7];
		ss_q_hi <= ss_ra[7:5];
		ss_q <= ss_q_col[8*ss_q_hi +: 8];
	end
	assign ss_mem_dout = ss_q;

	assign ss_out = o_SC;
endmodule
