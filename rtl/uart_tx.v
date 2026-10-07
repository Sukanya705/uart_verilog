//------------------------------------------------------------------------------
// Module      : uart_tx
// Description : UART transmitter, 8N1 by default (1 start, DATA_BITS data
//               LSB first, 1 stop). Line idles high.
//
// Usage       : Put the byte on tx_data and pulse tx_start for one clock while
//               tx_busy is low. tx_busy stays high until the stop bit ends.
//               tx_done pulses for one clock when the frame is finished.
//------------------------------------------------------------------------------
`timescale 1ns / 1ps

module uart_tx #(
    parameter integer DATA_BITS  = 8,
    parameter integer OVERSAMPLE = 16
) (
    input  wire                 clk,
    input  wire                 rst,        // synchronous, active high
    input  wire                 tick,       // OVERSAMPLE x baud tick
    input  wire                 tx_start,   // 1-cycle pulse: begin sending
    input  wire [DATA_BITS-1:0] tx_data,    // byte to send
    output reg                  tx,         // serial output
    output wire                 tx_busy,    // high while a frame is in progress
    output reg                  tx_done     // 1-cycle pulse at end of frame
);

    localparam integer IDX_W = (DATA_BITS > 1) ? $clog2(DATA_BITS) : 1;
    localparam integer OS_W  = (OVERSAMPLE > 1) ? $clog2(OVERSAMPLE) : 1;

    // FSM states
    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]           state;
    reg [OS_W-1:0]      os_cnt;     // counts ticks within one bit
    reg [IDX_W-1:0]     bit_idx;    // which data bit is being sent
    reg [DATA_BITS-1:0] shreg;      // shift register holding the byte

    assign tx_busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            tx      <= 1'b1;
            tx_done <= 1'b0;
            os_cnt  <= {OS_W{1'b0}};
            bit_idx <= {IDX_W{1'b0}};
            shreg   <= {DATA_BITS{1'b0}};
        end else begin
            tx_done <= 1'b0;

            case (state)
                //----------------------------------------------------------
                S_IDLE: begin
                    tx      <= 1'b1;
                    os_cnt  <= {OS_W{1'b0}};
                    bit_idx <= {IDX_W{1'b0}};
                    if (tx_start) begin
                        shreg <= tx_data;
                        tx    <= 1'b0;          // start bit
                        state <= S_START;
                    end
                end
                //----------------------------------------------------------
                S_START: begin
                    if (tick) begin
                        if (os_cnt == OVERSAMPLE - 1) begin
                            os_cnt <= {OS_W{1'b0}};
                            tx     <= shreg[0]; // first data bit (LSB)
                            state  <= S_DATA;
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end
                //----------------------------------------------------------
                S_DATA: begin
                    if (tick) begin
                        if (os_cnt == OVERSAMPLE - 1) begin
                            os_cnt <= {OS_W{1'b0}};
                            shreg  <= shreg >> 1;
                            if (bit_idx == DATA_BITS - 1) begin
                                tx    <= 1'b1;  // stop bit
                                state <= S_STOP;
                            end else begin
                                tx      <= shreg[1];
                                bit_idx <= bit_idx + 1'b1;
                            end
                        end else begin
                            os_cnt <= os_cnt + 1'b1;
                        end
                    end
                end
                //----------------------------------------------------------
                S_STOP: begin
                    if (tick) begin
                        if (os_cnt == OVERSAMPLE - 1) begin
                            os_cnt  <= {OS_W{1'b0}};
                            tx_done <= 1'b1;
                            state   <= S_IDLE;
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
