//------------------------------------------------------------------------------
// Testbench   : tb_uart_tx
// Description : Self-checking testbench for baud_gen + uart_tx.
//               An independent monitor samples the serial line and checks:
//                 - line idles high
//                 - start bit = 0
//                 - 8 data bits arrive LSB first with the correct value
//                 - stop bit = 1
//                 - tx_busy is high during the frame and low afterwards
//               Prints "PASS" or "FAIL" at the end.
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_uart_tx;

    localparam integer CLK_FREQ   = 100_000_000;
    localparam integer BAUD_RATE  = 115_200;
    localparam integer OVERSAMPLE = 16;
    localparam integer CLK_PERIOD = 10;                       // 100 MHz

    // Clock cycles per UART bit, exactly as produced by baud_gen
    localparam integer DIVISOR  = (CLK_FREQ + (BAUD_RATE*OVERSAMPLE)/2)
                                  / (BAUD_RATE*OVERSAMPLE);
    localparam integer BIT_CLKS = DIVISOR * OVERSAMPLE;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        tx_start = 1'b0;
    reg  [7:0] tx_data  = 8'h00;
    wire       tick, tx, tx_busy, tx_done;

    integer errors = 0;
    integer tests  = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Device under test --------------------------------------------------
    baud_gen #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .OVERSAMPLE(OVERSAMPLE))
        u_baud (.clk(clk), .rst(rst), .tick(tick));

    uart_tx #(.DATA_BITS(8), .OVERSAMPLE(OVERSAMPLE))
        dut (.clk(clk), .rst(rst), .tick(tick), .tx_start(tx_start),
             .tx_data(tx_data), .tx(tx), .tx_busy(tx_busy), .tx_done(tx_done));

    // ---- Send one byte and verify the waveform on the tx pin ----------------
    task send_and_check(input [7:0] data);
        reg [7:0] got;
        integer   i;
        begin
            tests = tests + 1;

            @(posedge clk);
            tx_data  <= data;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            // Start bit: wait for falling edge, then check at mid-bit
            @(negedge tx);
            repeat (BIT_CLKS/2) @(posedge clk);
            if (tx !== 1'b0) begin
                errors = errors + 1;
                $display("[%0t] ERROR: start bit not low (data=0x%02h)", $time, data);
            end
            if (tx_busy !== 1'b1) begin
                errors = errors + 1;
                $display("[%0t] ERROR: tx_busy not high during frame", $time);
            end

            // Data bits, LSB first, sampled mid-bit
            for (i = 0; i < 8; i = i + 1) begin
                repeat (BIT_CLKS) @(posedge clk);
                got[i] = tx;
            end

            // Stop bit
            repeat (BIT_CLKS) @(posedge clk);
            if (tx !== 1'b1) begin
                errors = errors + 1;
                $display("[%0t] ERROR: stop bit not high (data=0x%02h)", $time, data);
            end

            if (got !== data) begin
                errors = errors + 1;
                $display("[%0t] ERROR: sent 0x%02h but line carried 0x%02h",
                         $time, data, got);
            end else begin
                $display("[%0t] OK   : 0x%02h transmitted correctly", $time, data);
            end

            // Frame must finish and tx_busy must drop
            repeat (BIT_CLKS) @(posedge clk);
            if (tx_busy !== 1'b0) begin
                errors = errors + 1;
                $display("[%0t] ERROR: tx_busy stuck high after frame", $time);
            end
            if (tx !== 1'b1) begin
                errors = errors + 1;
                $display("[%0t] ERROR: line not idle-high after frame", $time);
            end
        end
    endtask

    // ---- Stimulus -----------------------------------------------------------
    initial begin
`ifdef DUMP_VCD                      // enabled by the Makefile (-DDUMP_VCD)
        $dumpfile("sim/tb_uart_tx.vcd");
        $dumpvars(0, tb_uart_tx);
`endif

        repeat (10) @(posedge clk);
        rst <= 1'b0;
        repeat (10) @(posedge clk);

        if (tx !== 1'b1) begin
            errors = errors + 1;
            $display("ERROR: line not idle-high after reset");
        end

        send_and_check(8'h55);   // 01010101 alternating
        send_and_check(8'hAA);   // 10101010 alternating
        send_and_check(8'h00);   // all zeros
        send_and_check(8'hFF);   // all ones
        send_and_check(8'hA3);   // arbitrary
        send_and_check(8'h3C);   // arbitrary
        send_and_check(8'h01);   // only LSB set (checks bit order)
        send_and_check(8'h80);   // only MSB set (checks bit order)

        $display("--------------------------------------------------");
        $display("tb_uart_tx : %0d frames tested, %0d errors", tests, errors);
        if (errors == 0) $display("tb_uart_tx : PASS");
        else             $display("tb_uart_tx : FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

    // Watchdog: never hang the simulator
    initial begin
        #(20_000_000);
        $display("tb_uart_tx : FAIL (timeout)");
        $finish;
    end

endmodule
