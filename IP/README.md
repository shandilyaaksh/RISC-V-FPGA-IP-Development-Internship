# SPI Master IP for VSDSquadron RV32I SoC

**Memory-mapped SPI Master controller. Mode-0.**

---

## What is this?

`spi_master` is a small, verified, memory-mapped SPI Master peripheral for RV32I-based SoCs. It performs standard SPI Mode-0, 8-bit, full-duplex byte transfers, controlled entirely through four 32-bit registers at a fixed base address — no bit-banging, no external SPI library.

| | |
|---|---|
| **Base Address** | `0x30000000` |
| **SPI Mode** | Mode-0 (CPOL=0, CPHA=0) |
| **Transfer Size** | 8 bits, full-duplex |
| **Bus Interface** | Memory-mapped, single-cycle |
| **Verified On** | RTL simulation (Icarus Verilog + GTKWave) and physical hardware (VSDSquadron FM, iCE40UP5K) |
| **License** | MIT (see `LICENSE`) |

---

## Quick Start

**1. Add the RTL to your project**

```
cp ip/spi_master/rtl/spi_master.v <your_project>/rtl/
```

**2. Instantiate it in your top-level SoC**

```verilog
wire spi_sel = (mem_addr[31:4] == 28'h3000000);
wire [31:0] spi_rdata;
wire spi_sclk, spi_mosi, spi_cs_n;
wire spi_miso = spi_mosi; // loopback for bench testing; replace with real pin for production

spi_master spi_inst (
    .clk(clk), .resetn(resetn),
    .sel(spi_sel), .we(mem_wstrb), .addr(mem_addr),
    .wdata(mem_wdata), .rdata(spi_rdata),
    .sclk(spi_sclk), .mosi(spi_mosi), .miso(spi_miso), .cs_n(spi_cs_n)
);

// Add spi_sel ? spi_rdata : into your existing mem_rdata mux
```

Full wiring instructions, address-decode rules, and pin-constraint guidance: **[`Integration_Guide.md`](SPI_Master/docs/IP_User_Guide.md)**

**3. Drive it from firmware**

```c
#define SPI_BASE   0x30000000u
#define SPI_CTRL   (*(volatile uint32_t*)(SPI_BASE + 0x00))
#define SPI_TXDATA (*(volatile uint32_t*)(SPI_BASE + 0x04))
#define SPI_RXDATA (*(volatile uint32_t*)(SPI_BASE + 0x08))
#define SPI_STATUS (*(volatile uint32_t*)(SPI_BASE + 0x0C))

SPI_TXDATA = 0xA5;
SPI_CTRL   = 0x3;                     // EN | START
while (SPI_STATUS & 0x1) {}           // wait for BUSY to clear
uint8_t rx = SPI_RXDATA & 0xFF;       // received byte
```

Complete, ready-to-run firmware: **[`Example_Usage.md`](SPI_Master/docs/Example_Usage.md)**

**4. Test it**

Flash your bitstream, open a serial terminal at 9600 baud 8N1, and reset the board. In loopback configuration, you should see the transmitted test bytes echoed back over UART:

```
A5
3C
FF
00
B7
```

---

## Documentation Index

| Document | Purpose |
|---|---|
| [`IP_User_Guide.md`](SPI_Master/docs/IP_User_Guide.md) | What the IP does, features, limitations, expected behavior — start here |
| [`Register_Map.md`](SPI_Master/docs/Register_Map.md) | Full bit-level register specification |
| [`Integration_Guide.md`](SPI_Master/docs/Integration_Guide.md) | How to wire this IP into your own SoC |
| [`Example_Usage.md`](SPI_Master/docs/Example_Usage.md) | Ready-to-run C firmware and expected output |

---

## Repository Structure

```
/ip/spi_master/
├── rtl/
│   └── spi_master.v
├── software/
│   └── spi_test.c
├── docs/
│   ├── IP_User_Guide.md
│   ├── Register_Map.md
│   ├── Integration_Guide.md
│   └── Example_Usage.md
└── README.md
```

---

## Known Limitations

No interrupts, no FIFO, single chip-select, Mode-0 only, 8-bit transfers only. See [`IP_User_Guide.md/limitations`](SPI_Master/docs/IP_User_Guide.md#6-known-limitations--notes) for the full list and rationale.
