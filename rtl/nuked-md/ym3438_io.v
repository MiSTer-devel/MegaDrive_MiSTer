module ym3438_io
	(
	input ss_en,
	input ss_in,
	output ss_out,

	input MCLK,
	input c1,
	input c2,
	input [1:0] address,
	input [7:0] data,
	input CS,
	input WR,
	input RD,
	input IC,
	input timer_a,
	input timer_b,
	input [7:0] reg_21,
	input [7:3] reg_2c,
	input pg_dbg,
	input eg_dbg,
	input eg_dbg_inc,
	input [13:0] op_dbg,
	input [8:0] ch_dbg,
	output write_addr_en,
	output write_data_en,
	output [7:0] data_bus,
	output bank,
	output [7:0] data_o,
	output io_dir,
	output irq,
	input ym2612_status_enable
	);
	
	
	wire read_en = (~RD & IC & ~CS) & (~ym2612_status_enable | address == 2'h0);
	wire write_addr = (~WR & ~CS & ~address[0]) | ~IC;
	wire write_data = ~WR & ~CS & address[0] & IC;
	
	wire io_IC = IC;
	
	wire write_a_tr1_q, write_a_tr1_nq;
	
	wire write_a_sig;
	
	wire ss_step1_write_a_tr1;
	ym_rs_trig write_a_tr1
		(
		.MCLK(MCLK),
		.set(write_addr),
		.rst(write_a_sig),
		.q(write_a_tr1_q),
		.nq(write_a_tr1_nq)
		, .ss_en(ss_en), .ss_in(ss_in), .ss_out(ss_step1_write_a_tr1));
	
	wire write_a_tr2_q;
	
	wire ss_step2_write_a_tr2;
	ym_rs_trig_sync write_a_tr2
		(
		.MCLK(MCLK),
		.set(write_a_tr1_q),
		.rst(write_a_tr1_nq),
		.c1(c1),
		.q(write_a_tr2_q),
		.nq()
		, .ss_en(ss_en), .ss_in(ss_step1_write_a_tr1), .ss_out(ss_step2_write_a_tr2));
	
	wire ss_step3_write_a_sl;
	ym_slatch write_a_sl
		(
		.MCLK(MCLK),
		.en(c2),
		.inp(write_a_tr2_q),
		.val(write_a_sig),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step2_write_a_tr2), .ss_out(ss_step3_write_a_sl));
	
	wire write_a_sig_delay;
	
	wire ss_step4_write_a_sr;
	ym_sr_bit write_a_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(write_a_sig),
		.sr_out(write_a_sig_delay)
		, .ss_en(ss_en), .ss_in(ss_step3_write_a_sl), .ss_out(ss_step4_write_a_sr));
	
	assign write_addr_en = write_a_sig & ~write_a_sig_delay;
	
	wire write_d_tr1_q, write_d_tr1_nq;
	
	wire write_d_sig;
	
	wire ss_step5_write_d_tr1;
	ym_rs_trig write_d_tr1
		(
		.MCLK(MCLK),
		.set(write_data),
		.rst(write_d_sig),
		.q(write_d_tr1_q),
		.nq(write_d_tr1_nq)
		, .ss_en(ss_en), .ss_in(ss_step4_write_a_sr), .ss_out(ss_step5_write_d_tr1));
	
	wire write_d_tr2_q;
	
	wire ss_step6_write_d_tr2;
	ym_rs_trig_sync write_d_tr2
		(
		.MCLK(MCLK),
		.set(write_d_tr1_q),
		.rst(write_d_tr1_nq),
		.c1(c1),
		.q(write_d_tr2_q),
		.nq()
		, .ss_en(ss_en), .ss_in(ss_step5_write_d_tr1), .ss_out(ss_step6_write_d_tr2));
	
	wire ss_step7_write_d_sl;
	ym_slatch write_d_sl
		(
		.MCLK(MCLK),
		.en(c2),
		.inp(write_d_tr2_q),
		.val(write_d_sig),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step6_write_d_tr2), .ss_out(ss_step7_write_d_sl));
		
	wire write_d_sig_delay;
	
	wire ss_step8_write_d_sr;
	ym_sr_bit write_d_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(write_d_sig),
		.sr_out(write_d_sig_delay)
		, .ss_en(ss_en), .ss_in(ss_step7_write_d_sl), .ss_out(ss_step8_write_d_sr));
	
	assign write_data_en = write_d_sig & ~write_d_sig_delay;
	
	wire [8:0] data_l_out;
	wire [8:0] data_in = { address[1], data };
	wire data_l_en = ~WR & ~CS;
	
	wire ss_step8b_data_l;
	ym_slatch #(.DATA_WIDTH(9)) data_l
		(
		.MCLK(MCLK),
		.en(data_l_en),
		.inp(data_in),
		.val(data_l_out),
		.nval()
		, .ss_en(ss_en), .ss_in(ss_step8_write_d_sr), .ss_out(ss_step8b_data_l));
	
	wire busy_of;
	
	wire busy_state_o;
	
	wire ss_step9_busy_cnt;
	ym_cnt_bit #(.DATA_WIDTH(5)) busy_cnt
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.c_in(~busy_state_o),
		.reset(~io_IC),
		.val(),
		.c_out(busy_of)
		, .ss_en(ss_en), .ss_in(ss_step8b_data_l), .ss_out(ss_step9_busy_cnt));
	
	wire busy_state_i = ~(write_data_en | (~busy_state_o & ~(busy_of | ~io_IC)));
	
	wire ss_step10_busy_sr;
	ym_sr_bit busy_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.bit_in(busy_state_i),
		.sr_out(busy_state_o)
		, .ss_en(ss_en), .ss_in(ss_step9_busy_cnt), .ss_out(ss_step10_busy_sr));
	
	assign io_dir = ~(IC & ~RD & ~CS);
	
	assign data_bus = (io_dir & IC) ? data_l_out[7:0] : 8'h00; // tristate + pull down

	assign bank = data_l_out[8];
	
	wire read_status = ~reg_21[6] & read_en;
	wire read_debug = reg_21[6] & read_en;
	
	wire timer_a_status_sl_out;
	
	wire ss_step11_timer_a_status_sl;
	ym_slatch timer_a_status_sl
		(
		.MCLK(MCLK),
		.en(~read_en),
		.inp(timer_a),
		.val(),
		.nval(timer_a_status_sl_out)
		, .ss_en(ss_en), .ss_in(ss_step10_busy_sr), .ss_out(ss_step11_timer_a_status_sl));
	
	wire timer_b_status_sl_out;
	
	wire ss_step12_timer_b_status_sl;
	ym_slatch timer_b_status_sl
		(
		.MCLK(MCLK),
		.en(~read_en),
		.inp(timer_b),
		.val(),
		.nval(timer_b_status_sl_out)
		, .ss_en(ss_en), .ss_in(ss_step11_timer_a_status_sl), .ss_out(ss_step12_timer_b_status_sl));
	
	reg [7:0] data_o_r = 0;
	reg [25:0] status_time = 0;
	
	wire [7:0] debug_data;
	always @(posedge MCLK)
	begin
		if (ss_en)
		begin
			data_o_r <= {data_o_r[6:0], ss_step12_timer_b_status_sl};
			status_time <= {status_time[24:0], data_o_r[7]};
		end
		else
		begin

		if (read_status)
			data_o_r <= { ~busy_state_o, 5'h0, timer_b_status_sl_out, timer_a_status_sl_out };
		if (read_debug)
			data_o_r <= debug_data;

		if (read_status | read_debug)
			status_time <= 26'd40000000;
		else if (status_time)
			status_time <= status_time - 1;
		else
			data_o_r <= 8'h0;
			end
end
	assign data_o = data_o_r;
	
	assign irq = ~(timer_a_status_sl_out | timer_b_status_sl_out);
	
	wire [15:0] debug_data_w;
	wire [6:0] debug_data1_1;
	wire [6:0] debug_data1_2;
	
	assign debug_data = reg_21[7] ? debug_data_w[15:8] : debug_data_w[7:0];
	
	wire [8:0] ch_dbg_sr_o;
	
	wire ss_step14_ch_dbg_sr;
	ym_sr_bit_array #(.DATA_WIDTH(9)) ch_dbg_sr
		(
		.MCLK(MCLK),
		.c1(c1),
		.c2(c2),
		.data_in(ch_dbg),
		.data_out(ch_dbg_sr_o)
		, .ss_en(ss_en), .ss_in(status_time[25]), .ss_out(ss_step14_ch_dbg_sr));
	
	assign debug_data_w[15] = pg_dbg;
	assign debug_data_w[14] = reg_21[0] ? eg_dbg : eg_dbg_inc;
	assign debug_data_w[13:0] = reg_2c[4] ? { 5'h0, ch_dbg_sr_o } : op_dbg;


	assign ss_out = ss_step14_ch_dbg_sr;
endmodule
