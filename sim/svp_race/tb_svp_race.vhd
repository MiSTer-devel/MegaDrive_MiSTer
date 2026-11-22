-- Directed test of the SVP status handshake: the SSP's write of XST sets SA (bit 0 of 0xA15004) and the 68000's
-- read of 0xA15004 clears it.  The SSP runs a four-instruction program from a ROM held in this file:
--   0400  0840 0000   ldi ST, 0x0000
--   0402  0830 1234   ldi A, 0x1234
--   0404  00B3        ld EXT3, A          (the write of XST)
--   0405  4C00 0405   bra always, 0x0405
-- ROM_ACK follows ROM_REQ two clocks later; CE toggles every clock as system.sv drives it.  For each start offset
-- d = 0 .. 23 clocks the test resets the SVP, waits d clocks, then reads 0xA15004 back to back (BUS_SEL held until
-- DTACK_N is low, then released for one clock) for 3,000 clocks.  An offset is lost when no read returns SA = 1:
-- the SSP's write fell on the clock of a read and was discarded.  Every offset must see SA.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_svp_race is
end entity;

architecture sim of tb_svp_race is
	signal clk     : std_logic := '0';
	signal ce      : std_logic := '0';
	signal rst_n   : std_logic := '0';
	signal bus_a   : std_logic_vector(23 downto 1) := (others => '0');
	signal bus_do  : std_logic_vector(15 downto 0);
	signal bus_sel : std_logic := '0';
	signal dtack_n : std_logic;
	signal rom_a   : std_logic_vector(20 downto 1);
	signal rom_di  : std_logic_vector(15 downto 0) := (others => '0');
	signal rom_req : std_logic;
	signal rom_ack : std_logic := '0';
	signal rom_dly : integer range 0 to 2 := 0;
	signal done    : boolean := false;

	type prog_t is array (0 to 7) of std_logic_vector(15 downto 0);
	constant PROG : prog_t := (x"0840", x"0000", x"0830", x"1234", x"00B3", x"4C00", x"0405", x"0000");
begin
	clk <= not clk after 9.312 ns when not done;      -- 53.69 MHz

	process (clk) begin
		if rising_edge(clk) then
			ce <= rst_n and not ce;
		end if;
	end process;

	dut : entity work.SVP
	port map(
		CLK => clk, CE => ce, RST_N => rst_n, ENABLE => '1',
		BUS_A => bus_a, BUS_DO => bus_do, BUS_DI => (others => '0'), BUS_SEL => bus_sel, BUS_RNW => '1',
		BUS_DTACK_N => dtack_n, DMA_ACTIVE => '0',
		ROM_A => rom_a, ROM_DI => rom_di, ROM_REQ => rom_req, ROM_ACK => rom_ack,
		DRAM_A => open, DRAM_DI => (others => '0'), DRAM_DO => open, DRAM_WE => open
	);

	-- program ROM, word addresses 0x0400-0x0407
	process (clk)
		variable wa : unsigned(19 downto 0);
	begin
		if rising_edge(clk) then
			if rom_req /= rom_ack and rom_dly = 0 then
				rom_dly <= 2;
			elsif rom_dly = 1 then
				wa := unsigned(rom_a);
				if wa >= x"00400" and wa < x"00408" then
					rom_di <= PROG(to_integer(wa(2 downto 0)));
				else
					rom_di <= (others => '0');
				end if;
				rom_ack <= rom_req;
				rom_dly <= 0;
			elsif rom_dly /= 0 then
				rom_dly <= rom_dly - 1;
			end if;
		end if;
	end process;

	process
		variable k, lost, first : integer;
		variable seen : boolean;
	begin
		lost := 0; first := -1;
		for d in 0 to 23 loop
			rst_n <= '0'; bus_sel <= '0';
			for i in 1 to 8 loop wait until rising_edge(clk); end loop;
			rst_n <= '1';
			for i in 1 to d loop wait until rising_edge(clk); end loop;
			seen := false; k := 0;
			while k < 3000 loop
				bus_a <= std_logic_vector(to_unsigned(16#50A802#, 23));    -- 0xA15004
				bus_sel <= '1';
				wait until rising_edge(clk); k := k + 1;
				while dtack_n = '1' loop wait until rising_edge(clk); k := k + 1; end loop;
				if bus_do(0) = '1' then seen := true; end if;
				bus_sel <= '0';
				wait until rising_edge(clk); k := k + 1;
			end loop;
			if not seen then
				lost := lost + 1;
				if first < 0 then first := d; end if;
			end if;
		end loop;
		report "SVP status race: offsets 24, lost " & integer'image(lost) & ", first lost offset " & integer'image(first);
		assert lost = 0 report "SVP status race: SA set by the SSP's XST write was discarded" severity failure;
		report "SVP status race: PASS";
		done <= true;
		wait;
	end process;
end architecture;
