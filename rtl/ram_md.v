
module vram_ip
(
	input	  [7:0] address,
	input	 [31:0] byteena,
	input	        clock,
	input	[255:0] data,
	input	        wren,
	output[255:0] q
);

spram #(8,256) ram
(
	.clock(clock),
	.address(address),
	.data(data),
	.wren(wren),
	.byteena(byteena),
	.q(q)
);

endmodule

module vram_ip2
(
	input	  [7:0] address_a,
	input	 [31:0] byteena_a,
	input	[255:0] data_a,
	input	        wren_a,
	output[255:0] q_a,
	input	  [7:0] address_b,
	input	 [31:0] byteena_b,
	input	[255:0] data_b,
	input	        wren_b,
	output[255:0] q_b,
	input	        clock
);

dpram #(8,256) ram
(
	.clock(clock),
	.address_a(address_a),
	.data_a(data_a),
	.wren_a(wren_a),
	.byteena_a(byteena_a),
	.q_a(q_a),
	.address_b(address_b),
	.data_b(data_b),
	.wren_b(wren_b),
	.byteena_b(byteena_b),
	.q_b(q_b)
);

endmodule
