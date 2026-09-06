// The snapshot buffer, as a dual clock memory.
//
// The controller fills and replays it on clk_md. The dump that carries it out
// to DDR3 runs on clk_sys, because that is the clock DDRAM_CLK is driven from
// and crossing that boundary by hand loses requests. Port B exists only so the
// dump can read what the controller wrote without either side changing clock.

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

	// write-first on both ports. Once port B writes as well as reads this is a true
	// dual-port memory, and Quartus refuses to infer one whose read-during-write
	// returns the old contents: "uninferred due to unsupported read-during-write
	// behavior", then "Cannot synthesize dual-port RAM logic", and the build stops
	// in analysis. Neither side ever reads an address the other is writing - the
	// controller is idle while the dump moves a slot - so which value comes back in
	// that case does not matter, only that the shape is one the tool can build.
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
