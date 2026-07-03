/*
 * SPI Master IP — Minimal, Single-Byte, Mode 0
 * Task 6: Real Peripheral IP Development
 *
 * Register Map (Base: 0x30000000):
 *   0x00 CTRL   — Bit0: EN, Bit1: START (auto-clear), Bits[15:8]: CLKDIV
 *   0x04 TXDATA — Bits[7:0]: byte to transmit
 *   0x08 RXDATA — Bits[7:0]: byte received (read-only)
 *   0x0C STATUS — Bit0: BUSY, Bit1: DONE (write-1-to-clear)
 */

`default_nettype none

module spi_master (
    // --- Memory Bus Interface ---
    input             clk,
    input             resetn,
    input             sel,
    input             we,
    input      [31:0] addr,
    input      [31:0] wdata,
    output reg [31:0] rdata,

    // --- SPI Pin Interface ---
    output            sclk,
    output            mosi,
    input             miso,
    output            cs_n
);

// ============================================================
// Register Select: addr[3:2] picks the target register
// ============================================================
wire [1:0] reg_sel = addr[3:2];

localparam REG_CTRL   = 2'b00;   // offset 0x00
localparam REG_TXDATA = 2'b01;   // offset 0x04
localparam REG_RXDATA = 2'b10;   // offset 0x08
localparam REG_STATUS = 2'b11;   // offset 0x0C

// ============================================================
// Software-visible registers
// ============================================================
reg        ctrl_en;
reg        ctrl_start;
reg [7:0]  ctrl_clkdiv;
reg [7:0]  txdata_reg;
reg [7:0]  rxdata_reg;
reg        status_busy;
reg        status_done;

// ============================================================
// Transfer state machine
// ============================================================
localparam S_IDLE     = 2'd0;
localparam S_TRANSFER = 2'd1;
localparam S_FINISH   = 2'd2;

reg [1:0]  state;
reg [2:0]  bit_cnt;    // counts bits 7 down to 0
reg [7:0]  clk_cnt;    // clock divider counter
reg        sclk_int;   // internal SPI clock
reg        cs_n_int;   // internal chip select
reg [7:0]  tx_shift;   // transmit shift register (MSB first)
reg [7:0]  rx_shift;   // receive shift register

// ============================================================
// Output Assignments
// ============================================================
assign sclk = sclk_int;
assign mosi = tx_shift[7];   // always drive MSB of shift register
assign cs_n = cs_n_int;

// ============================================================
// Write Logic + SPI State Machine (one always block)
// ============================================================
always @(posedge clk) begin
    if (!resetn) begin
        ctrl_en     <= 1'b0;
        ctrl_start  <= 1'b0;
        ctrl_clkdiv <= 8'd0;
        txdata_reg  <= 8'd0;
        rxdata_reg  <= 8'd0;
        status_busy <= 1'b0;
        status_done <= 1'b0;
        state       <= S_IDLE;
        sclk_int    <= 1'b0;
        cs_n_int    <= 1'b1;
        tx_shift    <= 8'd0;
        rx_shift    <= 8'd0;
        bit_cnt     <= 3'd0;
        clk_cnt     <= 8'd0;
    end else begin

        // ---- Software write path ----
        if (sel && we) begin
            case (reg_sel)
                REG_CTRL: begin
                    ctrl_en     <= wdata[0];
                    ctrl_start  <= wdata[1];
                    ctrl_clkdiv <= wdata[15:8];
                end
                REG_TXDATA: begin
                    txdata_reg  <= wdata[7:0];
                end
                REG_RXDATA: begin
                    // Read-only: writes ignored
                end
                REG_STATUS: begin
                    // Write-1-to-clear DONE (bit 1)
                    if (wdata[1]) status_done <= 1'b0;
                end
            endcase
        end

        // ---- SPI Transfer State Machine ----
        case (state)

            S_IDLE: begin
                sclk_int <= 1'b0;   // clock idles low
                cs_n_int <= 1'b1;   // chip deselected
                // Trigger when EN=1 and START=1
                if (ctrl_en && ctrl_start) begin
                    ctrl_start  <= 1'b0;        // auto-clear START
                    status_busy <= 1'b1;
                    status_done <= 1'b0;
                    cs_n_int    <= 1'b0;        // assert CS_N low
                    tx_shift    <= txdata_reg;  // load TX byte
                    rx_shift    <= 8'd0;
                    bit_cnt     <= 3'd7;        // 8 bits (7 down to 0)
                    clk_cnt     <= 8'd0;
                    state       <= S_TRANSFER;
                end
            end

            S_TRANSFER: begin
                if (clk_cnt == ctrl_clkdiv) begin
                    clk_cnt  <= 8'd0;
                    sclk_int <= ~sclk_int;   // toggle clock

                    if (!sclk_int) begin
                        // Was LOW → going HIGH = RISING EDGE
                        // Sample MISO (shift in, MSB received first)
                       rx_shift <= {rx_shift[6:0], miso};

                        if (bit_cnt == 3'd0) begin
    				rxdata_reg <= {rx_shift[6:0], miso};
    				state <= S_FINISH;
			end
			else begin
    				bit_cnt <= bit_cnt - 1;
			end

                    end else begin
                        // Was HIGH → going LOW = FALLING EDGE
                        // Shift MOSI to next bit
                        tx_shift <= {tx_shift[6:0], 1'b0};
                    end

                end else begin
                    clk_cnt <= clk_cnt + 1;
                end
            end

            S_FINISH: begin
                sclk_int    <= 1'b0;      // clock returns low
                cs_n_int    <= 1'b1;      // deassert CS_N
                status_busy <= 1'b0;
                status_done <= 1'b1;      // signal software
                state       <= S_IDLE;
            end

            default: state <= S_IDLE;

        endcase
    end
end

// ============================================================
// Read Logic — combinational
// ============================================================
always @(*) begin
    case (reg_sel)
        REG_CTRL:   rdata = {16'b0, ctrl_clkdiv, 6'b0, ctrl_start, ctrl_en};
        REG_TXDATA: rdata = {24'b0, txdata_reg};
        REG_RXDATA: rdata = {24'b0, rxdata_reg};
        REG_STATUS: rdata = {30'b0, status_done, status_busy};
        default:    rdata = 32'b0;
    endcase
end

endmodule
