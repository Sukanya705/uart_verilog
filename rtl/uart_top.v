//------------------------------------------------------------------------------
// Module      : uart_top
// Description : Top-level UART: baud generator + transmitter + receiver.
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module uart_top #(
    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD_RATE  = 115_200,
    parameter integer DATA_BITS  = 8,
    parameter integer OVERSAMPLE = 16
) (
    input  wire                 clk,
    input  wire                 rst,        // synchronous, active high

    // Transmit interface
    input  wire                 tx_start,
    input  wire [DATA_BITS-1:0] tx_data,
    output wire                 tx_busy,
    output wire                 tx_done,
    output wire                 tx,

    // Receive interface
    input  wire                 rx,
    output wire [DATA_BITS-1:0] rx_data,
    output wire                 rx_valid,
    output wire                 frame_err
);

    wire tick;

    baud_gen #(
        .CLK_FREQ   (CLK_FREQ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_baud_gen (
        .clk  (clk),
        .rst  (rst),
        .tick (tick)
    );

    uart_tx #(
        .DATA_BITS  (DATA_BITS),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_uart_tx (
        .clk      (clk),
        .rst      (rst),
        .tick     (tick),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    uart_rx #(
        .DATA_BITS  (DATA_BITS),
        .OVERSAMPLE (OVERSAMPLE)
    ) u_uart_rx (
        .clk       (clk),
        .rst       (rst),
        .tick      (tick),
        .rx        (rx),
        .rx_data   (rx_data),
        .rx_valid  (rx_valid),
        .frame_err (frame_err)
    );

endmodule
