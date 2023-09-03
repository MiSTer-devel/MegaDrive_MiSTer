module EPPROM_24CXX
(
	input clk,
	input rst, 
	input en,            // Enable Module
	
	input  [1:0]  mode,  // 0: X24C01, 1: 24C01 - 24C16, 2: 24C65
	input  [12:0] mask,
	
	// Chip pins
	output        sda_o, // Serial Out
	input         sda_i, // Serial In
	input         scl,   // Serial Clock

	// BRAM Interface
	output [12:0] ram_addr,
	input   [7:0] ram_q,
	output  [7:0] ram_d,
	output        ram_wr,
	output        ram_rd
);

typedef enum bit [7:0] {
	IDLE     = 8'b00000001,
	ADR_5BIT = 8'b00000010, 
	ADR_7BIT = 8'b00000100, 
	ADR_8BIT = 8'b00001000,
	ADR_DEV  = 8'b00010000,
	START_CHK= 8'b00100000,
	WRITE    = 8'b01000000,
	READ     = 8'b10000000
} state_t;
state_t state;

reg [3:0] sda_old = '1;
reg [3:0] scl_old = '1;
always @(posedge clk) begin
	if (rst) begin
		sda_old <= '1;
		scl_old <= '1;
	end else if (en) begin
		sda_old <= {sda_old[2:0],sda_i};
		scl_old <= {scl_old[2:0],scl};
	end
end

wire sda_rise = (sda_old == 4'b0011);
wire sda_fall = (sda_old == 4'b1100);

wire scl_rise = (scl_old == 4'b0011);
wire scl_fall = (scl_old == 4'b1100);
wire scl_high = (scl_old == 4'b1111);

reg       start = 0, stop = 0, cont = 0;
reg       run = 0;
reg [3:0] bit_cnt = 0;
reg [7:0] din;
reg [7:0] dout;
reg       sack = 0;

always @(posedge clk) begin
	reg prestart;

	if (rst) begin
		prestart <= 0;
		stop <= 0;
		start <= 0;
		cont <= 0;
		run <= 0;
		bit_cnt <= 4'hF;
		sack <= 0;
	end else begin
		start <= 0;
		stop <= 0;
		cont <= 0;
		if (en) begin
			if (sda_fall && scl_high && !prestart) begin
				prestart <= 1;
				run <= 0;
			end
			else if (scl_fall && !run && prestart) begin
				prestart <= 0;
				start <= 1;
				run <= 1;
				bit_cnt <= 4'h7;
			end

			if (sda_rise && scl_high && run) begin
				stop <= 1;
				run <= 0;
				sack <= 0;
			end

			if (scl_fall && run) cont <= 1;

			if (scl_rise && run) begin
				if (!bit_cnt[3]) begin
					din[bit_cnt[2:0]] <= sda_i;
				end
			end
			else if (scl_fall && run) begin
				bit_cnt <= bit_cnt - 4'h1;
				if (!bit_cnt[3]) begin
					sack <= ~|bit_cnt[2:0];
				end
				else begin
					sack <= 0;
					bit_cnt <= 4'h7;
				end
			end
		end
	end
end

assign sda_o = (state == IDLE) ? 1'b1 : 
					(state == READ) ? (dout[bit_cnt[2:0]] | bit_cnt[3]) :
											~sack;
reg ack_old;
always @(posedge clk) if(en) ack_old <= sack;

wire ack_end = (~sack && ack_old);

reg [12:0] addr;
reg        write;
reg        read;
always @(posedge clk) begin
	reg read_delay;
	reg pre_read_delay;

	if (rst) begin
		state <= IDLE;
		addr <= '0;
		write <= 0;
		read <= 0;
	end
	else if(en) begin

		read_delay <= read;
		if (write) addr <= addr + 1'd1;
		if (read_delay) dout <= ram_q;
		
		write <= 0;
		read <= 0;

		case (state)
			IDLE:
				if (start) begin
					state <= mode == 0 ? ADR_7BIT : ADR_DEV;
				end
			
			ADR_DEV:
				if (ack_end) begin
					if (din[0]) begin
						read <= 1;
						state <= READ;
					end
					else begin
						addr[10:8] <= din[3:1];
						state <= mode == 2 ? ADR_5BIT : ADR_8BIT;
					end
				end
			
			ADR_5BIT:
				if (ack_end) begin
					addr[12:8] <= din[4:0];
					state <= ADR_8BIT;
				end

			ADR_7BIT:
				if (ack_end) begin
					addr[6:0] <= din[7:1];
					if (din[0]) begin
						read <= 1;
						state <= READ;
					end
					else begin
						state <= WRITE;
					end
				end
			
			ADR_8BIT:
				if (ack_end) begin
					addr[7:0] <= din[7:0];
					state <= START_CHK;
				end
			
			START_CHK:
				if (start) state <= ADR_DEV;
				else if (cont) state <= WRITE;
			
			READ:
				if (ack_end) begin
					addr <= addr + 1'd1;
					read <= 1;
				end
			
			WRITE:
				if (ack_end) begin
					write <= 1;
				end
		endcase
		
		if (stop) state <= IDLE;
	end
end

assign ram_addr = addr & mask;
assign ram_d = din;
assign ram_wr = write;
assign ram_rd = read;
	
endmodule
