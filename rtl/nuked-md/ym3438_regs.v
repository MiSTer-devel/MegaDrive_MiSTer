module ym3438_reg_ctrl
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input MCLK,
	input c1,
	input c2,
	input [7:0] data,
	input bank,
	input write_addr_en,
	input write_data_en,
	input IC,
	input fsm_sel_23,
	input fsm_sel_1,
	input timer_ed,
	input ch3_sel,
	input [1:0] rate_sel,
	input fsm_dac_load,
	input fsm_dac_out_sel,
	output [3:0] multi,
	output [2:0] dt,
	output [6:0] tl,
	output [1:0] ks,
	output [4:0] sl,
	output ssg_enable,
	output ssg_inv,
	output ssg_repeat,
	output ssg_holdup,
	output ssg_type0,
	output ssg_type2,
	output ssg_type3,
	output [4:0] rate,
	output [10:0] fnum,
	output [2:0] block,
	output [1:0] note,
	output [2:0] connect,
	output [2:0] fb,
	output [2:0] pms,
	output [1:0] ams,
	output [1:0] pan_o,
	output [7:0] reg_21,
	output [3:0] lfo,
	output [7:0] dac,
	output dac_en,
	output [7:3] reg_2c,
	output kon,
	output kon_csm,
	output mode_csm,
	output timer_a_status,
	output timer_b_status,
	output [2:0] dac_index
	);
	
	wire fm_addr_write = (data[7:4] != 0) & write_addr_en;
	
	wire fm_addr_sr_o;
	
	wire ss_step1_fm_addr_sr;
	ym_sr_bit fm_addr_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(~((~write_addr_en & ~fm_addr_sr_o) | fm_addr_write)),
		.sr_out(fm_addr_sr_o)
		, .ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_step1_fm_addr_sr));
	
	wire fm_data_write = ~fm_addr_sr_o & write_data_en;
	
	wire fm_data_sr_o2;
	wire fm_data_sr_o = ~fm_data_sr_o2;
	
	wire ss_step2_fm_data_sr;
	ym_sr_bit fm_data_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(~((~write_addr_en & fm_data_sr_o) | fm_data_write)),
		.sr_out(fm_data_sr_o2)
		, .ss_en(ss_en), .ss_in(ss_step1_fm_addr_sr), .ss_out(ss_step2_fm_data_sr));
		
	wire nIC = ~IC;
	
	wire [8:0] fm_address_in;
	wire [8:0] fm_address_out;
	
	assign fm_address_in = nIC ? 9'h000 : (fm_addr_write ? { bank, data } : fm_address_out); 
	
	wire ss_step3_fm_address;
	ym_sr_bit_array #(.DATA_WIDTH(9)) fm_address
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(fm_address_in),
		.data_out(fm_address_out)
		, .ss_en(ss_en), .ss_in(ss_step2_fm_data_sr), .ss_out(ss_step3_fm_address));
	
	wire [7:0] fm_data_in;
	wire [7:0] fm_data_out;
	
	assign fm_data_in = nIC ? 8'h00 : (fm_data_write ? data : fm_data_out); 
	
	wire ss_step4_fm_data;
	ym_sr_bit_array #(.DATA_WIDTH(8)) fm_data
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(fm_data_in),
		.data_out(fm_data_out)
		, .ss_en(ss_en), .ss_in(ss_step3_fm_address), .ss_out(ss_step4_fm_data));
	
	wire [1:0] cnt_low_out;
	wire [2:0] cnt_high_out;
	
	wire [4:0] reg_cnt = { cnt_high_out, cnt_low_out };
	
	wire cnt_reset = nIC | fsm_sel_23;
	
	wire reset_low_cnt = cnt_reset | cnt_low_out[1];
	
	wire ss_step5_cnt_low;
	ym_cnt_bit #(.DATA_WIDTH(2)) cnt_low
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.c_in(1'h1),
		.reset(reset_low_cnt),
		.val(cnt_low_out),
		.c_out()
		, .ss_en(ss_en), .ss_in(ss_step4_fm_data), .ss_out(ss_step5_cnt_low));
	
	wire ss_step6_cnt_high;
	ym_cnt_bit #(.DATA_WIDTH(3)) cnt_high
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.c_in(cnt_low_out[1]),
		.reset(cnt_reset),
		.val(cnt_high_out),
		.c_out()
		, .ss_en(ss_en), .ss_in(ss_step5_cnt_low), .ss_out(ss_step6_cnt_high));

	wire ch_match = ~((reg_cnt[0] ^ fm_address_out[0]) | (reg_cnt[1] ^ fm_address_out[1]) | (reg_cnt[2] ^ fm_address_out[8]));
	
	wire ch_write = ch_match & fm_data_sr_o;
	
	wire ch_writeA0 = ch_write & (fm_address_out[7:2] == 6'h28);
	wire ch_writeA4 = ch_write & (fm_address_out[7:2] == 6'h29);
	wire ch_writeA8 = ch_write & (fm_address_out[7:2] == 6'h2a);
	wire ch_writeAC = ch_write & (fm_address_out[7:2] == 6'h2b);
	wire ch_writeB0 = ch_write & (fm_address_out[7:2] == 6'h2c);
	wire ch_writeB4 = ch_write & (fm_address_out[7:2] == 6'h2d);
	
	wire op_match = ~((reg_cnt[0] ^ fm_address_out[0]) | (reg_cnt[1] ^ fm_address_out[1]) | (reg_cnt[3] ^ fm_address_out[2]) | (reg_cnt[2] ^ fm_address_out[8]));
	
	wire op_write = op_match & fm_data_sr_o;
	
	wire op_write30 = op_write & (fm_address_out[7:4] == 4'h3);
	wire op_write40 = op_write & (fm_address_out[7:4] == 4'h4);
	wire op_write50 = op_write & (fm_address_out[7:4] == 4'h5);
	wire op_write60 = op_write & (fm_address_out[7:4] == 4'h6);
	wire op_write70 = op_write & (fm_address_out[7:4] == 4'h7);
	wire op_write80 = op_write & (fm_address_out[7:4] == 4'h8);
	wire op_write90 = op_write & (fm_address_out[7:4] == 4'h9);
	
	wire [3:0] reg_multi_o;
	
	wire ss_step7_reg_multi_sr;
	ym_sr_bit_array #(.DATA_WIDTH(4), .SR_LENGTH(2)) reg_multi_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(reg_multi_o),
		.data_out(multi)
		, .ss_en(ss_en), .ss_in(ss_step6_cnt_high), .ss_out(ss_step7_reg_multi_sr));
	
	wire ss_step8_reg_multi;
	ym3438_op_register #(.DATA_WIDTH(4)) reg_multi
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[3:0]),
		.write_en(op_write30),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(reg_multi_o)
		, .ss_en(ss_en), .ss_in(ss_step7_reg_multi_sr), .ss_out(ss_step8_reg_multi));
	
	wire ss_step9_reg_dt;
	ym3438_op_register #(.DATA_WIDTH(3)) reg_dt
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[6:4]),
		.write_en(op_write30),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(dt)
		, .ss_en(ss_en), .ss_in(ss_step8_reg_multi), .ss_out(ss_step9_reg_dt));
	
	wire ss_step10_reg_tl;
	ym3438_op_register #(.DATA_WIDTH(7)) reg_tl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[6:0]),
		.write_en(op_write40),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(tl)
		, .ss_en(ss_en), .ss_in(ss_step9_reg_dt), .ss_out(ss_step10_reg_tl));
		
	wire [4:0] ar;
	
	wire ss_step11_reg_ar;
	ym3438_op_register #(.DATA_WIDTH(5)) reg_ar
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[4:0]),
		.write_en(op_write50),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(ar)
		, .ss_en(ss_en), .ss_in(ss_step10_reg_tl), .ss_out(ss_step11_reg_ar));
	
	wire ss_step12_reg_ks;
	ym3438_op_register #(.DATA_WIDTH(2)) reg_ks
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[7:6]),
		.write_en(op_write50),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(ks)
		, .ss_en(ss_en), .ss_in(ss_step11_reg_ar), .ss_out(ss_step12_reg_ks));
		
	wire [4:0] dr;
	
	wire ss_step13_reg_dr;
	ym3438_op_register #(.DATA_WIDTH(5)) reg_dr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[4:0]),
		.write_en(op_write60),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(dr)
		, .ss_en(ss_en), .ss_in(ss_step12_reg_ks), .ss_out(ss_step13_reg_dr));
		
	wire am;
	
	wire ss_step14_reg_am;
	ym3438_op_register #(.DATA_WIDTH(1)) reg_am
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[7:7]),
		.write_en(op_write60),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(am)
		, .ss_en(ss_en), .ss_in(ss_step13_reg_dr), .ss_out(ss_step14_reg_am));
		
	wire [4:0] sr;
	
	wire ss_step15_reg_sr;
	ym3438_op_register #(.DATA_WIDTH(5)) reg_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[4:0]),
		.write_en(op_write70),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(sr)
		, .ss_en(ss_en), .ss_in(ss_step14_reg_am), .ss_out(ss_step15_reg_sr));
		
	wire [3:0] rr;
	
	wire ss_step16_reg_rr;
	ym3438_op_register #(.DATA_WIDTH(4)) reg_rr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[3:0]),
		.write_en(op_write80),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(rr)
		, .ss_en(ss_en), .ss_in(ss_step15_reg_sr), .ss_out(ss_step16_reg_rr));
	
	wire ss_step17_reg_sl;
	ym3438_op_register #(.DATA_WIDTH(4)) reg_sl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[7:4]),
		.write_en(op_write80),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(sl[3:0])
		, .ss_en(ss_en), .ss_in(ss_step16_reg_rr), .ss_out(ss_step17_reg_sl));
	
	assign sl[4] = sl[3:0] == 4'hf;
	
	wire [3:0] ssgeg;
	
	wire ss_step18_reg_ssgeg;
	ym3438_op_register #(.DATA_WIDTH(4)) reg_ssgeg
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[3:0]),
		.write_en(op_write90),
		.rst(nIC),
		.bank(fm_address_out[3]),
		.obank(reg_cnt[4]),
		.data_o(ssgeg)
		, .ss_en(ss_en), .ss_in(ss_step17_reg_sl), .ss_out(ss_step18_reg_ssgeg));
		
	assign ssg_enable = ssgeg[3];
	assign ssg_inv = ssgeg[2] & ssg_enable;
	assign ssg_repeat = ~ssgeg[0];
	assign ssg_holdup = ssgeg[2:0] == 3'h3 | ssgeg[2:0] == 3'h5;
	assign ssg_type0 = ssgeg[1:0] == 2'h0;
	assign ssg_type2 = ssgeg[1:0] == 2'h2;
	assign ssg_type3 = ssgeg[1:0] == 2'h3;
		
	wire [5:0] reg_a4_in;
	wire [5:0] reg_a4_out;
	
	wire ss_step19_reg_a4;
	ym_sr_bit_array #(.DATA_WIDTH(6)) reg_a4
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(reg_a4_in),
		.data_out(reg_a4_out)
		, .ss_en(ss_en), .ss_in(ss_step18_reg_ssgeg), .ss_out(ss_step19_reg_a4));
	
	assign reg_a4_in = nIC ? 6'h00 : (ch_writeA4 ? fm_data_out[5:0] : reg_a4_out);
		
	wire [5:0] reg_ac_in;
	wire [5:0] reg_ac_out;
	
	wire ss_step20_reg_ac;
	ym_sr_bit_array #(.DATA_WIDTH(6)) reg_ac
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(reg_ac_in),
		.data_out(reg_ac_out)
		, .ss_en(ss_en), .ss_in(ss_step19_reg_a4), .ss_out(ss_step20_reg_ac));
	
	assign reg_ac_in = nIC ? 6'h00 : (ch_writeAC ? fm_data_out[5:0] : reg_ac_out);
	
	wire [10:0] reg_fnum_o;
	
	wire ss_step21_reg_fnum;
	ym3438_ch_register #(.DATA_WIDTH(11)) reg_fnum
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data({reg_a4_out[2:0], fm_data_out}),
		.write_en(ch_writeA0),
		.rst(nIC),
		.data_o_4(reg_fnum_o)
		, .ss_en(ss_en), .ss_in(ss_step20_reg_ac), .ss_out(ss_step21_reg_fnum));
	
	wire [2:0] reg_block_o;
	
	wire ss_step22_reg_block;
	ym3438_ch_register #(.DATA_WIDTH(3)) reg_block
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(reg_a4_out[5:3]),
		.write_en(ch_writeA0),
		.rst(nIC),
		.data_o_4(reg_block_o)
		, .ss_en(ss_en), .ss_in(ss_step21_reg_fnum), .ss_out(ss_step22_reg_block));
	
	wire [10:0] reg_fnum_ch3_o_0;
	wire [10:0] reg_fnum_ch3_o_4;
	wire [10:0] reg_fnum_ch3_o_5;
	
	wire ss_step23_reg_fnum_ch3;
	ym3438_ch_register #(.DATA_WIDTH(11)) reg_fnum_ch3
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data({reg_ac_out[2:0], fm_data_out}),
		.write_en(ch_writeA8),
		.rst(nIC),
		.data_o_0(reg_fnum_ch3_o_0),
		.data_o_4(reg_fnum_ch3_o_4),
		.data_o_5(reg_fnum_ch3_o_5)
		, .ss_en(ss_en), .ss_in(ss_step22_reg_block), .ss_out(ss_step23_reg_fnum_ch3));
	
	wire [2:0] reg_block_ch3_o_0;
	wire [2:0] reg_block_ch3_o_4;
	wire [2:0] reg_block_ch3_o_5;
	
	wire ss_step24_reg_block_ch3;
	ym3438_ch_register #(.DATA_WIDTH(3)) reg_block_ch3
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(reg_ac_out[5:3]),
		.write_en(ch_writeA8),
		.rst(nIC),
		.data_o_0(reg_block_ch3_o_0),
		.data_o_4(reg_block_ch3_o_4),
		.data_o_5(reg_block_ch3_o_5)
		, .ss_en(ss_en), .ss_in(ss_step23_reg_fnum_ch3), .ss_out(ss_step24_reg_block_ch3));
	
	wire ss_step25_reg_connect;
	ym3438_ch_register #(.DATA_WIDTH(3)) reg_connect
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[2:0]),
		.write_en(ch_writeB0),
		.rst(nIC),
		.data_o_5(connect)
		, .ss_en(ss_en), .ss_in(ss_step24_reg_block_ch3), .ss_out(ss_step25_reg_connect));
	
	wire ss_step26_reg_fb;
	ym3438_ch_register #(.DATA_WIDTH(3)) reg_fb
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[5:3]),
		.write_en(ch_writeB0),
		.rst(nIC),
		.data_o_0(fb)
		, .ss_en(ss_en), .ss_in(ss_step25_reg_connect), .ss_out(ss_step26_reg_fb));
	
	wire ss_step27_reg_pms;
	ym3438_ch_register #(.DATA_WIDTH(3)) reg_pms
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[2:0]),
		.write_en(ch_writeB4),
		.rst(nIC),
		.data_o_5(pms)
		, .ss_en(ss_en), .ss_in(ss_step26_reg_fb), .ss_out(ss_step27_reg_pms));
	
	wire [1:0] ams_o;
	
	assign ams = am ? ams_o : 2'h0;
	
	wire ss_step28_reg_ams;
	ym3438_ch_register #(.DATA_WIDTH(2)) reg_ams
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(fm_data_out[5:4]),
		.write_en(ch_writeB4),
		.rst(nIC),
		.data_o_5(ams_o)
		, .ss_en(ss_en), .ss_in(ss_step27_reg_pms), .ss_out(ss_step28_reg_ams));
	
	wire [1:0] pan_o1;
	wire [1:0] pan_o2;
	
	wire ss_step29_reg_pan;
	ym3438_ch_register #(.DATA_WIDTH(2)) reg_pan
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(~fm_data_out[7:6]),
		.write_en(ch_writeB4),
		.rst(nIC),
		.data_o_4(pan_o1),
		.data_o_5(pan_o2)
		, .ss_en(ss_en), .ss_in(ss_step28_reg_ams), .ss_out(ss_step29_reg_pan));
	
	wire [1:0] pan_sel = fsm_dac_out_sel ? ~pan_o2 : ~pan_o1;
	
	wire load_ed_o;
	
	wire ss_step30_load_ed;
	ym_edge_detect load_ed
		(
		.MCLK(MCLK),
		.c1(c1),
		.inp(fsm_dac_load),
		.outp(load_ed_o)
		, .ss_en(ss_en), .ss_in(ss_step29_reg_pan), .ss_out(ss_step30_load_ed));

	wire ss_step31_pan_lock;
	ym_slatch #(.DATA_WIDTH(2)) pan_lock
		(
		.MCLK(MCLK),
		.en(load_ed_o),
		.inp(pan_sel),
		.val(pan_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step30_load_ed), .ss_out(ss_step31_pan_lock));
		
	// EXTRA start
	
	wire [2:0] dac_index_i = reg_cnt[1:0] + (reg_cnt[2] ? 3'h3 : 3'h0) + { 2'h0, ~fsm_dac_out_sel };

	wire ss_step32_dac_index_lock;
	ym_slatch #(.DATA_WIDTH(3)) dac_index_lock
		(
		.MCLK(MCLK),
		.en(load_ed_o),
		.inp(dac_index_i),
		.val(dac_index),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step31_pan_lock), .ss_out(ss_step32_dac_index_lock));
	
	// EXTRA end
		
	wire reg_21_wr;
	
	wire ss_step33_reg_21_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h21)) reg_21_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_21_wr)
		, .ss_en(ss_en), .ss_in(ss_step32_dac_index_lock), .ss_out(ss_step33_reg_21_ctrl));
		
	wire ss_step34_reg_21_data;
	ym3438_reg_data #(.DATA_WIDTH(8)) reg_21_data
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[7:0]),
		.reg_wr(reg_21_wr),
		.rst(nIC),
		.data_o(reg_21)
		, .ss_en(ss_en), .ss_in(ss_step33_reg_21_ctrl), .ss_out(ss_step34_reg_21_data));
		
	wire reg_22_wr;
	
	wire ss_step35_reg_22_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h22)) reg_22_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_22_wr)
		, .ss_en(ss_en), .ss_in(ss_step34_reg_21_data), .ss_out(ss_step35_reg_22_ctrl));
		
	wire ss_step36_reg_22_data;
	ym3438_reg_data #(.DATA_WIDTH(4)) reg_22_data
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[3:0]),
		.reg_wr(reg_22_wr),
		.rst(nIC),
		.data_o(lfo)
		, .ss_en(ss_en), .ss_in(ss_step35_reg_22_ctrl), .ss_out(ss_step36_reg_22_data));
	
	wire [9:0] reg_timer_a_o;
		
	wire reg_24_wr;
	
	wire ss_step37_reg_24_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h24)) reg_24_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_24_wr)
		, .ss_en(ss_en), .ss_in(ss_step36_reg_22_data), .ss_out(ss_step37_reg_24_ctrl));
		
	wire ss_step38_reg_24_data;
	ym3438_reg_data #(.DATA_WIDTH(8)) reg_24_data
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[7:0]),
		.reg_wr(reg_24_wr),
		.rst(nIC),
		.data_o(reg_timer_a_o[9:2])
		, .ss_en(ss_en), .ss_in(ss_step37_reg_24_ctrl), .ss_out(ss_step38_reg_24_data));
		
	wire reg_25_wr;
	
	wire ss_step39_reg_25_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h25)) reg_25_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_25_wr)
		, .ss_en(ss_en), .ss_in(ss_step38_reg_24_data), .ss_out(ss_step39_reg_25_ctrl));
		
	wire ss_step40_reg_25_data;
	ym3438_reg_data #(.DATA_WIDTH(2)) reg_25_data
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[1:0]),
		.reg_wr(reg_25_wr),
		.rst(nIC),
		.data_o(reg_timer_a_o[1:0])
		, .ss_en(ss_en), .ss_in(ss_step39_reg_25_ctrl), .ss_out(ss_step40_reg_25_data));
	
	wire [7:0] reg_timer_b_o;
		
	wire reg_26_wr;
	
	wire ss_step41_reg_26_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h26)) reg_26_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_26_wr)
		, .ss_en(ss_en), .ss_in(ss_step40_reg_25_data), .ss_out(ss_step41_reg_26_ctrl));
		
	wire ss_step42_reg_26_data;
	ym3438_reg_data #(.DATA_WIDTH(8)) reg_26_data
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[7:0]),
		.reg_wr(reg_26_wr),
		.rst(nIC),
		.data_o(reg_timer_b_o)
		, .ss_en(ss_en), .ss_in(ss_step41_reg_26_ctrl), .ss_out(ss_step42_reg_26_data));
		
	wire reg_27_wr;
	
	wire ss_step43_reg_27_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h27)) reg_27_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_27_wr)
		, .ss_en(ss_en), .ss_in(ss_step42_reg_26_data), .ss_out(ss_step43_reg_27_ctrl));
	
	wire [3:0] reg_27_timer_ctrl_o;
		
	wire ss_step44_reg_27_timer_ctrl;
	ym3438_reg_data #(.DATA_WIDTH(4)) reg_27_timer_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[3:0]),
		.reg_wr(reg_27_wr),
		.rst(nIC),
		.data_o(reg_27_timer_ctrl_o)
		, .ss_en(ss_en), .ss_in(ss_step43_reg_27_ctrl), .ss_out(ss_step44_reg_27_timer_ctrl));
	
	wire [1:0] reg_27_timer_reset_o;

	wire ss_step45_reg_27_timer_reset;
	ym_sr_bit_array #(.DATA_WIDTH(2)) reg_27_timer_reset
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(reg_27_wr ? data[5:4] : 2'h0),
		.data_out(reg_27_timer_reset_o)
		, .ss_en(ss_en), .ss_in(ss_step44_reg_27_timer_ctrl), .ss_out(ss_step45_reg_27_timer_reset));
	
	wire [1:0] reg_27_mode_o;
		
	wire ss_step46_reg_27_mode;
	ym3438_reg_data #(.DATA_WIDTH(2)) reg_27_mode
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[7:6]),
		.reg_wr(reg_27_wr),
		.rst(nIC),
		.data_o(reg_27_mode_o)
		, .ss_en(ss_en), .ss_in(ss_step45_reg_27_timer_reset), .ss_out(ss_step46_reg_27_mode));
		
	wire reg_28_wr;
	
	wire ss_step47_reg_28_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h28)) reg_28_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_28_wr)
		, .ss_en(ss_en), .ss_in(ss_step46_reg_27_mode), .ss_out(ss_step47_reg_28_ctrl));
	
	wire [2:0] reg_28_ch_o;
	wire [3:0] reg_28_slot_o;
		
	wire ss_step48_reg_28_ch;
	ym3438_reg_data #(.DATA_WIDTH(3)) reg_28_ch
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[2:0]),
		.reg_wr(reg_28_wr),
		.rst(nIC),
		.data_o(reg_28_ch_o)
		, .ss_en(ss_en), .ss_in(ss_step47_reg_28_ctrl), .ss_out(ss_step48_reg_28_ch));
		
	wire ss_step49_reg_28_slot;
	ym3438_reg_data #(.DATA_WIDTH(4)) reg_28_slot
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[7:4]),
		.reg_wr(reg_28_wr),
		.rst(nIC),
		.data_o(reg_28_slot_o)
		, .ss_en(ss_en), .ss_in(ss_step48_reg_28_ch), .ss_out(ss_step49_reg_28_slot));
		
	wire reg_2a_wr;
	
	wire ss_step50_reg_2a_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h2a)) reg_2a_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_2a_wr)
		, .ss_en(ss_en), .ss_in(ss_step49_reg_28_slot), .ss_out(ss_step50_reg_2a_ctrl));
		
	wire ss_step51_reg_2a_dac;
	ym3438_reg_data #(.DATA_WIDTH(7)) reg_2a_dac
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[6:0]),
		.reg_wr(reg_2a_wr),
		.rst(nIC),
		.data_o(dac[6:0])
		, .ss_en(ss_en), .ss_in(ss_step50_reg_2a_ctrl), .ss_out(ss_step51_reg_2a_dac));

	
	wire reg_dac_msb_in;
	wire reg_dac_msb_out;

	wire ss_step52_reg_dac_msb;
	ym_sr_bit reg_dac_msb
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(reg_dac_msb_in),
		.sr_out(reg_dac_msb_out)
		, .ss_en(ss_en), .ss_in(ss_step51_reg_2a_dac), .ss_out(ss_step52_reg_dac_msb));
		
	assign reg_dac_msb_in = nIC ? 1'h0 : (reg_2a_wr ? ~data[7] : reg_dac_msb_out);
	assign dac[7] = ~reg_dac_msb_out;
		
	wire reg_2b_wr;
	
	wire ss_step53_reg_2b_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h2b)) reg_2b_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_2b_wr)
		, .ss_en(ss_en), .ss_in(ss_step52_reg_dac_msb), .ss_out(ss_step53_reg_2b_ctrl));
		
	wire ss_step54_reg_2b_dac_en;
	ym3438_reg_data #(.DATA_WIDTH(1)) reg_2b_dac_en
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[7]),
		.reg_wr(reg_2b_wr),
		.rst(nIC),
		.data_o(dac_en)
		, .ss_en(ss_en), .ss_in(ss_step53_reg_2b_ctrl), .ss_out(ss_step54_reg_2b_dac_en));
		
	wire reg_2c_wr;
	
	wire ss_step55_reg_2c_ctrl;
	ym3438_reg_wr_ctrl #(.REG_ADDRESS(8'h2c)) reg_2c_ctrl
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data),
		.bank(bank),
		.write_addr_en(write_addr_en),
		.write_data_en(write_data_en),
		.reg_wr(reg_2c_wr)
		, .ss_en(ss_en), .ss_in(ss_step54_reg_2b_dac_en), .ss_out(ss_step55_reg_2c_ctrl));
		
	wire ss_step56_reg_2c_data;
	ym3438_reg_data #(.DATA_WIDTH(5)) reg_2c_data
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data(data[7:3]),
		.reg_wr(reg_2c_wr),
		.rst(nIC),
		.data_o(reg_2c)
		, .ss_en(ss_en), .ss_in(ss_step55_reg_2c_ctrl), .ss_out(ss_step56_reg_2c_data));
	
	wire kon_sr1_in;
	wire kon_sr1_out;
	
	wire ss_step57_kon_sr1;
	ym_sr_bit #(.SR_LENGTH(6)) kon_sr1
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(kon_sr1_in),
		.sr_out(kon_sr1_out)
		, .ss_en(ss_en), .ss_in(ss_step56_reg_2c_data), .ss_out(ss_step57_kon_sr1));
	
	wire kon_sr2_in;
	wire kon_sr2_out;
	
	wire ss_step58_kon_sr2;
	ym_sr_bit #(.SR_LENGTH(6)) kon_sr2
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(kon_sr2_in),
		.sr_out(kon_sr2_out)
		, .ss_en(ss_en), .ss_in(ss_step57_kon_sr1), .ss_out(ss_step58_kon_sr2));
	
	wire kon_sr3_in;
	wire kon_sr3_out;
	
	wire ss_step59_kon_sr3;
	ym_sr_bit #(.SR_LENGTH(6)) kon_sr3
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(kon_sr3_in),
		.sr_out(kon_sr3_out)
		, .ss_en(ss_en), .ss_in(ss_step58_kon_sr2), .ss_out(ss_step59_kon_sr3));
	
	wire kon_sr4_in;
	wire kon_sr4_out;
	
	wire ss_step60_kon_sr4;
	ym_sr_bit #(.SR_LENGTH(6)) kon_sr4
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(kon_sr4_in),
		.sr_out(kon_sr4_out)
		, .ss_en(ss_en), .ss_in(ss_step59_kon_sr3), .ss_out(ss_step60_kon_sr4));
	
	wire kon_ch_match = ~nIC & (reg_cnt == { 2'h0, reg_28_ch_o });
	
	assign kon_sr1_in = kon_ch_match ? reg_28_slot_o[0] : (~nIC & kon_sr4_out);
	assign kon_sr2_in = kon_ch_match ? reg_28_slot_o[3] : kon_sr1_out;
	assign kon_sr3_in = kon_ch_match ? reg_28_slot_o[1] : kon_sr2_out;
	assign kon_sr4_in = kon_ch_match ? reg_28_slot_o[2] : kon_sr3_out;
	
	assign kon = kon_sr4_out | kon_csm;
	
	assign mode_csm = reg_27_mode_o == 2'b10;
	
	wire mode_ch3 = reg_27_mode_o != 2'b00;
	
	wire timer_test = reg_21[2];
	
	wire timer_a_inc;
	wire timer_a_load;
	wire timer_a_load_cnt;
	wire timer_a_cout;
	wire timer_a_load_sr_o;
	wire timer_a_of_sr_o;
	wire timer_a_load_cnt_i;
	
	
	wire ss_step61_timer_a_cnt;
	ym_cnt_bit_load #(.DATA_WIDTH(10)) timer_a_cnt
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.c_in(timer_a_inc),
		.reset(~timer_a_load),
		.load(timer_a_load_cnt),
		.load_val(reg_timer_a_o),
		.val(),
		.c_out(timer_a_cout)
		, .ss_en(ss_en), .ss_in(ss_step60_kon_sr4), .ss_out(ss_step61_timer_a_cnt));
	
	assign timer_a_inc = (timer_a_load & fsm_sel_1) | timer_test;
	
	wire ss_step62_timer_a_load_l;
	ym_slatch timer_a_load_l
		(
		.MCLK(MCLK),
		.en(timer_ed),
		.inp(reg_27_timer_ctrl_o[0]),
		.val(timer_a_load),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step61_timer_a_cnt), .ss_out(ss_step62_timer_a_load_l));
	
	wire ss_step63_timer_a_load_sr;
	ym_sr_bit timer_a_load_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(timer_a_load),
		.sr_out(timer_a_load_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step62_timer_a_load_l), .ss_out(ss_step63_timer_a_load_sr));
	
	wire ss_step64_timer_a_of_sr;
	ym_sr_bit timer_a_of_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(timer_a_cout),
		.sr_out(timer_a_of_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step63_timer_a_load_sr), .ss_out(ss_step64_timer_a_of_sr));
		
	assign timer_a_load_cnt_i = (~timer_a_load_sr_o & timer_a_load) | timer_a_of_sr_o;
	
	wire ss_step65_timer_a_load_cnt_sr;
	ym_sr_bit timer_a_load_cnt_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(timer_a_load_cnt_i),
		.sr_out(timer_a_load_cnt)
		, .ss_en(ss_en), .ss_in(ss_step64_timer_a_of_sr), .ss_out(ss_step65_timer_a_load_cnt_sr));
	
	wire timer_a_status_reset = nIC | reg_27_timer_reset_o[0];
	
	wire timer_a_status_set = ~timer_a_status_reset & timer_a_of_sr_o & reg_27_timer_ctrl_o[2];
	
	wire timer_a_status_sr_o2;
	wire timer_a_status_sr_o = ~timer_a_status_sr_o2;
	assign timer_a_status = ~timer_a_status_sr_o;
	
	wire ss_step66_timer_a_status_sr;
	ym_sr_bit timer_a_status_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(~((timer_a_status_sr_o & ~timer_a_status_reset) | timer_a_status_set)),
		.sr_out(timer_a_status_sr_o2)
		, .ss_en(ss_en), .ss_in(ss_step65_timer_a_load_cnt_sr), .ss_out(ss_step66_timer_a_status_sr));

	
	wire timer_b_inc;
	wire timer_b_load;
	wire timer_b_load_cnt;
	wire timer_b_sub_cout;
	wire timer_b_cout;
	wire timer_b_load_sr_o;
	wire timer_b_of_sr_o;
	wire timer_b_load_cnt_i;
	wire timer_b_subcnt_of_sr_o;
	
	wire ss_step67_timer_b_subcnt;
	ym_cnt_bit #(.DATA_WIDTH(4)) timer_b_subcnt
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.c_in(fsm_sel_1),
		.reset(nIC),
		.val(),
		.c_out(timer_b_sub_cout)
		, .ss_en(ss_en), .ss_in(ss_step66_timer_a_status_sr), .ss_out(ss_step67_timer_b_subcnt));
	
	wire ss_step68_timer_b_subcnt_of_sr;
	ym_sr_bit timer_b_subcnt_of_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(timer_b_sub_cout),
		.sr_out(timer_b_subcnt_of_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step67_timer_b_subcnt), .ss_out(ss_step68_timer_b_subcnt_of_sr));
	
	
	wire ss_step69_timer_b_cnt;
	ym_cnt_bit_load #(.DATA_WIDTH(8)) timer_b_cnt
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.c_in(timer_b_inc),
		.reset(~timer_b_load),
		.load(timer_b_load_cnt),
		.load_val(reg_timer_b_o),
		.val(),
		.c_out(timer_b_cout)
		, .ss_en(ss_en), .ss_in(ss_step68_timer_b_subcnt_of_sr), .ss_out(ss_step69_timer_b_cnt));
	
	assign timer_b_inc = (timer_b_load & timer_b_subcnt_of_sr_o) | timer_test;
	
	wire ss_step70_timer_b_load_l;
	ym_slatch timer_b_load_l
		(
		.MCLK(MCLK),
		.en(timer_ed),
		.inp(reg_27_timer_ctrl_o[1]),
		.val(timer_b_load),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step69_timer_b_cnt), .ss_out(ss_step70_timer_b_load_l));
	
	wire ss_step71_timer_b_load_sr;
	ym_sr_bit timer_b_load_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(timer_b_load),
		.sr_out(timer_b_load_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step70_timer_b_load_l), .ss_out(ss_step71_timer_b_load_sr));
	
	wire ss_step72_timer_b_of_sr;
	ym_sr_bit timer_b_of_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(timer_b_cout),
		.sr_out(timer_b_of_sr_o)
		, .ss_en(ss_en), .ss_in(ss_step71_timer_b_load_sr), .ss_out(ss_step72_timer_b_of_sr));
		
	assign timer_b_load_cnt_i = (~timer_b_load_sr_o & timer_b_load) | timer_b_of_sr_o;
	
	wire ss_step73_timer_b_load_cnt_sr;
	ym_sr_bit timer_b_load_cnt_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(timer_b_load_cnt_i),
		.sr_out(timer_b_load_cnt)
		, .ss_en(ss_en), .ss_in(ss_step72_timer_b_of_sr), .ss_out(ss_step73_timer_b_load_cnt_sr));
	
	wire timer_b_status_reset = nIC | reg_27_timer_reset_o[1];
	
	wire timer_b_status_set = ~timer_b_status_reset & timer_b_of_sr_o & reg_27_timer_ctrl_o[3];
	
	wire timer_b_status_sr_o2;
	wire timer_b_status_sr_o = ~timer_b_status_sr_o2;
	assign timer_b_status = ~timer_b_status_sr_o;
	
	wire ss_step74_timer_b_status_sr;
	ym_sr_bit timer_b_status_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(~((timer_b_status_sr_o & ~timer_b_status_reset) | timer_b_status_set)),
		.sr_out(timer_b_status_sr_o2)
		, .ss_en(ss_en), .ss_in(ss_step73_timer_b_load_cnt_sr), .ss_out(ss_step74_timer_b_status_sr));
	
	wire kon_csm_o;
	
	wire ss_step75_kon_csm_l;
	ym_slatch kon_csm_l
		(
		.MCLK(MCLK),
		.en(timer_ed),
		.inp(mode_csm & timer_a_load_cnt_i),
		.val(kon_csm_o),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step74_timer_b_status_sr), .ss_out(ss_step75_kon_csm_l));
		
	assign kon_csm = kon_csm_o & ch3_sel;
	
	wire [10:0] fnum_mux;
	
	wire ss_step76_fnum_sr;
	ym_sr_bit_array #(.DATA_WIDTH(11)) fnum_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(fnum_mux),
		.data_out(fnum)
		, .ss_en(ss_en), .ss_in(ss_step75_kon_csm_l), .ss_out(ss_step76_fnum_sr));
	
	wire ch3_match = reg_cnt[2:0] == 3'h1;
	
	wire fnum_sel_ch3_1 = (reg_cnt[4:3] == 2'h0) & ch3_match & mode_ch3;
	wire fnum_sel_ch3_2 = (reg_cnt[4:3] == 2'h2) & ch3_match & mode_ch3;
	wire fnum_sel_ch3_3 = (reg_cnt[4:3] == 2'h1) & ch3_match & mode_ch3;
	wire fnum_sel_normal = ~fnum_sel_ch3_1 & ~fnum_sel_ch3_2 & ~fnum_sel_ch3_3;

	assign fnum_mux = (reg_fnum_o & { 11 {fnum_sel_normal}})
		| (reg_fnum_ch3_o_0 & { 11 {fnum_sel_ch3_3}})
		| (reg_fnum_ch3_o_4 & { 11 {fnum_sel_ch3_2}})
		| (reg_fnum_ch3_o_5 & { 11 {fnum_sel_ch3_1}});

	assign block = (reg_block_o & { 3 {fnum_sel_normal}})
		| (reg_block_ch3_o_0 & { 3 {fnum_sel_ch3_3}})
		| (reg_block_ch3_o_4 & { 3 {fnum_sel_ch3_2}})
		| (reg_block_ch3_o_5 & { 3 {fnum_sel_ch3_1}});
	
	assign note[1] = fnum_mux[10];
	assign note[0] = fnum_mux[10] ? (fnum_mux[9:7] != 3'h0) : (fnum_mux[9:7] ==3'h7);
	
	wire rate_sel_a = rate_sel == 2'h0;
	wire rate_sel_d = rate_sel == 2'h1;
	wire rate_sel_s = rate_sel == 2'h2;
	wire rate_sel_r = rate_sel == 2'h3;
	
	assign rate = (
		({5{rate_sel_a}} & ar)
		| ({5{rate_sel_d}} & dr)
		| ({5{rate_sel_s}} & sr)
		| {({4{rate_sel_r}} & rr), rate_sel_r}
		);
	

	assign ss_out = ss_step76_fnum_sr;
endmodule

module ym3438_op_register #(parameter DATA_WIDTH = 1)
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input MCLK,
	input c1,
	input c2,
	input [DATA_WIDTH-1:0] data,
	input write_en,
	input rst,
	input bank,
	input obank,
	output [DATA_WIDTH-1:0] data_o
	);
	
	wire [DATA_WIDTH-1:0] sr1_in;
	wire [DATA_WIDTH-1:0] sr1_out;
	wire ss_step1_sr1;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH), .SR_LENGTH(12)) sr1
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr1_in),
		.data_out(sr1_out)
		, .ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_step1_sr1));
		
	wire [DATA_WIDTH-1:0] sr2_in;
	wire [DATA_WIDTH-1:0] sr2_out;
	wire ss_step2_sr2;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH), .SR_LENGTH(12)) sr2
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr2_in),
		.data_out(sr2_out)
		, .ss_en(ss_en), .ss_in(ss_step1_sr1), .ss_out(ss_step2_sr2));
	
	wire write1 = write_en & ~bank;
	wire write2 = write_en & bank;

	assign sr1_in = rst ? {DATA_WIDTH{1'h0}} : (write1 ? data : sr1_out);
	assign sr2_in = rst ? {DATA_WIDTH{1'h0}} : (write2 ? data : sr2_out);
	
	assign data_o = obank ? sr2_out : sr1_out;
	

	assign ss_out = ss_step2_sr2;
endmodule

module ym3438_ch_register #(parameter DATA_WIDTH = 1)
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input MCLK,
	input c1,
	input c2,
	input [DATA_WIDTH-1:0] data,
	input write_en,
	input rst,
	output [DATA_WIDTH-1:0] data_o_0,
	output [DATA_WIDTH-1:0] data_o_1,
	output [DATA_WIDTH-1:0] data_o_2,
	output [DATA_WIDTH-1:0] data_o_3,
	output [DATA_WIDTH-1:0] data_o_4,
	output [DATA_WIDTH-1:0] data_o_5
	);
	
	wire [DATA_WIDTH-1:0] sr_in[0:5];
	wire [DATA_WIDTH-1:0] sr_out[0:5];
	wire ss_step1_sr_0;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) sr_0
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr_in[0]),
		.data_out(sr_out[0])
		, .ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_step1_sr_0));
	wire ss_step2_sr_1;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) sr_1
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr_in[1]),
		.data_out(sr_out[1])
		, .ss_en(ss_en), .ss_in(ss_step1_sr_0), .ss_out(ss_step2_sr_1));
	wire ss_step3_sr_2;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) sr_2
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr_in[2]),
		.data_out(sr_out[2])
		, .ss_en(ss_en), .ss_in(ss_step2_sr_1), .ss_out(ss_step3_sr_2));
	wire ss_step4_sr_3;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) sr_3
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr_in[3]),
		.data_out(sr_out[3])
		, .ss_en(ss_en), .ss_in(ss_step3_sr_2), .ss_out(ss_step4_sr_3));
	wire ss_step5_sr_4;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) sr_4
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr_in[4]),
		.data_out(sr_out[4])
		, .ss_en(ss_en), .ss_in(ss_step4_sr_3), .ss_out(ss_step5_sr_4));
	wire ss_step6_s_5;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) s_5
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(sr_in[5]),
		.data_out(sr_out[5])
		, .ss_en(ss_en), .ss_in(ss_step5_sr_4), .ss_out(ss_step6_s_5));
	
	assign sr_in[0] = rst ? {DATA_WIDTH{1'h0}} : (write_en ? data : sr_out[5]);
	assign sr_in[1] = sr_out[0]; 
	assign sr_in[2] = sr_out[1]; 
	assign sr_in[3] = sr_out[2]; 
	assign sr_in[4] = sr_out[3]; 
	assign sr_in[5] = sr_out[4];

	assign data_o_0 = sr_out[0];
	assign data_o_1 = sr_out[1];
	assign data_o_2 = sr_out[2];
	assign data_o_3 = sr_out[3];
	assign data_o_4 = sr_out[4];
	assign data_o_5 = sr_out[5];
	

	assign ss_out = ss_step6_s_5;
endmodule

module ym3438_reg_wr_ctrl #(parameter REG_ADDRESS = 0)
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input MCLK,
	input c1,
	input c2,
	input [7:0] data,
	input bank,
	input write_addr_en,
	input write_data_en,
	output reg_wr
	);

	
	wire reg_addr_o2;
	wire reg_addr_o = ~reg_addr_o2;
	wire reg_addr_sel = ~bank & data == REG_ADDRESS & write_addr_en;

	wire ss_step1_reg_addr_sr;
	ym_sr_bit reg_addr_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(~(reg_addr_sel | (reg_addr_o & ~write_addr_en))),
		.sr_out(reg_addr_o2)
		, .ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_step1_reg_addr_sr));

		
	assign reg_wr = reg_addr_o & ~bank & write_data_en;


	assign ss_out = ss_step1_reg_addr_sr;
endmodule

module ym3438_reg_data #(parameter DATA_WIDTH = 1)
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input MCLK,
	input c1,
	input c2,
	input [DATA_WIDTH-1:0] data,
	input reg_wr,
	input rst,
	output [DATA_WIDTH-1:0] data_o
	);

	
	wire [DATA_WIDTH-1:0] reg_sr_in;
	wire [DATA_WIDTH-1:0] reg_sr_out;

	wire ss_step1_reg_sr;
	ym_sr_bit_array #(.DATA_WIDTH(DATA_WIDTH)) reg_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(reg_sr_in),
		.data_out(reg_sr_out)
		, .ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_step1_reg_sr));

		
	assign reg_sr_in = rst ? {DATA_WIDTH{1'h0}} : (reg_wr ? data : reg_sr_out);
	assign data_o = reg_sr_out;


	assign ss_out = ss_step1_reg_sr;
endmodule
