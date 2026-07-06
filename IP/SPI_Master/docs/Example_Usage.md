# SPI Master IP — Example Usage

**IP Name:** `spi_master`
**Language:** C (bare-metal, no OS/RTOS dependency)
**Target:** RV32I softcore on VSDSquadron FM

> This document provides a complete, ready-to-run firmware example demonstrating how to drive the `spi_master` IP from C. It assumes the IP has already been integrated per `Integration_Guide.md`, and that you understand the register set described in `Register_Map.md`.

---

## 1. Prerequisites

- `spi_master` IP instantiated and wired at base address `0x30000000` (or your chosen address — update `SPI_BASE` below to match).
- A UART peripheral available on your SoC for printing results (the reference example assumes the standard VSDSquadron UART memory-mapped interface).
- Either an external SPI slave device connected to the board's SPI header pins, **or** the bench-test loopback (`miso` tied to `mosi`) described in `Integration_Guide.md` Section 6.2.

---

## 2. Register Access Macros

```c
#include <stdint.h>

#define SPI_BASE    0x30000000u

#define SPI_CTRL    (*(volatile uint32_t*)(SPI_BASE + 0x00))
#define SPI_TXDATA  (*(volatile uint32_t*)(SPI_BASE + 0x04))
#define SPI_RXDATA  (*(volatile uint32_t*)(SPI_BASE + 0x08))
#define SPI_STATUS  (*(volatile uint32_t*)(SPI_BASE + 0x0C))

#define SPI_CTRL_EN     (1u << 0)
#define SPI_CTRL_START  (1u << 1)
#define SPI_STATUS_BUSY (1u << 0)
#define SPI_STATUS_DONE (1u << 1)
```

> **Note:** The `volatile` qualifier on every register pointer is mandatory, not optional. Without it, an optimizing compiler is free to cache, reorder, or eliminate accesses to these addresses, since nothing in the C abstract machine indicates that memory-mapped hardware state can change independently of program flow. Omitting `volatile` here is a common source of "polling loop never exits" bugs.

---

## 3. Driver Function: Single-Byte Blocking Transfer

```c
/**
 * spi_transfer_byte
 * ------------------
 * Sends one byte over SPI and returns the byte received in the same
 * transfer (full-duplex). Blocks until the transfer completes.
 */
uint8_t spi_transfer_byte(uint8_t tx_byte) {
    SPI_TXDATA = (uint32_t)tx_byte;              // Step 1: stage byte to send
    SPI_CTRL   = SPI_CTRL_EN | SPI_CTRL_START;   // Step 2: enable + trigger transfer

    while (SPI_STATUS & SPI_STATUS_BUSY) {
        // Step 3: poll until hardware clears BUSY
    }

    return (uint8_t)(SPI_RXDATA & 0xFF);          // Step 4: retrieve received byte
}
```

This single function is the complete driver required to use this IP — there is no initialization routine beyond what is shown here, because the IP requires no configuration beyond the `EN`/`START` sequence for every transfer (Mode-0 timing and 8-bit width are fixed in hardware, per `Register_Map.md`).

---

## 4. Complete Example Program

