//------------------------------------------------------------------------------
// Module      : uart_rx
// Description : UART receiver, 8N1 by default, with OVERSAMPLE x oversampling.
//
//   * 2-flop synchronizer on the asynchronous rx input (avoids metastability)
//   * Start bit is re-checked at its midpoint, so short glitches are ignored
//   * Every following bit is sampled in the middle of the bit period
//   * Framing error flagged if the stop bit is not high
//   * After a framing error (or reset) the receiver only re-arms once the line
//     has been seen high again, so a stuck-low line is not mistaken for a new
//     start bit
//
// Outputs     : rx_valid  - 1-cycle pulse, rx_data holds a good byte
//               frame_err - 1-cycle pulse, stop bit was low (byte discarded)
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module uart_rx #(
    parameter integer DATA_BITS  = 8,
    parameter integer OVERSAMPLE = 16
) (
    input  wire                 clk,
    input  wire                 rst,        // synchronous, active high
    input  wire                 tick,       // OVERSAMPLE x baud tick
    input  wire                 rx,         // serial input (asynchronous)
    output reg  [DATA_BITS-1:0] rx_data,
    output reg                  rx_valid,
    output reg                  frame_err
);

    localparam integer IDX_W = (DATA_BITS > 1) ? $clog2(DATA_BITS) : 1;
    localparam integer OS_W  = (OVERSAMPLE > 1) ? $clog2(OVERSAMPLE) : 1;

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    // ---- Input synchronizer -------------------------------------------------
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    // ---- Receive FSM --------------------------------------------------------
    reg [1:0]           state;
    reg [OS_W-1:0]      os_cnt;
    reg [IDX_W-1:0]     bit_idx;
    reg [DATA_BITS-1:0] shreg;
    reg                 armed;      // high once the line has been seen idle-high

    always @(posedge clk) begin
        if (rst) begin
            armed     <= 1'b0;
            state     <= S_IDLE;
            os_cnt    <= {OS_W{1'b0}};
            bit_idx   <= {IDX_W{1'b0}};
            shreg     <= {DATA_BITS{1'b0}};
            rx_data   <= {DATA_BITS{1'b0}};
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            rx_valid  <= 1'b0;
            frame_err <= 1'b0;

            case (state)
                //----------------------------------------------------------
                S_IDLE: begin
                    os_cnt  <= {OS_W{1'b0}};
                    bit_idx <= {IDX_W{1'b0}};
                    if (rx_sync == 1'b1)
                        armed <= 1'b1;              // line is idle, ready
                    else if (armed) begin           // falling edge: start bit?
                        armed <= 1'b0;
                        state <= S_START;
                    end
                end
                //----------------------------------------------------------
                S_START: begin                      // wait to middle of start bit
                    if (tick) begin
                        if (os_cnt == (OVERSAMPLE/2) - 1) begin
                            os_cnt <= {OS_W{1'b0}};
                            if (rx_sync == 1'b0)
                                state <= S_DATA;    // valid start bit
                            else
                                state <= S_IDLE;    // glitch, ignore
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end
                //----------------------------------------------------------
                S_DATA: begin                       // sample mid-bit, LSB first
                    if (tick) begin
                        if (os_cnt == OVERSAMPLE - 1) begin
                            os_cnt <= {OS_W{1'b0}};
                            shreg  <= {rx_sync, shreg[DATA_BITS-1:1]};
                            if (bit_idx == DATA_BITS - 1)
                                state <= S_STOP;
                            else
                                bit_idx <= bit_idx + 1'b1;
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end
                //----------------------------------------------------------
                S_STOP: begin                       // check stop bit mid-bit
                    if (tick) begin
                        if (os_cnt == OVERSAMPLE - 1) begin
                            os_cnt    <= {OS_W{1'b0}};
                            rx_data   <= shreg;
                            rx_valid  <= rx_sync;   // stop bit must be 1
                            frame_err <= ~rx_sync;
                            state     <= S_IDLE;
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end
                //----------------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
