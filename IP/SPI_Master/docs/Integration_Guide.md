# SPI Master IP — Integration Guide

**IP Name:** `spi_master`
**Target SoC:** RV32I-based SoC (VSDSquadron FM reference design)
**Target FPGA:** Lattice iCE40UP5K

> This guide explains how to plug the `spi_master` IP into your own VSDSquadron-based RV32I SoC. It assumes you are familiar with the VSDSquadron FPGA platform and its standard memory-mapped bus, but **not** with the internal RTL of this specific IP.

---

## 1. Package Contents

```
/ip/spi_master/
├── rtl/
│   └── spi_master.v          # The IP core — instantiate this, do not modify
├── software/
│   └── spi_test.c            # Reference firmware (see Example_Usage.md)
├── docs/
│   ├── IP_User_Guide.md
│   ├── Register_Map.md
│   ├── Integration_Guide.md  # (this file)
│   └── Example_Usage.md
└── README.md
```

**Required file for integration:** `rtl/spi_master.v`

This is the only RTL file this IP requires. It has no dependencies on any other file in this package and does not require any other custom module beyond standard Verilog constructs supported by the Yosys/nextpnr open-source toolchain used for iCE40 targets.

---

## 2. Signals Exposed to the Top Level

The IP presents two signal groups to the integrator: a **bus-side interface** (connects to your SoC's shared memory bus) and a **pin-side interface** (connects to physical SPI signals, either routed to board pins or looped back internally for bench testing).

### 2.1 Bus-Side Interface

| Signal | Direction (relative to IP) | Width | Description |
|---|---|---|---|
| `clk` | Input | 1 | System clock. Must be the same clock domain as the CPU and shared bus. |
| `resetn` | Input | 1 | Active-low synchronous reset. |
| `sel` | Input | 1 | Asserted by the top-level address decoder when `mem_addr` falls within this IP's 16-byte register window. |
| `we` | Input | 1 | Write-enable. Typically wired to the SoC's global write-strobe (`|mem_wmask`), qualified externally by `sel`. |
| `addr` | Input | 32 | Full system address bus. The IP internally decodes bits `[3:2]` to select among its four registers; upper bits are not used internally (address-range gating is the top level's responsibility via `sel`). |
| `wdata` | Input | 32 | System write-data bus. |
| `rdata` | Output | 32 | Register read-data output. Valid combinationally whenever `sel` is asserted; must be muxed onto the shared system read bus by the top level. |

### 2.2 Pin-Side Interface

| Signal | Direction (relative to IP) | Width | Description |
|---|---|---|---|
| `sclk` | Output | 1 | SPI serial clock. Idles low (Mode-0). |
| `mosi` | Output | 1 | SPI Master-Out-Slave-In data line. |
| `miso` | Input | 1 | SPI Master-In-Slave-Out data line. |
| `cs_n` | Output | 1 | Active-low chip select, framed automatically per transfer. |

---

## 3. Instantiation Template

```verilog
spi_master spi_inst (
    .clk    (clk),
    .resetn (resetn),

    // Bus-side interface
    .sel    (spi_sel),
    .we     (mem_wstrb),
    .addr   (mem_addr),
    .wdata  (mem_wdata),
    .rdata  (spi_rdata),

    // Pin-side interface
    .sclk   (spi_sclk),
    .mosi   (spi_mosi),
    .miso   (spi_miso),
    .cs_n   (spi_cs_n)
);
```

Copy this instantiation into your top-level SoC file (e.g. `riscv.v` in the VSDSquadron reference SoC), alongside your other memory-mapped peripherals (GPIO, UART, etc.).

---

## 4. Address Decoding Requirements

The IP itself does **not** perform full-address range checking against the rest of the system — that responsibility belongs to the top-level integrator, via the `sel` input. You must generate `sel` externally using a comparator against your chosen base address.

**Reference base address used by this IP's documentation and example firmware: `0x30000000`.**

```verilog
// 16-byte register window: 0x30000000 - 0x3000000F
wire spi_sel = (mem_addr[31:4] == 28'h3000000);
```

> **Warning:** You may relocate this IP to a different base address in your own SoC, provided you (1) update the comparator constant above accordingly, and (2) update the base-address macro in your firmware (`SPI_BASE` in `spi_test.c`, see `Example_Usage.md`) to match. **Do not** choose a base address that overlaps any existing peripheral's decoded range — verify this explicitly against your SoC's existing address map before integrating.

### 4.1 Read-Data Multiplexing

Because the SPI IP's `rdata` output shares the system's single read-data bus with every other peripheral, it must be combined into your existing priority-mux structure:

```verilog
assign mem_rdata =
    isRAM   ? RAM_rdata  :
    spi_sel ? spi_rdata  :
    gpio_sel ? gpio_rdata :
    IO_rdata;
```

The order of the ternary chain does not affect functional correctness as long as each `_sel` signal is mutually exclusive by construction (guaranteed if your address ranges do not overlap) — but as a best practice, group all discrete-peripheral selects together, ahead of any legacy/catch-all IO decode.

### 4.2 Write Strobe

Wire `we` to your SoC's global write-strobe signal (commonly `wire mem_wstrb = |mem_wmask;`), **not** to individual byte-lane bits. This IP performs full-word register writes only and does not decode `mem_wmask` sub-fields internally; if your bus provides sub-word write masking, that granularity is not honored by this IP — a store instruction of any width targeting this IP's address range will be treated as a full-word write.

---

## 5. Clock and Reset Requirements

| Requirement | Detail |
|---|---|
| **Clock domain** | The IP must be clocked from the same domain as the CPU and shared bus. No clock-domain-crossing logic is included or required. |
| **Reference frequency** | Reference documentation and timing assume a 12 MHz system clock (VSDSquadron FM's internal `SB_HFOSC`-derived clock, divided as configured in the reference SoC). |
| **Reset polarity** | Active-low, synchronous, matching the SoC's global `resetn`. |
| **Effect of a different clock frequency** | The IP's internal SPI clock divider produces `SCLK` as a fixed division of the system clock. Changing the system clock frequency will proportionally change the resulting `SCLK` frequency. If your target SPI slave device has a maximum SCLK frequency requirement, verify the resulting SCLK rate against your system clock before deployment. |

---

## 6. Board-Level Usage (VSDSquadron FPGA)

### 6.1 Pin Connections

| IP Signal | Recommended VSDSquadron FM Connection |
|---|---|
| `sclk` | Route to a header pin connected to your SPI slave device's clock input, or leave unconnected/internally looped for bench testing (see Section 6.2) |
| `mosi` | Route to a header pin connected to your SPI slave device's data input |
| `miso` | Route from a header pin connected to your SPI slave device's data output |
| `cs_n` | Route to a header pin connected to your SPI slave device's chip-select input |

Update your board's `.pcf` constraint file to assign these signals to the specific header pins you intend to use. This IP does not dictate specific pin numbers — pin assignment is a board/application-level decision.

### 6.2 Bench-Test Loopback Mode (No External Slave Required)

For initial bring-up without a physical SPI slave device attached, connect `miso` directly to `mosi` at the top level:

```verilog
assign spi_miso = spi_mosi;   // Loopback for self-checking bench test
```

In this configuration, every byte transmitted will be received back identically, allowing you to verify correct IP integration (address decode, register access, transfer completion) purely from firmware and UART output, without needing any external hardware. This is the configuration used to validate the reference firmware in `Example_Usage.md`.

> **Note:** Loopback mode is a bring-up/verification aid only. Remove the loopback assignment and wire `miso`/`mosi` to your actual physical header pins before deploying against a real SPI slave device.

---

## 7. Integration Checklist

Before considering integration complete, confirm the following:

- [ ] `spi_master.v` instantiated in top-level SoC RTL with all bus-side and pin-side ports connected.
- [ ] `spi_sel` comparator added, using a base address that does not overlap any existing peripheral.
- [ ] `spi_rdata` added into the system's read-data priority mux.
- [ ] `we` wired to the global write-strobe signal.
- [ ] Clock and reset connected to the same domain as the rest of the SoC.
- [ ] Either physical SPI pins constrained in the `.pcf` file, or loopback mode connected for bench testing.
- [ ] Firmware's `SPI_BASE` macro updated to match the chosen base address (see `Example_Usage.md`).
- [ ] Design re-synthesized, placed, routed, and re-flashed after integration.

---

*Once integration is complete, proceed to `Example_Usage.md` for a ready-to-run firmware example, or `Register_Map.md` for full register-level detail.*
