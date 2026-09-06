module ym3438_lfo
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input MCLK,
	input c1,
	input c2,
	input [3:0] lfo,
	input fsm_sel23,
	input [7:0] reg_21,
	input IC,
	input [2:0] pms,
	input [10:0] fnum,
	output [5:0] lfo_am,
	output [11:0] fnum_lfo
	);
	
	wire [6:0] lfo_subcnt_sr_in;
	wire [6:0] lfo_subcnt_sr_out;
	
	wire ss_step1_lfo_subcnt_sr;
	ym_sr_bit_array #(.DATA_WIDTH(7)) lfo_subcnt_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(lfo_subcnt_sr_in),
		.data_out(lfo_subcnt_sr_out)
		, .ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_step1_lfo_subcnt_sr));
	
	wire lfo_subcnt_inc = reg_21[1] | fsm_sel23;
	
	wire lfo_subcnt_of;
	
	wire lfo_subcnt_res = ~(lfo_subcnt_of | ~IC);
	
	wire [6:0] lfo_subcnt_sum = lfo_subcnt_sr_out + lfo_subcnt_inc;
	
	assign lfo_subcnt_sr_in = lfo_subcnt_res ? lfo_subcnt_sum : 7'h00;
	
	wire [7:0] lfo_sel;
	
	genvar i;
		
	generate
		for (i = 0; i < 8; i=i+1)
		begin : l1
			assign lfo_sel[i] = lfo[2:0] == i;
		end
	endgenerate
	
	wire [7:0] lfo_of_check;
	
	assign lfo_of_check[0] = lfo_sel[0] & lfo_subcnt_sr_out[6] & lfo_subcnt_sr_out[5]
		& lfo_subcnt_sr_out[3] & lfo_subcnt_sr_out[2];
	assign lfo_of_check[1] = lfo_sel[1] & lfo_subcnt_sr_out[6] & lfo_subcnt_sr_out[3]
		& lfo_subcnt_sr_out[2] & lfo_subcnt_sr_out[0];
	assign lfo_of_check[2] = lfo_sel[2] & lfo_subcnt_sr_out[6] & lfo_subcnt_sr_out[2]
		& lfo_subcnt_sr_out[1] & lfo_subcnt_sr_out[0];
	assign lfo_of_check[3] = lfo_sel[3] & lfo_subcnt_sr_out[6] & lfo_subcnt_sr_out[1] & lfo_subcnt_sr_out[0];
	assign lfo_of_check[4] = lfo_sel[4] & lfo_subcnt_sr_out[5] & lfo_subcnt_sr_out[4]
		& lfo_subcnt_sr_out[3] & lfo_subcnt_sr_out[2] & lfo_subcnt_sr_out[1];
	assign lfo_of_check[5] = lfo_sel[5] & lfo_subcnt_sr_out[5] & lfo_subcnt_sr_out[3] & lfo_subcnt_sr_out[2];
	assign lfo_of_check[6] = lfo_sel[6] & lfo_subcnt_sr_out[3];
	assign lfo_of_check[7] = lfo_sel[7] & lfo_subcnt_sr_out[2] & lfo_subcnt_sr_out[0];
	
	assign lfo_subcnt_of = lfo_of_check != 8'h00;
	
	wire [6:0] lfo_cnt_sr_in;
	wire [6:0] lfo_cnt_sr_out;
	
	wire ss_step2_lfo_cnt_sr;
	ym_sr_bit_array #(.DATA_WIDTH(7)) lfo_cnt_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(lfo_cnt_sr_in),
		.data_out(lfo_cnt_sr_out)
		, .ss_en(ss_en), .ss_in(ss_step1_lfo_subcnt_sr), .ss_out(ss_step2_lfo_cnt_sr));
	
	wire [6:0] lfo_cnt_sum = lfo_cnt_sr_out + { 6'h0, lfo_subcnt_of };
	
	assign lfo_cnt_sr_in = lfo[3] ? lfo_cnt_sum : 7'h00;
	
	wire fsm_sel0;
	
	wire ss_step3_fsm_sel0_sr;
	ym_sr_bit fsm_sel0_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(fsm_sel23),
		.sr_out(fsm_sel0)
		, .ss_en(ss_en), .ss_in(ss_step2_lfo_cnt_sr), .ss_out(ss_step3_fsm_sel0_sr));
	
	wire lfo_cnt_load;
	
	wire ss_step4_lfo_ed;
	ym_edge_detect lfo_ed
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(fsm_sel0),
		.outp(lfo_cnt_load)
		, .ss_en(ss_en), .ss_in(ss_step3_fsm_sel0_sr), .ss_out(ss_step4_lfo_ed));
	
	wire [6:0] lfo_cnt_lock;
	
	wire ss_step5_lfo_cnt_l;
	ym_slatch #(.DATA_WIDTH(7)) lfo_cnt_l
		(
		.MCLK(MCLK),
		.en(lfo_cnt_load),
		.inp(lfo_cnt_sr_out),
		.val(lfo_cnt_lock),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step4_lfo_ed), .ss_out(ss_step5_lfo_cnt_l));
	
	assign lfo_am = ~(lfo_cnt_lock[5:0] ^ {6{lfo_cnt_lock[6]}});
	
	wire lfo_pm_sign_l_o;
	
	wire ss_step6_lfo_pm_sign_l;
	ym_dlatch_1 lfo_pm_sign_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(lfo_cnt_lock[6]),
		.val(lfo_pm_sign_l_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step5_lfo_cnt_l), .ss_out(ss_step6_lfo_pm_sign_l));
	
	wire [2:0] lfo_pm_val = lfo_cnt_lock[4:2] ^ {3{lfo_cnt_lock[5]}};
	
	wire [7:0] lfo_pm_val_sel;
		
	generate
		for (i = 0; i < 8; i=i+1)
		begin : l2
			assign lfo_pm_val_sel[i] = lfo_pm_val == i;
		end
	endgenerate
	
	wire lfo_pms_1 = pms == 3'h1;
	wire lfo_pms_2 = pms == 3'h2;
	wire lfo_pms_3 = pms == 3'h3;
	wire lfo_pms_4 = pms == 3'h4;
	wire lfo_pms_5 = pms == 3'h5;
	wire lfo_pms_6 = pms == 3'h6;
	wire lfo_pms_7 = pms == 3'h7;
	wire lfo_pms_6_7 = lfo_pms_6 | lfo_pms_7;
	wire lfo_pms_5_6_7 = lfo_pms_5 | lfo_pms_6_7;
	
	wire lfo_pm_sel_sh2_2 = ((lfo_pm_val_sel[3] | lfo_pm_val_sel[6]) & lfo_pms_5_6_7)
		| ((lfo_pm_val_sel[2] | lfo_pm_val_sel[6]) & lfo_pms_4)
		| ((lfo_pm_val_sel[2] | lfo_pm_val_sel[3] | lfo_pm_val_sel[6] | lfo_pm_val_sel[7]) & lfo_pms_3)
		| ((lfo_pm_val_sel[3] | lfo_pm_val_sel[4] | lfo_pm_val_sel[5]) & lfo_pms_2)
		| ((lfo_pm_val_sel[4] | lfo_pm_val_sel[5] | lfo_pm_val_sel[6] | lfo_pm_val_sel[7]) & lfo_pms_1);
	
	wire lfo_pm_sel_sh2_1 = lfo_pm_val_sel[7] & lfo_pms_5_6_7;
	
	wire lfo_pm_sel_sh1_1 = ((lfo_pm_val_sel[2] | lfo_pm_val_sel[3]) & lfo_pms_5_6_7)
		| ((lfo_pm_val_sel[3] | lfo_pm_val_sel[4] | lfo_pm_val_sel[5] | lfo_pm_val_sel[6]) & lfo_pms_4)
		| ((lfo_pm_val_sel[4] | lfo_pm_val_sel[5] | lfo_pm_val_sel[6] | lfo_pm_val_sel[7]) & lfo_pms_3)
		| ((lfo_pm_val_sel[6] | lfo_pm_val_sel[7]) & lfo_pms_2);
	
	wire lfo_pm_sel_sh1_0 = ((lfo_pm_val_sel[4] | lfo_pm_val_sel[5] | lfo_pm_val_sel[6] | lfo_pm_val_sel[7]) & lfo_pms_5_6_7)
		| (lfo_pm_val_sel[7] & lfo_pms_4);
	
	wire lfo_pms_5_l_o;
	wire lfo_pms_6_l_o;
	wire lfo_pms_7_l_o;
	
	wire ss_step7_lfo_pms_5_l;
	ym_dlatch_1 lfo_pms_5_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(lfo_pms_6_7),
		.val(),
		.nval(lfo_pms_5_l_o)
		, .ss_en(ss_en), .ss_in(ss_step6_lfo_pm_sign_l), .ss_out(ss_step7_lfo_pms_5_l));
	
	wire ss_step8_lfo_pms_6_l;
	ym_dlatch_1 lfo_pms_6_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(~lfo_pms_6),
		.val(),
		.nval(lfo_pms_6_l_o)
		, .ss_en(ss_en), .ss_in(ss_step7_lfo_pms_5_l), .ss_out(ss_step8_lfo_pms_6_l));
	
	wire ss_step9_lfo_pms_7_l;
	ym_dlatch_1 lfo_pms_7_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(~lfo_pms_7),
		.val(),
		.nval(lfo_pms_7_l_o)
		, .ss_en(ss_en), .ss_in(ss_step8_lfo_pms_6_l), .ss_out(ss_step9_lfo_pms_7_l));
		
	wire [6:0] lfo_pm_add_1_i =
		~((fnum[10:4] & {7{lfo_pm_sel_sh1_0}}) | ({1'h0, fnum[10:5] } & {7{lfo_pm_sel_sh1_1}}));
	wire [6:0] lfo_pm_add_2_i =
		~(({ 1'h0, fnum[10:5] } & {7{lfo_pm_sel_sh2_1}}) | ({2'h0, fnum[10:6] } & {7{lfo_pm_sel_sh2_2}}));
	wire [6:0] lfo_pm_add_1_o;
	wire [6:0] lfo_pm_add_2_o;
	
	wire ss_step10_lfo_pm_add_1_l;
	ym_dlatch_1 #(.DATA_WIDTH(7)) lfo_pm_add_1_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(lfo_pm_add_1_i),
		.val(),
		.nval(lfo_pm_add_1_o)
		, .ss_en(ss_en), .ss_in(ss_step9_lfo_pms_7_l), .ss_out(ss_step10_lfo_pm_add_1_l));
	
	wire ss_step11_lfo_pm_add_2_l;
	ym_dlatch_1 #(.DATA_WIDTH(7)) lfo_pm_add_2_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(lfo_pm_add_2_i),
		.val(),
		.nval(lfo_pm_add_2_o)
		, .ss_en(ss_en), .ss_in(ss_step10_lfo_pm_add_1_l), .ss_out(ss_step11_lfo_pm_add_2_l));
	
	wire [7:0] lfo_pm_sum = lfo_pm_add_1_o + lfo_pm_add_2_o;
	
	wire [7:0] lfo_pm_sum_sh =
		(lfo_pm_sum & {8{lfo_pms_7_l_o}})
		| ({ 1'h0, lfo_pm_sum[7:1] } & {8{lfo_pms_6_l_o}})
		| ({ 2'h0, lfo_pm_sum[7:2] } & {8{lfo_pms_5_l_o}});
	
	wire [7:0] lfo_pm_sum_xnor = ~(lfo_pm_sum_sh ^ {8{lfo_pm_sign_l_o}});
	
	wire [7:0] lfo_pm_sum_o;
	
	wire ss_step12_lfo_pm_sum_l;
	ym_dlatch_2 #(.DATA_WIDTH(8)) lfo_pm_sum_l
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(lfo_pm_sum_xnor),
		.val(),
		.nval(lfo_pm_sum_o)
		, .ss_en(ss_en), .ss_in(ss_step11_lfo_pm_add_2_l), .ss_out(ss_step12_lfo_pm_sum_l));
	
	wire lfo_pm_sign_l2_o;
	
	wire ss_step13_lfo_pm_sign_l2;
	ym_dlatch_2 lfo_pm_sign_l2
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(~lfo_pm_sign_l_o),
		.val(),
		.nval(lfo_pm_sign_l2_o)
		, .ss_en(ss_en), .ss_in(ss_step12_lfo_pm_sum_l), .ss_out(ss_step13_lfo_pm_sign_l2));
	
	wire lfo_pm_sign_l3_o;
	
	wire ss_step14_lfo_pm_sign_l3;
	ym_dlatch_2 lfo_pm_sign_l3
		(
		.MCLK(MCLK),
		.c2(c2),
		.inp(lfo_pm_sign_l_o),
		.val(lfo_pm_sign_l3_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step13_lfo_pm_sign_l2), .ss_out(ss_step14_lfo_pm_sign_l3));
	
	wire [10:0] fnum_sr_o;
	
	wire ss_step15_fnum_sr;
	ym_sr_bit_array #(.DATA_WIDTH(11)) fnum_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(fnum),
		.data_out(fnum_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step14_lfo_pm_sign_l3), .ss_out(ss_step15_fnum_sr));
	
	wire [11:0] fnum_lfo_add = {fnum_sr_o, 1'h0} + { {4 {lfo_pm_sign_l2_o}}, lfo_pm_sum_o} + lfo_pm_sign_l3_o;
	
	wire ss_step16_fnum_lfo_l;
	ym_dlatch_1 #(.DATA_WIDTH(12)) fnum_lfo_l
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(fnum_lfo_add),
		.val(fnum_lfo),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step15_fnum_sr), .ss_out(ss_step16_fnum_lfo_l));
	


	assign ss_out = ss_step16_fnum_lfo_l;
endmodule
