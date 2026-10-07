# UART Transmitter & Receiver in Verilog

![Simulation](https://github.com/Sukanya705/uart_verilog/actions/workflows/sim.yml/badge.svg)
![Language](https://img.shields.io/badge/language-Verilog-blue)
![Tool](https://img.shields.io/badge/tool-Xilinx%20Vivado-red)
![License](https://img.shields.io/badge/license-MIT-green)

A parameterizable **UART (Universal Asynchronous Receiver/Transmitter)** written in synthesizable Verilog, with a self-checking testbench for each part of the design. Simulated in **Xilinx Vivado**.

<!-- Add your Vivado waveform screenshot here, e.g.: ![Waveform](docs/waveform.png) -->

---

## Highlights

- **8N1 framing** (1 start bit, 8 data bits LSB-first, 1 stop bit), configurable data width
- **16x oversampling receiver** that samples every bit at its midpoint
- **Metastability protection:** 2-flop synchronizer on the asynchronous `rx` input
- **Glitch rejection:** the start bit is re-checked at its midpoint, so short noise pulses are ignored
- **Framing-error detection** with automatic recovery
- **Parameterized:** clock frequency, baud rate, data width and oversampling are all `parameter`s
- **3 self-checking testbenches** that print `PASS` / `FAIL`, including an exhaustive 256-byte loopback test
- Verified to tolerate **±3 % baud-rate mismatch**
- Continuous integration: GitHub Actions runs all testbenches on every push

## UART Frame Format

```
 idle  start  D0  D1  D2  D3  D4  D5  D6  D7  stop  idle
  1      0    LSB                         MSB   1      1
```

At 115200 baud one bit lasts ≈ 8.68 µs, so one 10-bit frame lasts ≈ 86.8 µs.

## Architecture

```
                         +-------------------- uart_top ---------------------+
                         |                                                   |
   clk ----------------> |   +-----------+  tick (16 x baud)                 |
   rst ----------------> |   | baud_gen  |-----+-----------------+           |
                         |   +-----------+     |                 |           |
                         |                     v                 v           |
   tx_start, tx_data --> |              +-----------+      +-----------+      |
   tx_busy, tx_done  <-- |              |  uart_tx  |      |  uart_rx  |      |
                         |              +-----+-----+      +-----+-----+      |
                         |                    |                  ^           |
                         +--------------------|------------------|-----------+
                                              v                  |
                                             tx                  rx
```

| Module     | File             | Purpose |
|------------|------------------|---------|
| `baud_gen` | `rtl/baud_gen.v` | Divides the system clock to produce a tick at 16 × baud rate |
| `uart_tx`  | `rtl/uart_tx.v`  | Serializes a byte: IDLE → START → DATA → STOP |
| `uart_rx`  | `rtl/uart_rx.v`  | Synchronizes input, finds start bit, samples bits mid-bit, checks stop bit |
| `uart_top` | `rtl/uart_top.v` | Connects the three modules |

### Receiver operation

```
IDLE --(falling edge on rx)--> START --(8 ticks: still low?)--> DATA --(8 bits, 16 ticks each)--> STOP
  ^                               |  no: glitch, go back                                          |
  +---------------------------------------------------------------------------------------------+
```

The receiver sees a falling edge, waits half a bit, confirms the line is still low (otherwise it was noise), and then samples each following bit every 16 ticks, which lands in the middle of each bit. This is what makes the design tolerant of small baud-rate differences between the two ends.

## Repository Structure

```
.
├── rtl/
│   ├── baud_gen.v          Baud-rate tick generator
│   ├── uart_tx.v           Transmitter
│   ├── uart_rx.v           Receiver
│   └── uart_top.v          Top-level wrapper
├── tb/
│   ├── tb_uart_tx.v        Transmitter testbench
│   ├── tb_uart_rx.v        Receiver testbench
│   └── tb_uart_top.v       Full loopback testbench (all 256 byte values)
├── .github/workflows/sim.yml   CI: runs the testbenches on every push
├── Makefile                Optional: run simulations from a terminal
├── LICENSE
└── README.md
```

## Parameters

| Parameter    | Default       | Description                        |
|--------------|---------------|------------------------------------|
| `CLK_FREQ`   | `100_000_000` | System clock frequency in Hz       |
| `BAUD_RATE`  | `115_200`     | Baud rate                          |
| `DATA_BITS`  | `8`           | Number of data bits                |
| `OVERSAMPLE` | `16`          | Ticks per bit                      |

With the defaults the divisor is `100 MHz / (115200 × 16) ≈ 54`, giving an actual baud rate of 115 741 (**+0.47 % error**, well inside what a UART can tolerate).

## Interface (`uart_top`)

| Port        | Dir | Width | Description |
|-------------|-----|-------|-------------|
| `clk`       | in  | 1     | System clock |
| `rst`       | in  | 1     | Synchronous, active-high reset |
| `tx_start`  | in  | 1     | Pulse for one clock to send `tx_data` (only when `tx_busy` is low) |
| `tx_data`   | in  | 8     | Byte to transmit |
| `tx_busy`   | out | 1     | High while a frame is being sent |
| `tx_done`   | out | 1     | One-clock pulse when the frame has finished |
| `tx`        | out | 1     | Serial output (idles high) |
| `rx`        | in  | 1     | Serial input |
| `rx_data`   | out | 8     | Last received byte |
| `rx_valid`  | out | 1     | One-clock pulse: `rx_data` holds a new, valid byte |
| `frame_err` | out | 1     | One-clock pulse: stop bit was not high, byte discarded |

---

## Simulating in Vivado

1. **File → Project → New**, choose **RTL Project**, and pick any FPGA part (it is only needed for synthesis; behavioral simulation does not depend on it).
2. **Add Sources:** all files in `rtl/`.
3. **Add Simulation Sources:** all files in `tb/`.
4. In **Sources → Simulation Sources**, right-click the testbench you want and choose **Set as Top**.
5. **Run Simulation → Run Behavioral Simulation**, then type `run all` in the Tcl console.

| Testbench      | What it checks | Sim length |
|----------------|----------------|-----------|
| `tb_uart_tx`   | Idle-high line, start bit, 8 data bits LSB-first, stop bit, `tx_busy` behaviour for 8 patterns (`55`, `AA`, `00`, `FF`, `A3`, `3C`, `01`, `80`) | ≈ 0.73 ms |
| `tb_uart_rx`   | Normal bytes, back-to-back frames, framing error, glitch rejection, ±3 % baud mismatch | ≈ 1.2 ms |
| `tb_uart_top`  | TX looped back into RX, all 256 byte values `0x00`–`0xFF` | ≈ 22 ms |

Each testbench prints `PASS` or `FAIL` in the Tcl console. Expected output:

```
tb_uart_tx : 8 frames tested, 0 errors
tb_uart_tx : PASS
tb_uart_rx : 11 tests run, 0 errors
tb_uart_rx : PASS
tb_uart_top: 256 bytes sent, 0 errors
tb_uart_top: PASS
```

**Without Vivado** (e.g. on Linux or in CI), the same testbenches run with [Icarus Verilog](https://steveicarus.github.io/iverilog/):

```bash
make          # runs all three testbenches
```

## Verification Summary

| Test | Result |
|------|--------|
| TX waveform for 8 data patterns | PASS |
| RX: 6 normal bytes | PASS |
| RX: 3 back-to-back frames | PASS |
| RX: framing error flagged, byte discarded | PASS |
| RX: glitch (¼ bit wide) ignored | PASS |
| RX: sender 3 % slow and 3 % fast | PASS |
| Loopback: all 256 byte values | PASS |

### A bug the testbench caught

While writing `tb_uart_rx`, the baud-mismatch test failed even though each case worked in isolation. Tracing the receiver showed that after a **framing error** the stop bit was still low when the FSM returned to `IDLE`, so it mistook the tail of the stop bit for a new start bit and swallowed part of the next frame. The fix was an `armed` flag: the receiver now only accepts a start bit after it has seen the line high. The framing-error and glitch test cases guard against this regression.

## Design Decisions

- **16x oversampling** instead of counting full bit periods: gives mid-bit sampling and tolerance to clock mismatch.
- **One shared tick** from `baud_gen` for both TX and RX: a single counter and no derived clocks. Everything runs on one clock with clock-enables, which is the recommended FPGA/ASIC practice.
- **Synchronous, active-high reset** throughout.
- **Rounded baud divisor** to minimise baud-rate error.
- **Self-checking testbenches** (no manual waveform inspection needed) so regressions are caught automatically in CI.

## Possible Extensions

- [ ] Parity bit (even/odd) and 2 stop bits
- [ ] TX/RX FIFOs
- [ ] Overrun error flag
- [ ] AXI4-Lite wrapper
- [ ] Runtime-configurable baud rate

## License

Released under the [MIT License](LICENSE).

## Author

**Sukanya**
[LinkedIn]https://www.linkedin.com/in/sukanya-shinde-81339136b/ · [GitHub](https://github.com/sukanya705)