```c
#include <stdint.h>

#define SPI_BASE    0x30000000u
#define SPI_CTRL    (*(volatile uint32_t*)(SPI_BASE + 0x00))
#define SPI_TXDATA  (*(volatile uint32_t*)(SPI_BASE + 0x04))
#define SPI_RXDATA  (*(volatile uint32_t*)(SPI_BASE + 0x08))
#define SPI_STATUS  (*(volatile uint32_t*)(SPI_BASE + 0x0C))

#define SPI_CTRL_EN     (1u << 0)
#define SPI_CTRL_START  (1u << 1)
#define SPI_STATUS_BUSY (1u << 0)

/* --- UART output, assumed already provided by your SoC's BSP --- */
extern void uart_putchar(char c);

void uart_print_hex_byte(uint8_t b) {
    const char hex[] = "0123456789ABCDEF";
    uart_putchar(hex[(b >> 4) & 0xF]);
    uart_putchar(hex[b & 0xF]);
    uart_putchar('\r');
    uart_putchar('\n');
}

uint8_t spi_transfer_byte(uint8_t tx_byte) {
    SPI_TXDATA = (uint32_t)tx_byte;
    SPI_CTRL   = SPI_CTRL_EN | SPI_CTRL_START;

    while (SPI_STATUS & SPI_STATUS_BUSY) {
        /* wait for transfer to complete */
    }

    return (uint8_t)(SPI_RXDATA & 0xFF);
}

int main(void) {
    /* A deliberately varied test vector: alternating bit patterns,
       all-ones, all-zeros, and a mixed pattern — chosen to exercise
       every bit-value class through the shift path. */
    static const uint8_t test_vector[] = { 0xA5, 0x3C, 0xFF, 0x00, 0xB7 };
    const int n = sizeof(test_vector) / sizeof(test_vector[0]);

    for (int i = 0; i < n; i++) {
        uint8_t rx = spi_transfer_byte(test_vector[i]);
        uart_print_hex_byte(rx);
    }

    while (1) {
        /* halt */
    }

    return 0;
}
```

---

## 5. Expected Output

### 5.1 In Loopback Mode (No External Slave)

With `miso` tied to `mosi` per `Integration_Guide.md` Section 6.2, the byte received will always equal the byte transmitted. Running the program above produces the following UART output at 9600 baud, 8N1:

```
A5
3C
FF
00
B7
```

### 5.2 With a Real External SPI Slave

If a physical SPI slave device is connected instead of loopback, the received bytes will reflect whatever that specific slave device returns in response to each transmitted byte — consult your slave device's own datasheet for its expected response behavior. The driver function and firmware structure above remain identical regardless of which physical device is attached; only the *interpretation* of the received bytes changes.

---

## 6. Extending This Example

### 6.1 Multi-Byte Transfers

Since this IP supports only single-byte transactions (see `IP_User_Guide.md`, Known Limitations), multi-byte SPI commands (e.g., "write register address, then write register value") must be implemented in software as a sequence of individual `spi_transfer_byte()` calls, with `cs_n` framing occurring independently around *each* byte:

```c
/* NOTE: cs_n is automatically toggled per-byte by hardware. If your
   SPI slave device requires cs_n to remain asserted across multiple
   bytes within a single logical command, this IP's per-byte framing
   is NOT suitable without an external CS override — see
   IP_User_Guide.md Known Limitations. */
uint8_t addr_echo = spi_transfer_byte(0x80);   // e.g. register address byte
uint8_t data_echo  = spi_transfer_byte(0x42);  // e.g. register value byte
```

> **Warning:** Because `cs_n` is asserted and de-asserted automatically around every single-byte transfer by this IP, back-to-back calls to `spi_transfer_byte()` will produce a `cs_n` pulse (rising then falling) *between* each byte. This is compatible with SPI slave devices that treat every byte as an independent transaction, but is **not** compatible with slave devices that require `cs_n` to remain continuously asserted across a multi-byte command frame. For the latter case, this IP is not suitable in its current version without an external chip-select override mechanism.

### 6.2 Timeout-Protected Polling

The blocking `while (SPI_STATUS & SPI_STATUS_BUSY)` loop in Section 3 will hang indefinitely if the IP is misintegrated (see the failure symptoms table in `IP_User_Guide.md`). For production firmware, consider adding a bounded retry count:

```c
uint8_t spi_transfer_byte_safe(uint8_t tx_byte, int *timed_out) {
    SPI_TXDATA = (uint32_t)tx_byte;
    SPI_CTRL   = SPI_CTRL_EN | SPI_CTRL_START;

    uint32_t guard = 100000; /* tune for your system clock / SPI rate */
    while ((SPI_STATUS & SPI_STATUS_BUSY) && guard--) { }

    *timed_out = (guard == 0);
    return (uint8_t)(SPI_RXDATA & 0xFF);
}
```

---

*For full register-level detail behind every access in this example, see `Register_Map.md`. For RTL wiring and address-decode setup, see `Integration_Guide.md`.*
