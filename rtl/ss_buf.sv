// dump runs on clk_sys, DDRAM_CLK's own clock; crossing by hand drops requests.
module ss_buf #(parameter WORDS = 1024)
(
	input             clka,
	input             wea,
	input       [9:0] addra,
	input      [63:0] dina,
	output reg [63:0] qa = 0,

	input             clkb,
	input             web,
	input      [63:0] dinb,
	input       [9:0] addrb,
	output reg [63:0] qb = 0
);

	(* ramstyle = "M10K" *) reg [63:0] mem [0:WORDS-1];

	// write-first on both ports: Quartus refuses to infer dual-port RAM whose
	// read-during-write returns old data. Neither side reads an address the
	// other is writing, so which value wins here does not matter.
	always @(posedge clka) begin
		if (wea) begin
			mem[addra] <= dina;
			qa         <= dina;
		end
		else qa <= mem[addra];
	end

	always @(posedge clkb) begin
		if (web) begin
			mem[addrb] <= dinb;
			qb         <= dinb;
		end
		else qb <= mem[addrb];
	end

endmodule
