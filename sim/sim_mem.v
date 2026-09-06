// simulation-only behavioral models of the MiSTer sys memory primitives
`timescale 1ns/1ps

module spram #(parameter ADDRWIDTH=8, DATAWIDTH=8, MIF="")
(
	input                   clock,
	input  [ADDRWIDTH-1:0]  address,
	input  [DATAWIDTH-1:0]  data,
	input                   wren,
	input  [DATAWIDTH/8-1:0] byteena,
	output reg [DATAWIDTH-1:0] q
);
	reg [DATAWIDTH-1:0] mem [0:(1<<ADDRWIDTH)-1];
	integer i;
	initial for (i = 0; i < (1<<ADDRWIDTH); i = i + 1) mem[i] = 0;

	always @(posedge clock) begin
		if (wren) begin
			for (i = 0; i < DATAWIDTH/8; i = i + 1)
				if (byteena[i]) mem[address][i*8 +: 8] <= data[i*8 +: 8];
		end
		q <= mem[address];
	end
endmodule

module dpram #(parameter ADDRWIDTH=8, DATAWIDTH=8)
(
	input                    clock,
	input  [ADDRWIDTH-1:0]   address_a,
	input  [DATAWIDTH-1:0]   data_a,
	input                    wren_a,
	input  [DATAWIDTH/8-1:0] byteena_a,
	output reg [DATAWIDTH-1:0] q_a,
	input  [ADDRWIDTH-1:0]   address_b,
	input  [DATAWIDTH-1:0]   data_b,
	input                    wren_b,
	input  [DATAWIDTH/8-1:0] byteena_b,
	output reg [DATAWIDTH-1:0] q_b
);
	reg [DATAWIDTH-1:0] mem [0:(1<<ADDRWIDTH)-1];
	integer i;
	initial for (i = 0; i < (1<<ADDRWIDTH); i = i + 1) mem[i] = 0;

	always @(posedge clock) begin
		if (wren_a)
			for (i = 0; i < DATAWIDTH/8; i = i + 1)
				if (byteena_a[i]) mem[address_a][i*8 +: 8] <= data_a[i*8 +: 8];
		q_a <= mem[address_a];
	end

	always @(posedge clock) begin
		if (wren_b)
			for (i = 0; i < DATAWIDTH/8; i = i + 1)
				if (byteena_b[i]) mem[address_b][i*8 +: 8] <= data_b[i*8 +: 8];
		q_b <= mem[address_b];
	end
endmodule
