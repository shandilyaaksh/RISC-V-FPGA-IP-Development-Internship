# SPI Master IP — Register Map

**IP Name:** `spi_master`
**Base Address:** `0x30000000`
**Address Span:** 16 bytes (`0x30000000` – `0x3000000F`)
**Register Width:** 32 bits (word-aligned access only)
**Bus Type:** Memory-mapped, single-cycle, no wait-states

> This document is the authoritative bit-level reference for every register exposed by the SPI Master IP. If any statement here conflicts with a description elsewhere in the documentation set, this document takes precedence.

---

## 1. Address Map Summary

| Offset | Register | Access | Reset Value | Description |
|---|---|---|---|---|
| `0x00` | `CTRL` | R/W | `0x00000000` | Control register — enable and start-transfer bits |
| `0x04` | `TXDATA` | R/W | `0x00000000` | Transmit data register — byte to send |
| `0x08` | `RXDATA` | R | `0x00000000` | Receive data register — last byte received |
| `0x0C` | `STATUS` | R | `0x00000000` | Status register — busy/done flags |

> **Note:** All registers are accessed as full 32-bit words. Only the low-order bits described in each section below carry defined meaning; all unused/reserved bits read as `0` and must be treated as **reserved** (write as zero, ignore on read) by software to preserve forward compatibility with future revisions of this IP.

---

## 2. Register Details

### 2.1 `CTRL` — Control Register

**Offset:** `0x00`
**Access:** Read/Write
**Reset Value:** `0x00000000`

| Bit(s) | Name | Access | Reset | Description |
|---|---|---|---|---|
| 31:2 | — | — | 0 | Reserved. Write as 0. Read as 0. |
| 1 | `START` | R/W | 0 | Write `1` to begin a transfer. Only sampled by hardware while the IP is in its idle state; writes to this bit while a transfer is already in progress have no effect. This bit does not self-clear on readback — see behavioral note below. |
| 0 | `EN` | R/W | 0 | Enables the SPI Master block. When `0`, the IP holds `SCLK` and `CS_n` in their idle states and will not begin a transfer regardless of the state of `START`. |

**Read/Write Behavior**

- A read of `CTRL` returns the last value written to bits `[1:0]`; it does **not** reflect internal FSM state (use `STATUS` for that).
- `EN` must be set to `1` before or in the same write as `START` for a transfer to begin. Writing `START = 1` while `EN = 0` has no effect until `EN` is subsequently set.
- `START` is a **level-triggered request**, not a self-clearing pulse register at the software-visible level: firmware should treat it as "assert to request a transfer" and is **not required** to explicitly clear it afterward, but must not attempt to re-trigger a transfer by re-writing `START = 1` before `STATUS.BUSY` has cleared — such a write during an active transfer is ignored by hardware.

> **Warning:** Writing `CTRL` while `STATUS.BUSY = 1` will not interrupt or restart the in-progress transfer. The write is accepted at the bus level (no bus error is raised) but has no effect on the active transaction. Always confirm `STATUS.BUSY = 0` before writing `CTRL` to start a new transfer.

---

### 2.2 `TXDATA` — Transmit Data Register

**Offset:** `0x04`
**Access:** Read/Write
**Reset Value:** `0x00000000`

| Bit(s) | Name | Access | Reset | Description |
|---|---|---|---|---|
| 31:8 | — | — | 0 | Reserved. Write as 0. Read as 0. |
| 7:0 | `TXDATA` | R/W | 0 | Byte to be transmitted on the next transfer. Loaded into the internal transmit shift path when `START` is accepted. |

**Read/Write Behavior**

- Software must write `TXDATA` **before** writing `START = 1`. There is no automatic double-buffering: the value present in `TXDATA` at the moment `START` is accepted is the value transmitted.
- Reading `TXDATA` returns the last value written — it is not automatically updated by hardware during or after a transfer.
- Writing `TXDATA` while `STATUS.BUSY = 1` is **not recommended**: the byte currently being shifted out was already latched internally when the transfer began, so a mid-transfer write to `TXDATA` will not corrupt the current transfer, but the new value must not be relied upon until the current transfer's `DONE` has been observed, to avoid ambiguity about which byte will be used by a subsequent transfer.

