/*
 * SPI Master Test Firmware
 * Task 6: Real Peripheral IP Development
 *
 * SPI Base Address : 0x30000000
 * Loopback test    : MISO tied to MOSI in simulation
 * Expected result  : RXDATA == TXDATA for every transfer
 */

#include <stdint.h>

/* Provided by print.c in the firmware library — do NOT redefine */
void print_hex(unsigned int val);

/* SPI Register Definitions */
#define SPI_BASE    0x30000000UL

#define SPI_CTRL    (*(volatile uint32_t *)(SPI_BASE + 0x00))
#define SPI_TXDATA  (*(volatile uint32_t *)(SPI_BASE + 0x04))
#define SPI_RXDATA  (*(volatile uint32_t *)(SPI_BASE + 0x08))
#define SPI_STATUS  (*(volatile uint32_t *)(SPI_BASE + 0x0C))

/* STATUS bit masks */
#define SPI_BUSY  (1u << 0)
#define SPI_DONE  (1u << 1)

/* CLKDIV value — SCLK toggles every (CLKDIV+1) system cycles */
#define SPI_CLKDIV  5

/*
 * spi_transfer()
 * Loads one byte, triggers a transfer, waits for completion,
 * clears the DONE flag, and returns the received byte.
 */
uint8_t spi_transfer(uint8_t tx_byte)
{
    /* Step 1: Load the byte to transmit */
    SPI_TXDATA = tx_byte;

    /* Step 2: Write CTRL — EN=1, START=1, CLKDIV set */
    SPI_CTRL = ((uint32_t)SPI_CLKDIV << 8) | 0x3;

    /* Step 3: Poll until DONE flag is set */
    while (!(SPI_STATUS & SPI_DONE));

    /* Step 4: Clear DONE (write-1-to-clear) */
    SPI_STATUS = SPI_DONE;

    /* Step 5: Return received byte */
    return (uint8_t)(SPI_RXDATA & 0xFF);
}

int main(void)
{
    uint8_t rx;

    /* Configure SPI once: CLKDIV=5, EN=1, START=0 */
    SPI_CTRL = ((uint32_t)SPI_CLKDIV << 8) | 0x1;

    /* Test 1: Send 0xA5 — loopback should return 0xA5 */
    rx = spi_transfer(0xA5);
    print_hex((unsigned int)rx);   /* Expected: 000000A5 */

    /* Test 2: Send 0x3C */
    rx = spi_transfer(0x3C);
    print_hex((unsigned int)rx);   /* Expected: 0000003C */

    /* Test 3: Send 0xFF */
    rx = spi_transfer(0xFF);
    print_hex((unsigned int)rx);   /* Expected: 000000FF */

    /* Test 4: Send 0x00 */
    rx = spi_transfer(0x00);
    print_hex((unsigned int)rx);   /* Expected: 00000000 */

    /* Test 5: Send 0xB7 */
    rx = spi_transfer(0xB7);
    print_hex((unsigned int)rx);   /* Expected: 000000B7 */

    /* Halt processor */
    while (1);

    return 0;
}
