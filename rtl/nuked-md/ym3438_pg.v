module ym3438_pg
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input MCLK,
	input c1,
	input c2,
	input [11:0] fnum,
	input [2:0] block,
	input dt_sign_1,
	input dt_sign_2,
	input [4:0] dt_value,
	input [3:0] multi,
	input pg_reset,
	input [7:0] reg_21,
	input fsm_sel2,
	output [9:0] pg_out,
	output pg_dbg_o
	);
	
	wire [2:0] block_sr_o;
	
	wire ss_step1_block_sr;
	ym_sr_bit_array #(.DATA_WIDTH(3)) block_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(block),
		.data_out(block_sr_o)
		, .ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_step1_block_sr));
	
	wire [2:0] block_l_o;
	
	wire ss_step2_block_l;
	ym_dlatch_1 #(.DATA_WIDTH(3)) block_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(block_sr_o),
		.val(block_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step1_block_sr), .ss_out(ss_step2_block_l));
	
	wire block_sh0 = block_l_o[1:0] == 2'h0;
	wire block_sh1 = block_l_o[1:0] == 2'h1;
	wire block_sh2 = block_l_o[1:0] == 2'h2;
	wire block_sh3 = block_l_o[1:0] == 2'h3;
	
	wire [12:0] freq1 = { fnum, 1'h0 };
	
	wire [15:0] freq2 = ({16{block_sh0}} & { 3'h0, freq1 })
		| ({16{block_sh1}} & { 2'h0, freq1, 1'h0 })
		| ({16{block_sh2}} & { 1'h0, freq1, 2'h0 })
		| ({16{block_sh3}} & { freq1, 3'h0 });
	
	wire [16:0] freq3 = ~(
		({17{~block_l_o[2]}} & { 4'h0, freq2[15:3] })
		| ({17{block_l_o[2]}} & { freq2, 1'h0 })
		);
	
	wire [16:0] freq_l_o;
	
	wire ss_step3_freq_l;
	ym_dlatch_2 #(.DATA_WIDTH(17)) freq_l
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(freq3),
		.val(),
		.nval(freq_l_o)
		, .ss_en(ss_en), .ss_in(ss_step2_block_l), .ss_out(ss_step3_freq_l));
	
	wire [4:0] dt_value_sr_o;
	
	wire ss_step4_dt_value_sr;
	ym_sr_bit_array #(.DATA_WIDTH(5)) dt_value_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(dt_value ^ {5{dt_sign_1}}),
		.data_out(dt_value_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step3_freq_l), .ss_out(ss_step4_dt_value_sr));
	
	wire [16:0] dt_add = { {12{dt_sign_2}}, dt_value_sr_o };
	
	wire [16:0] freq_dt = freq_l_o + dt_add + dt_sign_2;
	
	wire [16:0] freq_l2_o;
	
	wire ss_step5_freq_l2;
	ym_dlatch_1 #(.DATA_WIDTH(17)) freq_l2
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(freq_dt),
		.val(freq_l2_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step4_dt_value_sr), .ss_out(ss_step5_freq_l2));
	
	wire [15:0] multi_sel;
	
	genvar i;
	
	generate
		for (i = 0; i < 16; i = i + 1)
		begin : l1
			assign multi_sel[i] = multi == i;
		end
	endgenerate
	
	wire multi_sel_1_l_o;
	
	wire ss_step6_multi_sel_1_l;
	ym_dlatch_1 multi_sel_1_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[14] | multi_sel[15]),
		.val(multi_sel_1_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step5_freq_l2), .ss_out(ss_step6_multi_sel_1_l));
	
	wire multi_sel_2_l_o;
	
	wire ss_step7_multi_sel_2_l;
	ym_dlatch_1 multi_sel_2_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[8] | multi_sel[9] | multi_sel[10] | multi_sel[11] | multi_sel[12] | multi_sel[13]),
		.val(multi_sel_2_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step6_multi_sel_1_l), .ss_out(ss_step7_multi_sel_2_l));
	
	wire multi_sel_3_l_o;
	
	wire ss_step8_multi_sel_3_l;
	ym_dlatch_1 multi_sel_3_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[4] | multi_sel[5] | multi_sel[6] | multi_sel[7]),
		.val(multi_sel_3_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step7_multi_sel_2_l), .ss_out(ss_step8_multi_sel_3_l));
	
	wire multi_sel_4_l_o;
	
	wire ss_step9_multi_sel_4_l;
	ym_dlatch_1 multi_sel_4_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[1] | multi_sel[3] | multi_sel[5] | multi_sel[7] | multi_sel[9] | multi_sel[11] | multi_sel[13]),
		.val(multi_sel_4_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step8_multi_sel_3_l), .ss_out(ss_step9_multi_sel_4_l));
	
	wire multi_sel_5_l_o;
	
	wire ss_step10_multi_sel_5_l;
	ym_dlatch_1 multi_sel_5_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[12] | multi_sel[13]),
		.val(multi_sel_5_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step9_multi_sel_4_l), .ss_out(ss_step10_multi_sel_5_l));
	
	wire multi_sel_6_l_o;
	
	wire ss_step11_multi_sel_6_l;
	ym_dlatch_1 multi_sel_6_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[14]),
		.val(multi_sel_6_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step10_multi_sel_5_l), .ss_out(ss_step11_multi_sel_6_l));
	
	wire multi_sel_7_l_o;
	
	wire ss_step12_multi_sel_7_l;
	ym_dlatch_1 multi_sel_7_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[2] | multi_sel[3] | multi_sel[6] | multi_sel[7] | multi_sel[10] | multi_sel[11]),
		.val(multi_sel_7_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step11_multi_sel_6_l), .ss_out(ss_step12_multi_sel_7_l));
	
	wire multi_sel_8_l_o;
	
	wire ss_step13_multi_sel_8_l;
	ym_dlatch_1 multi_sel_8_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[15]),
		.val(multi_sel_8_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step12_multi_sel_7_l), .ss_out(ss_step13_multi_sel_8_l));
	
	wire multi_sel_9_l_o;
	
	wire ss_step14_multi_sel_9_l;
	ym_dlatch_1 multi_sel_9_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(multi_sel[0]),
		.val(multi_sel_9_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step13_multi_sel_8_l), .ss_out(ss_step14_multi_sel_9_l));
	
	wire [19:0] freq_multi_add1 = ~(
		({20{multi_sel_5_l_o}} & { 1'h0, freq_l2_o, 2'h0 })
		| ({20{multi_sel_6_l_o}} & { 2'h3, ~freq_l2_o, 1'h1 })
		| ({20{multi_sel_7_l_o}} & { 2'h0, freq_l2_o, 1'h0 })
		| ({20{multi_sel_8_l_o}} & { 3'h7, ~freq_l2_o })
		| ({20{multi_sel_9_l_o}} & { 4'h0, freq_l2_o[16:1] })
		);
	
	wire [17:0] freq_multi_add2 = ~(
		({18{multi_sel_3_l_o}} & { 1'h0, freq_l2_o })
		| ({18{multi_sel_2_l_o}} & { freq_l2_o, 1'h0 })
		| ({18{multi_sel_1_l_o}} & { freq_l2_o[15:0], 2'h0 })
		);
	
	wire [19:0] freq_multi_add1_l_o;
	
	wire ss_step15_freq_multi_add1_l;
	ym_dlatch_2 #(.DATA_WIDTH(20)) freq_multi_add1_l
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(freq_multi_add1),
		.val(),
		.nval(freq_multi_add1_l_o)
		, .ss_en(ss_en), .ss_in(ss_step14_multi_sel_9_l), .ss_out(ss_step15_freq_multi_add1_l));
	
	wire [17:0] freq_multi_add2_l_o;
	
	wire ss_step16_freq_multi_add2_l;
	ym_dlatch_2 #(.DATA_WIDTH(18)) freq_multi_add2_l
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(freq_multi_add2),
		.val(),
		.nval(freq_multi_add2_l_o)
		, .ss_en(ss_en), .ss_in(ss_step15_freq_multi_add1_l), .ss_out(ss_step16_freq_multi_add2_l));
		
	wire multi_c_in;
	
	wire ss_step17_multi_c_in_l;
	ym_dlatch_2 multi_c_in_l
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(~(multi_sel_6_l_o | multi_sel_8_l_o)),
		.val(),
		.nval(multi_c_in)
		, .ss_en(ss_en), .ss_in(ss_step16_freq_multi_add2_l), .ss_out(ss_step17_multi_c_in_l));
	
	wire [19:0] freq_multi_sum = freq_multi_add1_l_o + { freq_multi_add2_l_o, 2'h0 } + multi_c_in;
	wire [19:0] freq_multi_sum_sr_o;
	
	wire ss_step18_freq_multi_sum_sr;
	ym_sr_bit_array #(.DATA_WIDTH(20)) freq_multi_sum_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(freq_multi_sum),
		.data_out(freq_multi_sum_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step17_multi_c_in_l), .ss_out(ss_step18_freq_multi_sum_sr));
	
	wire [16:0] freq_multi_add3_l_o;
	
	wire ss_step19_freq_multi_add3_l;
	ym_dlatch_2 #(.DATA_WIDTH(17)) freq_multi_add3_l
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(freq_l2_o),
		.val(freq_multi_add3_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step18_freq_multi_sum_sr), .ss_out(ss_step19_freq_multi_add3_l));
	
	wire [19:0] freq_multi_add3_sr_o;
	
	wire ss_step20_freq_multi_add3_sr;
	ym_sr_bit_array #(.DATA_WIDTH(20)) freq_multi_add3_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in({3'h0, freq_multi_add3_l_o}),
		.data_out(freq_multi_add3_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step19_freq_multi_add3_l), .ss_out(ss_step20_freq_multi_add3_sr));
	
	wire multi_sel_4_l2_o;
	
	wire ss_step21_multi_sel_4_l2;
	ym_dlatch_2 multi_sel_4_l2
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(multi_sel_4_l_o),
		.val(multi_sel_4_l2_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step20_freq_multi_add3_sr), .ss_out(ss_step21_multi_sel_4_l2));
	
	wire multi_sel_4_sr_o;
	
	wire ss_step22_multi_sel_4_sr;
	ym_sr_bit multi_sel_4_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(multi_sel_4_l2_o),
		.sr_out(multi_sel_4_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step21_multi_sel_4_l2), .ss_out(ss_step22_multi_sel_4_sr));
	
	wire multi_sel_4_sr_o_r = multi_sel_4_sr_o & pg_reset;
	
	wire [19:0] freq_multi_add3_l2_o;
	
	wire ss_step23_freq_multi_add3_l2;
	ym_dlatch_1 #(.DATA_WIDTH(20)) freq_multi_add3_l2
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(~(multi_sel_4_sr_o_r ? freq_multi_add3_sr_o : 20'h00000)),
		.val(),
		.nval(freq_multi_add3_l2_o)
		, .ss_en(ss_en), .ss_in(ss_step22_multi_sel_4_sr), .ss_out(ss_step23_freq_multi_add3_l2));
	
	wire [19:0] freq_multi_sum_l_o;
	
	wire ss_step24_freq_multi_sum_l;
	ym_dlatch_1 #(.DATA_WIDTH(20)) freq_multi_sum_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(~(pg_reset ? freq_multi_sum_sr_o : 20'h00000)),
		.val(),
		.nval(freq_multi_sum_l_o)
		, .ss_en(ss_en), .ss_in(ss_step23_freq_multi_add3_l2), .ss_out(ss_step24_freq_multi_sum_l));
	
	wire [19:0] freq_inc = freq_multi_sum_l_o + freq_multi_add3_l2_o;
	wire [19:0] freq_inc_l_o;
	
	wire ss_step25_freq_inc_l;
	ym_dlatch_2 #(.DATA_WIDTH(20)) freq_inc_l
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(freq_inc),
		.val(freq_inc_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step24_freq_multi_sum_l), .ss_out(ss_step25_freq_inc_l));
	
	wire pg_reset_sr_o;
	
	wire ss_step26_pg_reset_sr;
	ym_sr_bit pg_reset_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(pg_reset),
		.sr_out(pg_reset_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step25_freq_inc_l), .ss_out(ss_step26_pg_reset_sr));
	
	wire pg_reset2 = pg_reset_sr_o & ~reg_21[3];
	
	wire [19:0] o_phase;
	
	wire [19:0] phase = (pg_reset2 ? o_phase : 20'h00000) + freq_inc_l_o;
	
	wire [19:0] pg_values_o;
	
	wire ss_step27_pg_values;
	ym_sr_bit_array #(.DATA_WIDTH(20), .SR_LENGTH(20)) pg_values
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(phase),
		.data_out(pg_values_o)
		, .ss_en(ss_en), .ss_in(ss_step26_pg_reset_sr), .ss_out(ss_step27_pg_values));
	
	wire ss_step28_pg_values2;
	ym_sr_bit_array #(.DATA_WIDTH(20), .SR_LENGTH(4)) pg_values2
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(pg_values_o),
		.data_out(o_phase)
		, .ss_en(ss_en), .ss_in(ss_step27_pg_values), .ss_out(ss_step28_pg_values2));
	
	assign pg_out = pg_values_o[19:10];
	
	wire ss_step29_dbg_read;
	ym_dbg_read #(.DATA_WIDTH(10)) dbg_read
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.prev(0),
		.load(fsm_sel2),
		.load_val(o_phase[9:0]),
		.next(pg_dbg_o)
		, .ss_en(ss_en), .ss_in(ss_step28_pg_values2), .ss_out(ss_step29_dbg_read));


	assign ss_out = ss_step29_dbg_read;
endmodule
