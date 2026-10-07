# Optional: run the testbenches from a terminal with Icarus Verilog.
# (Vivado users can ignore this file and simulate inside Vivado.)
#
#   make        -> run all testbenches (fails if any testbench reports FAIL)
#   make tx     -> run only the transmitter testbench (rx, top also work)
#   make clean  -> remove generated files

RTL = rtl/baud_gen.v rtl/uart_tx.v rtl/uart_rx.v rtl/uart_top.v

.PHONY: all tx rx top clean

all: tx rx top

tx rx top:
	@mkdir -p sim
	iverilog -g2005 -Wall -DDUMP_VCD -o sim/tb_uart_$@.vvp $(RTL) tb/tb_uart_$@.v
	vvp sim/tb_uart_$@.vvp | grep -v "^VCD" | tee sim/$@.log
	@! grep -q "FAIL" sim/$@.log

clean:
	rm -rf sim
