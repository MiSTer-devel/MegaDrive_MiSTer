// ym3438, ym7101, fc1004 common cells
// scan chain added: ss_en/ss_in/ss_out on every cell, ss_en==0 keeps original behavior

module ym_sr_bit #(parameter SR_LENGTH = 1)
	(
	input MCLK,
	input c1,
	input c2,
	input bit_in,
	output sr_out,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [SR_LENGTH-1:0] v1 = 0;
	reg [SR_LENGTH-1:0] v2 = 0;

	assign sr_out = v2[SR_LENGTH-1];
	assign ss_out = v2[SR_LENGTH-1];

	// scan rides this cell's own network, one 2:1 mux per cell (a mux per stage
	// cost 2.3 ALMs/bit vs 0.42 overall). interleaves v1/v2 instead of walking one
	// bank then the other, so older snapshots see a different length and are refused.
	wire in_bit = ss_en ? ss_in : bit_in;

	always @(posedge MCLK)
	begin
		if (c1 | ss_en)
		begin
			if (SR_LENGTH == 1)
				v1 <= in_bit;
			else
				v1 <= { v2[SR_LENGTH-2:0], in_bit };
		end
		if (c2 | ss_en)
			v2 <= v1;
	end
endmodule

module ym_sr_bit_array #(parameter SR_LENGTH = 1, DATA_WIDTH = 1)
	(
	input MCLK,
	input c1,
	input c2,
	input [DATA_WIDTH-1:0] data_in,
	output [DATA_WIDTH-1:0] data_out,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire out[0:DATA_WIDTH-1];
	wire ss_link[0:DATA_WIDTH];
	assign ss_link[0] = ss_in;
	assign ss_out = ss_link[DATA_WIDTH];

	generate
		genvar i;
		for (i = 0; i < DATA_WIDTH; i = i + 1)
		begin : l1
			ym_sr_bit #(.SR_LENGTH(SR_LENGTH)) sr (
			.MCLK(MCLK),
			.c1(c1),
			.c2(c2),
			.bit_in(data_in[i]),
			.sr_out(out[i]),
			.ss_en(ss_en),
			.ss_in(ss_link[i]),
			.ss_out(ss_link[i+1])
			);

			assign data_out[i] = out[i];
		end
	endgenerate

endmodule

module ym_cnt_bit #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input c1,
	input c2,
	input c_in,
	input reset,
	output [DATA_WIDTH-1:0] val,
	output c_out,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire [DATA_WIDTH-1:0] data_in;
	wire [DATA_WIDTH-1:0] data_out;
	wire [DATA_WIDTH:0] sum;

	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) mem
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(data_in),
		.data_out(data_out),
		.ss_en(ss_en),
		.ss_in(ss_in),
		.ss_out(ss_out)
		);

	assign sum = { 1'h0, data_out } + {{DATA_WIDTH{1'h0}}, c_in};
	assign val = data_out;
	assign data_in = reset ? {DATA_WIDTH{1'h0}} : sum[DATA_WIDTH-1:0];
	assign c_out = sum[DATA_WIDTH];

endmodule

module ym_dlatch_1 #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input c1,
	input [DATA_WIDTH-1:0] inp,
	output [DATA_WIDTH-1:0] val,
	output [DATA_WIDTH-1:0] nval,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] mem = {DATA_WIDTH{1'h0}};

	wire [DATA_WIDTH-1:0] mem_assign = c1 ? inp : mem;

	assign ss_out = mem[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
				mem <= ss_in;
			else
				mem <= { mem[DATA_WIDTH-2:0], ss_in };
		end
		else
		begin
			mem <= mem_assign;
		end
	end

	assign val = mem;
	assign nval = ~mem;

endmodule

module ym_dlatch_2 #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input c2,
	input [DATA_WIDTH-1:0] inp,
	output [DATA_WIDTH-1:0] val,
	output [DATA_WIDTH-1:0] nval,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] mem = {DATA_WIDTH{1'h0}};

	wire [DATA_WIDTH-1:0] mem_assign = c2 ? inp : mem;

	assign ss_out = mem[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
				mem <= ss_in;
			else
				mem <= { mem[DATA_WIDTH-2:0], ss_in };
		end
		else
		begin
			mem <= mem_assign;
		end
	end

	assign val = mem;
	assign nval = ~mem;

endmodule

module ym_edge_detect
	(
	input MCLK,
	input c1,
	input inp,
	output outp,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire prev_out;

	ym_dlatch_1 prev
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(inp),
		.val(prev_out),
		.nval(),
		.ss_en(ss_en),
		.ss_in(ss_in),
		.ss_out(ss_out)
		);
	assign outp = ~(prev_out | ~inp);
endmodule

module ym_slatch #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input en,
	input [DATA_WIDTH-1:0] inp,
	output [DATA_WIDTH-1:0] val,
	output [DATA_WIDTH-1:0] nval,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] mem = {DATA_WIDTH{1'h0}};

	wire [DATA_WIDTH-1:0] mem_assign = en ? inp : mem;

	assign ss_out = mem[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
				mem <= ss_in;
			else
				mem <= { mem[DATA_WIDTH-2:0], ss_in };
		end
		else
		begin
			mem <= mem_assign;
		end
	end

	assign val = mem;
	assign nval = ~mem;

endmodule

module ym_slatch_t #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input en,
	input [DATA_WIDTH-1:0] inp,
	output [DATA_WIDTH-1:0] val,
	output [DATA_WIDTH-1:0] nval,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] mem = {DATA_WIDTH{1'h0}};

	wire [DATA_WIDTH-1:0] mem_assign = en ? inp : mem;

	// never mem_assign: that's the transparent path, live while en is high, and
	// tapping it feeds the next cell a functional input instead of the stored bit
	assign ss_out = mem[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
				mem <= ss_in;
			else
				mem <= { mem[DATA_WIDTH-2:0], ss_in };
		end
		else
		begin
			mem <= mem_assign;
		end
	end

	// the transparent path left live would let the surrounding network oscillate
	// around the latch while frozen: a non-converging loop, and a real hazard too
	assign val = ss_en ? mem : mem_assign;
	assign nval = ~val;

endmodule

module ym_rs_trig
	(
	input MCLK,
	input set,
	input rst,
	output reg q = 1'h0,
	output reg nq = 1'h1,
	input ss_en,
	input ss_in,
	output ss_out
	);

	assign ss_out = nq;

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			q <= ss_in;
			nq <= q;
		end
		else
		begin
			q <= rst ? 1'h0 : (set ? 1'h1 : q);
			nq <= set ? 1'h0 : (rst ? 1'h1 : ~q);
		end
	end

endmodule

module ym_rs_trig_sync
	(
	input MCLK,
	input set,
	input rst,
	input c1,
	output reg q = 1'h0,
	output reg nq = 1'h1,
	input ss_en,
	input ss_in,
	output ss_out
	);

	assign ss_out = nq;

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			q <= ss_in;
			nq <= q;
		end
		else
		begin
			q <= (c1 & rst) ? 1'h0 : ((c1 & set) ? 1'h1 : q);
			nq <= (c1 & set) ? 1'h0 : ((c1 & rst) ? 1'h1 : ~q);
		end
	end

endmodule

module ym_cnt_bit_load #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input c1,
	input c2,
	input c_in,
	input reset,
	input load,
	input [DATA_WIDTH-1:0] load_val,
	output [DATA_WIDTH-1:0] val,
	output c_out,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire [DATA_WIDTH-1:0] data_in;
	wire [DATA_WIDTH-1:0] data_out;
	wire [DATA_WIDTH:0] sum;

	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) mem
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(data_in),
		.data_out(data_out),
		.ss_en(ss_en),
		.ss_in(ss_in),
		.ss_out(ss_out)
		);

	wire [DATA_WIDTH-1:0] base_val = load ? load_val : data_out;

	assign sum = {1'h0, base_val} + {{DATA_WIDTH{1'h0}},c_in};
	assign data_in = reset ? {DATA_WIDTH{1'h0}} : sum[DATA_WIDTH-1:0];
	assign val = data_out;
	assign c_out = sum[DATA_WIDTH];

endmodule

module ym_dbg_read #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input c1,
	input c2,
	input prev,
	input load,
	input [DATA_WIDTH-1:0] load_val,
	output next,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire [DATA_WIDTH-1:0] data_in;
	wire [DATA_WIDTH-1:0] data_out;

	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) mem
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(data_in),
		.data_out(data_out),
		.ss_en(ss_en),
		.ss_in(ss_in),
		.ss_out(ss_out)
		);

	wire [DATA_WIDTH-1:0] chain;

	assign data_in = chain | (load ? load_val : {DATA_WIDTH{1'h0}});

	generate
		if (DATA_WIDTH == 1)
			assign chain = prev;
		else
			assign chain = { prev, data_out[DATA_WIDTH-1:1] };
	endgenerate

	assign next = data_out[0];

endmodule

module ym_dbg_read_eg #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input c1,
	input c2,
	input prev,
	input load,
	input [DATA_WIDTH-1:0] load_val,
	output next,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire [DATA_WIDTH-1:0] data_in;
	wire [DATA_WIDTH-1:0] data_out;

	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) mem
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(data_in),
		.data_out(data_out),
		.ss_en(ss_en),
		.ss_in(ss_in),
		.ss_out(ss_out)
		);

	wire [DATA_WIDTH-1:0] chain;

	assign data_in = chain | (load ? load_val : {DATA_WIDTH{1'h0}});

	generate
		if (DATA_WIDTH == 1)
			assign chain = prev;
		else
			assign chain = { data_out[DATA_WIDTH-2:0], prev };
	endgenerate

	assign next = data_out[DATA_WIDTH-1];

endmodule

module ym_slatch_r #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input en,
	input rst,
	input [DATA_WIDTH-1:0] inp,
	output [DATA_WIDTH-1:0] val,
	output [DATA_WIDTH-1:0] nval,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] mem = {DATA_WIDTH{1'h0}};

	wire [DATA_WIDTH-1:0] mem_assign = rst ? {DATA_WIDTH{1'h0}} : (en ? inp : mem);

	assign ss_out = mem[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
				mem <= ss_in;
			else
				mem <= { mem[DATA_WIDTH-2:0], ss_in };
		end
		else
		begin
			mem <= mem_assign;
		end
	end

	assign val = mem;
	assign nval = ~mem;

endmodule

module ym_cnt_bit_rs #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input c1,
	input c2,
	input c_in,
	input reset,
	input set,
	output [DATA_WIDTH-1:0] val,
	output [DATA_WIDTH-1:0] nval,
	output c_out,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire [DATA_WIDTH-1:0] data_in;
	wire [DATA_WIDTH-1:0] data_out;
	wire [DATA_WIDTH-1:0] data_out_s = set ? {DATA_WIDTH{1'h1}} : data_out;
	wire [DATA_WIDTH:0] sum;

	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) mem
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(data_in),
		.data_out(data_out),
		.ss_en(ss_en),
		.ss_in(ss_in),
		.ss_out(ss_out)
		);

	assign sum = {1'h0,data_out_s} + {{DATA_WIDTH{1'h0}}, c_in};
	assign val = data_out_s;
	assign nval = ~data_out_s;
	assign data_in = reset ? {DATA_WIDTH{1'h0}} : sum[DATA_WIDTH-1:0];
	assign c_out = sum[DATA_WIDTH];

endmodule

module ym_cnt_bit_rev #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input c1,
	input c2,
	input c_in,
	input dec,
	input reset,
	output [DATA_WIDTH-1:0] val,
	output c_out,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire [DATA_WIDTH-1:0] data_in;
	wire [DATA_WIDTH-1:0] data_out;
	wire [DATA_WIDTH:0] sum;

	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) mem
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(data_in),
		.data_out(data_out),
		.ss_en(ss_en),
		.ss_in(ss_in),
		.ss_out(ss_out)
		);

	assign sum = { 1'h0, data_out } + {1'h0, {DATA_WIDTH{dec}}} + {{DATA_WIDTH{1'h0}}, c_in};
	assign val = data_out;
	assign data_in = reset ? {DATA_WIDTH{1'h0}} : sum[DATA_WIDTH-1:0];
	assign c_out = sum[DATA_WIDTH];

endmodule

module ym_sr_bit_en #(parameter SR_LENGTH = 2)
	(
	input MCLK,
	input c1,
	input c2,
	input en1,
	input en2,
	input data_in,
	output [SR_LENGTH-1:0] data_out,
	input ss_en,
	input ss_in,
	output ss_out
	);

	wire [SR_LENGTH-1:0] sr_out;
	wire [SR_LENGTH-1:0] sr_in =
		(en1 ? { sr_out[SR_LENGTH-2:0], data_in } : {SR_LENGTH{1'h0}}) |
		(en2 ? sr_out : {SR_LENGTH{1'h0}});

	assign data_out = sr_out;

	ym_sr_bit_array #(.DATA_WIDTH(SR_LENGTH)) mem
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr_in),
		.data_out(sr_out),
		.ss_en(ss_en),
		.ss_in(ss_in),
		.ss_out(ss_out)
		);

endmodule


module ym_scnt_bit #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input clk,
	input load,
	input [DATA_WIDTH-1:0] val,
	input cin,
	input rst,
	output [DATA_WIDTH-1:0] q,
	output [DATA_WIDTH-1:0] nq,
	output cout,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] l1 = {DATA_WIDTH{1'h0}}, l2 = {DATA_WIDTH{1'h0}};

	wire [DATA_WIDTH:0] sum = { 1'h0, l2 } + {{DATA_WIDTH{1'h0}}, cin};

	assign cout = sum[DATA_WIDTH];

	assign q = l2;
	assign nq = ~l2;

	assign ss_out = l2[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
			begin
				l1 <= ss_in;
				l2 <= l1;
			end
			else
			begin
				l1 <= { l1[DATA_WIDTH-2:0], ss_in };
				l2 <= { l2[DATA_WIDTH-2:0], l1[DATA_WIDTH-1] };
			end
		end
		else
		begin
			if (~rst)
			begin
				l1 <= {DATA_WIDTH{1'h0}};
				l2 <= {DATA_WIDTH{1'h0}};
			end
			else
			begin
				if (~clk)
					l1 <= ~load ? val : sum[DATA_WIDTH-1:0];
				else
					l2 <= l1;
			end
		end
	end

endmodule


module ym_sdff #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input clk,
	input [DATA_WIDTH-1:0] val,
	output [DATA_WIDTH-1:0] q,
	output [DATA_WIDTH-1:0] nq,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] l1 = {DATA_WIDTH{1'h0}}, l2 = {DATA_WIDTH{1'h0}};

	assign q = l2;
	assign nq = ~l2;

	assign ss_out = l2[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
			begin
				l1 <= ss_in;
				l2 <= l1;
			end
			else
			begin
				l1 <= { l1[DATA_WIDTH-2:0], ss_in };
				l2 <= { l2[DATA_WIDTH-2:0], l1[DATA_WIDTH-1] };
			end
		end
		else
		begin
			if (~clk)
				l1 <= val;
			else
				l2 <= l1;
		end
	end

endmodule


module ym_sdffs #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input clk,
	input [DATA_WIDTH-1:0] val,
	input set,
	output [DATA_WIDTH-1:0] q,
	output [DATA_WIDTH-1:0] nq,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] l1 = 0, l2 = 0;

	assign q = l2;
	assign nq = ~l2;

	assign ss_out = l2[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
			begin
				l1 <= ss_in;
				l2 <= l1;
			end
			else
			begin
				l1 <= { l1[DATA_WIDTH-2:0], ss_in };
				l2 <= { l2[DATA_WIDTH-2:0], l1[DATA_WIDTH-1] };
			end
		end
		else
		begin
			if (~clk)
				l1 <= val;
			else if (~set)
				l1 <= {DATA_WIDTH{1'h1}};
			if (~set)
				l2 <= {DATA_WIDTH{1'h1}};
			else if (clk)
				l2 <= l1;
		end
	end

endmodule


module ym_sdffr #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input clk,
	input [DATA_WIDTH-1:0] val,
	input reset,
	output [DATA_WIDTH-1:0] q,
	output [DATA_WIDTH-1:0] nq,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] l1 = {DATA_WIDTH{1'h0}}, l2 = {DATA_WIDTH{1'h0}};

	assign q = l2;
	assign nq = ~l2;

	assign ss_out = l2[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
			begin
				l1 <= ss_in;
				l2 <= l1;
			end
			else
			begin
				l1 <= { l1[DATA_WIDTH-2:0], ss_in };
				l2 <= { l2[DATA_WIDTH-2:0], l1[DATA_WIDTH-1] };
			end
		end
		else
		begin
			if (~reset)
				l1 <= {DATA_WIDTH{1'h0}};
			else if (~clk)
				l1 <= val;
			if (~reset)
				l2 <= {DATA_WIDTH{1'h0}};
			else if (clk)
				l2 <= l1;
		end
	end

endmodule


module ym_sdffsr #(parameter DATA_WIDTH = 1)
	(
	input MCLK,
	input clk,
	input [DATA_WIDTH-1:0] val,
	input set,
	input reset,
	output [DATA_WIDTH-1:0] q,
	output [DATA_WIDTH-1:0] nq,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DATA_WIDTH-1:0] l1 = {DATA_WIDTH{1'h0}}, l2 = {DATA_WIDTH{1'h0}};

	assign q = (~set & ~reset) ? {DATA_WIDTH{1'h0}} : l2;
	assign nq = (~set & ~reset) ? {DATA_WIDTH{1'h0}} : ~l2;

	assign ss_out = l2[DATA_WIDTH-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DATA_WIDTH == 1)
			begin
				l1 <= ss_in;
				l2 <= l1;
			end
			else
			begin
				l1 <= { l1[DATA_WIDTH-2:0], ss_in };
				l2 <= { l2[DATA_WIDTH-2:0], l1[DATA_WIDTH-1] };
			end
		end
		else
		begin
			if (~reset)
				l1 <= {DATA_WIDTH{1'h0}};
			else if (~set)
				l1 <= {DATA_WIDTH{1'h1}};
			else if (~clk)
				l1 <= val;
			if (~set)
				l2 <= {DATA_WIDTH{1'h1}};
			else if (~reset)
				l2 <= {DATA_WIDTH{1'h0}};
			else if (clk)
				l2 <= l1;
		end
	end

endmodule


module ym_delaychain #(parameter DELAY_CNT = 1)
	(
	input MCLK,
	input inp,
	output outp,
	input ss_en,
	input ss_in,
	output ss_out
	);

	reg [DELAY_CNT-1:0] dl = {DELAY_CNT{1'h0}};

	assign ss_out = dl[DELAY_CNT-1];

	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			if (DELAY_CNT == 1)
				dl <= ss_in;
			else
				dl <= { dl[DELAY_CNT-2:0], ss_in };
		end
		else
		begin
			if (DELAY_CNT == 1)
				dl <= inp;
			else
				dl <= { dl[DELAY_CNT-2:0], inp };
		end
	end

	assign outp = dl[DELAY_CNT-1];

endmodule
