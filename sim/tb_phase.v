`timescale 1ns/1ps
// does a one-clock strobe at 107.37 MHz reach a register on the 53.69 MHz clock
// beside it? reproduces the walk's three-clocks-per-word timing.
module tb_phase;
	reg md = 0; always #4.657 md = ~md;
	reg sys = 0;
	initial begin #4.657; forever begin sys = 1; #9.314; sys = 0; #9.314; end end

	reg        wr = 0, wr_hold = 0;
	reg  [1:0] ext = 0;
	reg  [3:0] addr = 0;
	integer    step = 0, k;
	reg [15:0] seen_plain = 0, seen_hold = 0;

	always @(posedge md) begin
		wr <= 0;
		step <= step + 1;
		// mphase 0 waits, 1..4 write: five steps of three clocks per buffer word
		if (step % 3 == 2) begin
			if (((step / 3) % 5) != 0) begin
				wr   <= 1;
				addr <= addr + 1'b1;
			end
		end
		if (wr)         ext <= 2'd2;
		else if (|ext)  ext <= ext - 1'd1;
	end
	always @* wr_hold = wr | (|ext);

	always @(posedge sys) begin
		if (wr)      seen_plain[addr] <= 1;
		if (wr_hold) seen_hold[addr]  <= 1;
	end

	initial begin
		repeat (4000) @(posedge md);
		$display("one clock strobe, words seen on the slow clock: %b", seen_plain);
		$display("held strobe,      words seen on the slow clock: %b", seen_hold);
		if (&seen_hold && !(&seen_plain))
			$display("RESULT: PASS - the narrow strobe loses words, the held one does not");
		else
			$display("RESULT: FAIL - plain %0d, held %0d of 16", $countones(seen_plain), $countones(seen_hold));
		$finish;
	end
endmodule
