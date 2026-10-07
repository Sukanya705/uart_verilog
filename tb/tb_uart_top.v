//------------------------------------------------------------------------------
// Testbench   : tb_uart_top
// Description : End-to-end loopback test. The tx pin of uart_top is wired to its
//               own rx pin, then ALL 256 byte values (0x00..0xFF) are sent and
//               checked on the receive side. Prints "PASS" or "FAIL".
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_uart_top;

    localparam integer CLK_FREQ   = 100_000_000;
    localparam integer BAUD_RATE  = 115_200;
    localparam integer OVERSAMPLE = 16;
    localparam integer CLK_PERIOD = 10;

    localparam integer DIVISOR   = (CLK_FREQ + (BAUD_RATE*OVERSAMPLE)/2)
                                   / (BAUD_RATE*OVERSAMPLE);
    localparam integer BIT_CLKS  = DIVISOR * OVERSAMPLE;
    localparam integer TIMEOUT   = 12 * BIT_CLKS;        // generous per-byte limit

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        tx_start = 1'b0;
    reg  [7:0] tx_data  = 8'h00;
    wire       tx, tx_busy, tx_done;
    wire [7:0] rx_data;
    wire       rx_valid, frame_err;

    integer errors = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Device under test, TX looped back to RX ---------------------------
    uart_top #(
        .CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE),
        .DATA_BITS(8), .OVERSAMPLE(OVERSAMPLE)
    ) dut (
        .clk(clk), .rst(rst),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx_busy(tx_busy), .tx_done(tx_done), .tx(tx),
        .rx(tx),                                         // loopback
        .rx_data(rx_data), .rx_valid(rx_valid), .frame_err(frame_err)
    );

    // ---- Monitor ------------------------------------------------------------
    reg       seen_valid = 1'b0;
    reg [7:0] last_data  = 8'h00;
    always @(posedge clk) begin
        if (rx_valid) begin
            seen_valid <= 1'b1;
            last_data  <= rx_data;
        end
        if (frame_err) begin
            errors = errors + 1;
            $display("[%0t] ERROR: unexpected frame_err", $time);
        end
    end

    // ---- Send one byte and wait for it to come back -------------------------
    task send_and_receive(input [7:0] data);
        integer wait_cnt;
        begin
            // wait until the transmitter is free
            @(posedge clk);
            while (tx_busy) @(posedge clk);

            seen_valid = 1'b0;
            tx_data  <= data;
            tx_start <= 1'b1;
            @(posedge clk);
            tx_start <= 1'b0;

            // wait for the receiver to report a byte
            wait_cnt = 0;
            while (!seen_valid && wait_cnt < TIMEOUT) begin
                @(posedge clk);
                wait_cnt = wait_cnt + 1;
            end

            if (!seen_valid) begin
                errors = errors + 1;
                $display("[%0t] ERROR: timeout waiting for 0x%02h", $time, data);
            end else if (last_data !== data) begin
                errors = errors + 1;
                $display("[%0t] ERROR: sent 0x%02h, received 0x%02h",
                         $time, data, last_data);
            end
        end
    endtask

    integer n;

    initial begin
`ifdef DUMP_VCD                      // enabled by the Makefile (-DDUMP_VCD)
        $dumpfile("sim/tb_uart_top.vcd");
        $dumpvars(0, tb_uart_top);
`endif

        repeat (10) @(posedge clk);
        rst <= 1'b0;
        repeat (20) @(posedge clk);

        $display("Loopback test: sending all 256 byte values ...");
        for (n = 0; n < 256; n = n + 1)
            send_and_receive(n[7:0]);

        $display("--------------------------------------------------");
        $display("tb_uart_top: 256 bytes sent, %0d errors", errors);
        if (errors == 0) $display("tb_uart_top: PASS");
        else             $display("tb_uart_top: FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

    // Watchdog (256 frames x ~87 us = ~22 ms, so 40 ms is plenty)
    initial begin
        #(40_000_000);
        $display("tb_uart_top: FAIL (timeout)");
        $finish;
    end

endmodule