---

### 2.3 `RXDATA` — Receive Data Register

**Offset:** `0x08`
**Access:** Read-Only
**Reset Value:** `0x00000000`

| Bit(s) | Name | Access | Reset | Description |
|---|---|---|---|---|
| 31:8 | — | — | 0 | Reserved. Always reads 0. |
| 7:0 | `RXDATA` | R | 0 | Byte received during the most recently completed transfer. |

**Read/Write Behavior**

- `RXDATA` is updated by hardware only at the completion of a transfer (i.e., when `STATUS.DONE` becomes `1`). Reading it before the first transfer completes returns the reset value `0x00`.
- `RXDATA` is **non-destructive on read** — reading this register any number of times returns the same value and does not clear `STATUS.DONE` or affect internal state. Software may safely re-read `RXDATA` for debugging without side effects.
- Writes to this register are ignored by hardware (register is read-only); no bus error is generated on a write attempt.

---

### 2.4 `STATUS` — Status Register

**Offset:** `0x0C`
**Access:** Read-Only
**Reset Value:** `0x00000000`

| Bit(s) | Name | Access | Reset | Description |
|---|---|---|---|---|
| 31:2 | — | — | 0 | Reserved. Always reads 0. |
| 1 | `DONE` | R | 0 | Set by hardware when a transfer completes. Indicates `RXDATA` holds valid data from the most recent transfer. |
| 0 | `BUSY` | R | 0 | Set by hardware for the entire duration of an active transfer; clears when the transfer completes. |

**Read/Write Behavior**

- `BUSY` and `DONE` are mutually informative but not strictly complementary: `BUSY = 1` implies `DONE = 0`, but `BUSY = 0` does not by itself distinguish "idle, never started" from "idle, transfer completed" — check `DONE` for the latter.
- This is a **read-only** register; write attempts are ignored (no bus error).
- Both flags are combinational reflections of internal controller state — there is no separate "clear-on-read" or "write-1-to-clear" mechanism. `DONE` remains set (readable) until the next transfer is started, at which point it is cleared automatically by hardware for the duration of the new transfer.

---

## 3. Register Access Summary Table

| Register | Typical Software Operation | Frequency |
|---|---|---|
| `TXDATA` | Write | Once per transfer (before `START`) |
| `CTRL` | Write | Once per transfer (to trigger `START`) |
| `STATUS` | Read (poll) | Repeatedly, until `BUSY` clears |
| `RXDATA` | Read | Once per transfer (after `BUSY` clears) |

---

## 4. Reset Behavior

On system reset (assertion of the SoC-wide reset input), all four registers return to their documented reset values (`0x00000000`), the internal transfer FSM returns to its idle state, `CS_n` is driven to its inactive (high) level, and `SCLK` is held at its Mode-0 idle level (low). No transfer is in progress immediately following reset, and `STATUS.BUSY`/`STATUS.DONE` both read `0`.

---

## 5. Reserved Bits and Forward Compatibility

All bit positions marked **Reserved** in the tables above are guaranteed to read as `0` in this IP version. Software **must**:

- Write `0` to all reserved bit positions when writing to `CTRL` or `TXDATA` (do not assume don't-care behavior).
- Ignore the value of reserved bits when reading `CTRL`, `RXDATA`, or `STATUS`.

This convention allows future versions of this IP to add functionality (for example, additional `CTRL` mode bits) in currently-reserved bit positions without breaking software written against this register specification, provided that software follows the rule above.

---

*See `Integration_Guide.md` for address-decoding and RTL wiring instructions, and `Example_Usage.md` for a complete firmware sequence built on top of this register map.*
