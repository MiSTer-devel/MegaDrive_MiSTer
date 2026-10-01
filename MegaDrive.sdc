derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
#set_multicycle_path -from {emu|md_board|*} -to {emu|cartridge|*} -setup 2
#set_multicycle_path -from {emu|md_board|*} -to {emu|cartridge|*} -hold 1

# psg_iir registers only load on ce_flt, a 7 MHz enable on clk_sys
set_multicycle_path -from {*|psg_iir|*} -to {*|psg_iir|*intreg*} -setup 2
set_multicycle_path -from {*|psg_iir|*} -to {*|psg_iir|*intreg*} -hold 1
