`timescale 1ns/1ps

module tb_cell;
	reg MCLK = 0;
	reg ss_en = 0;
	reg clk = 0, rst = 0, en = 0;
	reg [1:0] d_inp = 0, s_inp = 0;
	wire [1:0] outp, outp_nr, val, nval;
	integer fails = 0;
	integer s, c, r;

	ym7101_dff #(.DATA_WIDTH(2)) dff (
		.MCLK(MCLK), .clk(clk), .inp(d_inp), .rst(rst),
		.outp(outp), .outp_nr(outp_nr),
		.ss_en(ss_en), .ss_in(1'b0), .ss_out()
	);

	ym_slatch_t #(.DATA_WIDTH(2)) sl (
		.MCLK(MCLK), .en(en), .inp(s_inp), .val(val), .nval(nval),
		.ss_en(ss_en), .ss_in(1'b0), .ss_out()
	);

	task edge_mclk;
		begin
			#1 MCLK = 1;
			#1 MCLK = 0;
			#1;
		end
	endtask

	initial begin
		d_inp = 2'b10; clk = 0; edge_mclk;
		clk = 1; edge_mclk;
		d_inp = 2'b01; clk = 0; edge_mclk;
		s_inp = 2'b01; en = 1; edge_mclk;
		en = 0; s_inp = 2'b10; #1;

		if (dff.l1 !== 2'b01 || dff.l2 !== 2'b10 || sl.mem !== 2'b01) begin
			$display("FAIL setup: l1=%b l2=%b mem=%b", dff.l1, dff.l2, sl.mem);
			fails = fails + 1;
		end

		// no MCLK edge from here on: only the combinational outputs are checked
		for (s = 0; s < 2; s = s + 1)
			for (c = 0; c < 2; c = c + 1)
				for (r = 0; r < 2; r = r + 1) begin
					ss_en = s; clk = c; en = c; rst = r; #1;
					if (outp !== (r ? 2'b00 : (c ? dff.l1 : dff.l2)) || outp_nr !== (c ? dff.l1 : dff.l2)) begin
						$display("FAIL CELL ym7101_dff ss_en=%0d clk=%0d rst=%0d: outp=%b outp_nr=%b, l1=%b l2=%b",
							s, c, r, outp, outp_nr, dff.l1, dff.l2);
						fails = fails + 1;
					end
					if (val !== (c ? s_inp : sl.mem) || nval !== ~(c ? s_inp : sl.mem)) begin
						$display("FAIL CELL ym_slatch_t ss_en=%0d en=%0d: val=%b nval=%b, inp=%b mem=%b",
							s, c, val, nval, s_inp, sl.mem);
						fails = fails + 1;
					end
				end

		if (fails == 0)
			$display("RESULT: PASS - cell outputs ignore ss_en");
		else
			$display("RESULT: FAIL - %0d cell checks", fails);
		$finish;
	end
endmodule
