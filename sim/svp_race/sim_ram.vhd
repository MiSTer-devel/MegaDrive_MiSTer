-- Behavioural models of the spram and mlab entities (rtl/bram.vhd, rtl/mlab.vhd) for simulation without the
-- altera_mf library.  Same entity names, generics and ports.
--   spram: address registered, output unregistered, read-during-write returns the new data.
--   mlab:  write registered, read address and output unregistered.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spram is
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8;
		mem_init_file : string := " ";
		mem_name      : string := "MEM"
	);
	port (
		clock   : in  std_logic;
		address : in  std_logic_vector(addr_width-1 downto 0);
		data    : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		enable  : in  std_logic := '1';
		wren    : in  std_logic := '0';
		q       : out std_logic_vector(data_width-1 downto 0);
		cs      : in  std_logic := '1'
	);
end entity;

architecture sim of spram is
	type mem_t is array (0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
	signal mem : mem_t := (others => (others => '0'));
	signal ra  : integer range 0 to 2**addr_width-1 := 0;
begin
	process (clock) begin
		if rising_edge(clock) then
			if enable = '1' then
				if wren = '1' and cs = '1' then
					mem(to_integer(unsigned(address))) <= data;
				end if;
				ra <= to_integer(unsigned(address));
			end if;
		end if;
	end process;
	q <= mem(ra) when cs = '1' else (others => '1');
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mlab is
	generic (
		addr_width    : integer := 8;
		data_width    : integer := 8
	);
	port (
		clock     : in  std_logic;
		rdaddress : in  std_logic_vector(addr_width-1 downto 0);
		wraddress : in  std_logic_vector(addr_width-1 downto 0);
		data      : in  std_logic_vector(data_width-1 downto 0) := (others => '0');
		wren      : in  std_logic := '0';
		q         : out std_logic_vector(data_width-1 downto 0);
		cs        : in  std_logic := '1'
	);
end entity;

architecture sim of mlab is
	type mem_t is array (0 to 2**addr_width-1) of std_logic_vector(data_width-1 downto 0);
	signal mem : mem_t := (others => (others => '0'));
begin
	process (clock) begin
		if rising_edge(clock) then
			if wren = '1' and cs = '1' then
				mem(to_integer(unsigned(wraddress))) <= data;
			end if;
		end if;
	end process;
	q <= mem(to_integer(unsigned(rdaddress))) when cs = '1' else (others => '1');
end architecture;
