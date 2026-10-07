//------------------------------------------------------------------------------
// Testbench   : tb_uart_rx
// Description : Self-checking testbench for baud_gen + uart_rx.
//               The testbench plays the role of a transmitter and drives the
//               rx pin with hand-built frames. Cases covered:
//                 1. Normal bytes (0x55, 0xAA, 0x00, 0xFF, 0xA3, 0x3C)
//                 2. Back-to-back frames with no idle gap
//                 3. Framing error (stop bit = 0) -> frame_err, no rx_valid
//                 4. Glitch shorter than half a bit -> ignored
//                 5. Sender baud rate off by about +/-3 % -> still received
//               Prints "PASS" or "FAIL" at the end.
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_uart_rx;

    localparam integer CLK_FREQ   = 100_000_000;
    localparam integer BAUD_RATE  = 115_200;
    localparam integer OVERSAMPLE = 16;
    localparam integer CLK_PERIOD = 10;

    localparam integer DIVISOR  = (CLK_FREQ + (BAUD_RATE*OVERSAMPLE)/2)
                                  / (BAUD_RATE*OVERSAMPLE);
    localparam integer BIT_CLKS = DIVISOR * OVERSAMPLE;

    reg        clk = 1'b0;
    reg        rst = 1'b1;
    reg        rx  = 1'b1;               // line idles high
    wire       tick;
    wire [7:0] rx_data;
    wire       rx_valid, frame_err;

    integer errors = 0;
    integer tests  = 0;

    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Device under test --------------------------------------------------
    baud_gen #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .OVERSAMPLE(OVERSAMPLE))
        u_baud (.clk(clk), .rst(rst), .tick(tick));

    uart_rx #(.DATA_BITS(8), .OVERSAMPLE(OVERSAMPLE))
        dut (.clk(clk), .rst(rst), .tick(tick), .rx(rx),
             .rx_data(rx_data), .rx_valid(rx_valid), .frame_err(frame_err));

    // ---- Monitor: remembers what the receiver reported ----------------------
    reg       seen_valid = 1'b0;
    reg       seen_ferr  = 1'b0;
    reg [7:0] last_data  = 8'h00;
    integer   valid_count = 0;

    always @(posedge clk) begin
        if (rx_valid) begin
            seen_valid  <= 1'b1;
            last_data   <= rx_data;
            valid_count <= valid_count + 1;
        end
        if (frame_err) seen_ferr <= 1'b1;
    end

    task clear_flags;
        begin
            @(posedge clk);
            seen_valid = 1'b0;
            seen_ferr  = 1'b0;
        end
    endtask

    // ---- Drive one serial frame on rx --------------------------------------
    // bit_clks lets us stretch/shrink the bit time to test baud mismatch.
    task drive_frame(input [7:0] data, input stop_level, input integer bit_clks);
        integer i;
        begin
            rx = 1'b0;                                   // start bit
            repeat (bit_clks) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin          // data, LSB first
                rx = data[i];
                repeat (bit_clks) @(posedge clk);
            end
            rx = stop_level;                             // stop bit
            repeat (bit_clks) @(posedge clk);
            rx = 1'b1;                                   // back to idle
        end
    endtask

    // ---- Check helpers ------------------------------------------------------
    task expect_byte(input [7:0] data, input integer bit_clks);
        begin
            tests = tests + 1;
            clear_flags;
            drive_frame(data, 1'b1, bit_clks);
            repeat (BIT_CLKS) @(posedge clk);            // allow time to finish
            if (!seen_valid) begin
                errors = errors + 1;
                $display("[%0t] ERROR: rx_valid never pulsed for 0x%02h", $time, data);
            end else if (last_data !== data) begin
                errors = errors + 1;
                $display("[%0t] ERROR: sent 0x%02h but received 0x%02h",
                         $time, data, last_data);
            end else if (seen_ferr) begin
                errors = errors + 1;
                $display("[%0t] ERROR: unexpected frame_err for 0x%02h", $time, data);
            end else begin
                $display("[%0t] OK   : received 0x%02h", $time, last_data);
            end
        end
    endtask

    integer count_before;

    // ---- Stimulus -----------------------------------------------------------
    initial begin
`ifdef DUMP_VCD                      // enabled by the Makefile (-DDUMP_VCD)
        $dumpfile("sim/tb_uart_rx.vcd");
        $dumpvars(0, tb_uart_rx);
`endif

        repeat (10) @(posedge clk);
        rst <= 1'b0;
        repeat (BIT_CLKS) @(posedge clk);

        // 1. Normal bytes
        $display("--- Case 1: normal bytes ---");
        expect_byte(8'h55, BIT_CLKS);
        expect_byte(8'hAA, BIT_CLKS);
        expect_byte(8'h00, BIT_CLKS);
        expect_byte(8'hFF, BIT_CLKS);
        expect_byte(8'hA3, BIT_CLKS);
        expect_byte(8'h3C, BIT_CLKS);

        // 2. Back-to-back frames (no idle time between them)
        $display("--- Case 2: back-to-back frames ---");
        tests = tests + 1;
        clear_flags;
        count_before = valid_count;
        drive_frame(8'hC3, 1'b1, BIT_CLKS);
        drive_frame(8'h5A, 1'b1, BIT_CLKS);
        drive_frame(8'hE7, 1'b1, BIT_CLKS);
        repeat (BIT_CLKS) @(posedge clk);
        if ((valid_count - count_before) !== 3 || last_data !== 8'hE7) begin
            errors = errors + 1;
            $display("[%0t] ERROR: back-to-back frames: got %0d bytes, last=0x%02h",
                     $time, valid_count - count_before, last_data);
        end else begin
            $display("[%0t] OK   : 3 back-to-back frames received", $time);
        end

        // 3. Framing error: stop bit forced low
        $display("--- Case 3: framing error ---");
        tests = tests + 1;
        clear_flags;
        drive_frame(8'h96, 1'b0, BIT_CLKS);
        repeat (2*BIT_CLKS) @(posedge clk);
        if (!seen_ferr || seen_valid) begin
            errors = errors + 1;
            $display("[%0t] ERROR: framing error not handled (ferr=%b valid=%b)",
                     $time, seen_ferr, seen_valid);
        end else begin
            $display("[%0t] OK   : frame_err raised, byte discarded", $time);
        end

        // 4. Glitch shorter than half a bit must be ignored
        $display("--- Case 4: glitch rejection ---");
        tests = tests + 1;
        // Make sure the line is idle-high and the receiver is back in IDLE
        rx = 1'b1;
        repeat (2*BIT_CLKS) @(posedge clk);
        clear_flags;
        rx = 1'b0;
        repeat (BIT_CLKS/4) @(posedge clk);              // quarter-bit glitch
        rx = 1'b1;
        repeat (3*BIT_CLKS) @(posedge clk);
        if (seen_valid || seen_ferr) begin
            errors = errors + 1;
            $display("[%0t] ERROR: glitch was mistaken for a frame", $time);
        end else begin
            $display("[%0t] OK   : glitch ignored", $time);
        end

        // 5. Baud mismatch tolerance (+/- 3 %)
        $display("--- Case 5: baud-rate mismatch tolerance ---");
        expect_byte(8'hB6, (BIT_CLKS * 103) / 100);      // sender 3 % slow
        expect_byte(8'h4D, (BIT_CLKS *  97) / 100);      // sender 3 % fast

        $display("--------------------------------------------------");
        $display("tb_uart_rx : %0d tests run, %0d errors", tests, errors);
        if (errors == 0) $display("tb_uart_rx : PASS");
        else             $display("tb_uart_rx : FAIL");
        $display("--------------------------------------------------");
        $finish;
    end

    // Watchdog
    initial begin
        #(30_000_000);
        $display("tb_uart_rx : FAIL (timeout)");
        $finish;
    end

endmodule
