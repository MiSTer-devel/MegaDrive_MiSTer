derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
#set_multicycle_path -from {emu|md_board|*} -to {emu|cartridge|*} -setup 2
#set_multicycle_path -from {emu|md_board|*} -to {emu|cartridge|*} -hold 1
