//------------------------------------------------------------------------------
// Module      : baud_gen
// Description : Generates a one-clock-wide tick at OVERSAMPLE x BAUD_RATE.
//               The TX and RX modules count these ticks to time each bit.
//
// Parameters  : CLK_FREQ   - system clock frequency in Hz
//               BAUD_RATE  - desired baud rate
//               OVERSAMPLE - ticks per bit (16 is the usual UART choice)
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module baud_gen #(
    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer OVERSAMPLE = 16
) (
    input  wire clk,
    input  wire rst,        // synchronous, active high
    output reg  tick        // 1-cycle pulse at OVERSAMPLE x BAUD_RATE
);

    // Rounded divisor (reduces baud-rate error versus plain truncation)
    localparam integer DIVISOR = (CLK_FREQ + (BAUD_RATE * OVERSAMPLE) / 2)
                                 / (BAUD_RATE * OVERSAMPLE);
    localparam integer CNT_W   = (DIVISOR > 1) ? $clog2(DIVISOR) : 1;

    reg [CNT_W-1:0] cnt;

    always @(posedge clk) begin
        if (rst) begin
            cnt  <= {CNT_W{1'b0}};
            tick <= 1'b0;
        end else if (cnt == DIVISOR - 1) begin
            cnt  <= {CNT_W{1'b0}};
            tick <= 1'b1;
        end else begin
            cnt  <= cnt + 1'b1;
            tick <= 1'b0;
        end
    end

endmodule
