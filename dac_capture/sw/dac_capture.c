#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <string.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <time.h>
#include <signal.h>
#include <linux/spi/spidev.h>
#include "wishbone_wrapper.h"


// Number of bytes for half of read buffer (# addresses * 16-bit words)
#define HALF_BUFFER_SIZE (0x20000*2)
#define BUFFER_ADDR 0x00000
#define HALF_BUFFER_ADDR 0x20000

#define CAPTURE_REG_ADDR 0x40000
#define POINTER_L_REG_ADDR 0x40001
#define POINTER_H_REG_ADDR 0x40002
#define INTERRUPT_REG_ADDR 0x40003

#define WR0(a, i)       ((a >> 14) & 0x0FF)
#define WR1(a, i)       ((a >> 6) & 0x0FF)
#define WR2(a, i)       (((a << 2) & 0xFC) | (i << 1))

#define RD0(a, i)       ((a >> 14) & 0x0FF)
#define RD1(a, i)       ((a >> 6) & 0x0FF)
#define RD2(a, i)       (((a << 2) & 0xFC) | 0x01 | (i << 1))



int outfile_fd;


#define CMD_SIZE 3
// Max 32K - cmd size
#define MAX_TRANSFER_SIZE 16384

static unsigned char small_cmd_buffer[CMD_SIZE+2];
static unsigned char readbuffer[CMD_SIZE+HALF_BUFFER_SIZE];
static unsigned char buffer[HALF_BUFFER_SIZE];

static struct spi_ioc_transfer spi_trx[3];


extern void setup_gpio();
extern void cleanup_gpio();
extern int get_gpio(int port);
extern int spi_init();
extern void spi_close();

extern unsigned long spi_speed;
extern int spi_fd;

volatile sig_atomic_t quitflag = 0;


void clear_interrupt(int bitmask) {

	unsigned char buffer[2];

	buffer[0] = bitmask;
	buffer[1] = 0x00;
	wishbone_write((unsigned char *)buffer, 2, INTERRUPT_REG_ADDR);

}

void enable_capture(unsigned char en) {

	unsigned char buffer[2];

	buffer[0] = (en ? 1 : 0);
	buffer[1] = 0x00;
	wishbone_write((unsigned char *)buffer, 2, CAPTURE_REG_ADDR);

}

int get_buffer(int addr, int buffer_size, int clear_int_bitmask) {

	int trxpos;
	int ndone, count, nwritten;
	int ret, i, sample;
	unsigned char b0,b1,b2,b3;

	trxpos = 0;

	if (clear_int_bitmask) {

		spi_trx[0].tx_buf = (__u32) small_cmd_buffer;
		spi_trx[0].rx_buf = (__u32) small_cmd_buffer;
		spi_trx[0].len = CMD_SIZE+2;
		spi_trx[0].delay_usecs = 0;
		spi_trx[0].speed_hz = spi_speed;
		spi_trx[0].bits_per_word = 0;
		spi_trx[0].cs_change = 1;

		small_cmd_buffer[0] = WR0(INTERRUPT_REG_ADDR, 0 /*inc*/);
		small_cmd_buffer[1] = WR1(INTERRUPT_REG_ADDR, 0 /*inc*/);
		small_cmd_buffer[2] = WR2(INTERRUPT_REG_ADDR, 0 /*inc*/);
		small_cmd_buffer[3] = clear_int_bitmask;
		small_cmd_buffer[4] = 0x00;

		trxpos++;

	}

	ndone = 0;

	while (ndone < buffer_size) {

		count = buffer_size - ndone;
		// SPI buffer can hold 32K, including command bytes
		if (count > MAX_TRANSFER_SIZE) {
			count = MAX_TRANSFER_SIZE;
		}

		spi_trx[trxpos].tx_buf = (__u32) readbuffer;
		spi_trx[trxpos].rx_buf = (__u32) readbuffer;
		spi_trx[trxpos].len = count+CMD_SIZE;
		spi_trx[trxpos].delay_usecs = 0;
		spi_trx[trxpos].speed_hz = spi_speed;
		spi_trx[trxpos].bits_per_word = 0;
		spi_trx[trxpos].cs_change = 1;

		readbuffer[0] = RD0(addr, 1);
		readbuffer[1] = RD1(addr, 1);
		readbuffer[2] = RD2(addr, 1);

		ret = ioctl(spi_fd, SPI_IOC_MESSAGE(trxpos+1), &spi_trx);
		if (ret < 1) {
			fprintf(stderr, "ERROR: spi transfer error %d\n", ret);
			enable_capture(0);
			cleanup_gpio();
			close(outfile_fd);
			return 1;
		}

		memcpy(((unsigned char *)buffer)+ndone, ((unsigned char *)readbuffer)+CMD_SIZE, count);

		ndone += count;
		addr += (count/2);

		trxpos = 0;

	} // while (more to read)

	for (i = 0; i < buffer_size; i += 4) {
		b3 = buffer[i];
		b2 = buffer[i+1];
		b1 = buffer[i+2];
		b0 = buffer[i+3];

		sample = (unsigned int)b0 << 24 | (unsigned int)b1 << 16 | (unsigned int)b2 << 8 | b3;
		sample = sample << 4;

		if ((sample & 0x800000) == 0x800000)
			buffer[i] = 0xFF;
		else
			buffer[i] = 0;
		buffer[i+1] = (sample >> 16) & 0xFF;
		buffer[i+2] = (sample >> 8) & 0xFF;
		buffer[i+3] = sample & 0xFF;
	}

	nwritten = write(outfile_fd, buffer, buffer_size);

	if (nwritten < buffer_size) {
		fprintf(stderr, "ERROR: Short write: %d\n", nwritten);
		enable_capture(0);
		spi_close();
		cleanup_gpio();
		close(outfile_fd);
		return 1;
	}

	return 0;
}

void sigint_handler(int sig) {
	quitflag = 1;
}

int main(int argc, char ** argv){

	int addr;
	int ptr, count;
	int bitmask;
	time_t lastTime, currentTime;

	if (argc < 2) {
		fprintf(stderr, "Usage: %s output.wav\n", argv[0]);
		exit(1);
	}

	if ((outfile_fd = open(argv[1], O_CREAT|O_EXCL|O_RDWR, S_IRUSR|S_IWUSR) ) < 0) {
		fprintf(stderr, "Unable to create output file %s: %s\n", argv[1], strerror(errno));
		exit(1);
	}

	ftruncate(outfile_fd, 0);

	signal(SIGINT, sigint_handler);

	memset(readbuffer, 0, CMD_SIZE+HALF_BUFFER_SIZE);
	memset(spi_trx, 0, sizeof(struct spi_ioc_transfer)*2);

	setup_gpio();
	spi_init();

	wishbone_read((unsigned char *)buffer, 4, POINTER_L_REG_ADDR);

	if (buffer[0] || buffer[1] || buffer[2] || buffer[3]) {
		fprintf(stderr, "Buffer write pointer is not zero (0x%02x%02x%02x%02x).  Reset the FPGA.\n", buffer[3], buffer[2], buffer[1], buffer[0]);
		spi_close();
		cleanup_gpio();
		exit(1);
	}

	enable_capture(0);

	wishbone_read((unsigned char *)buffer, 2, INTERRUPT_REG_ADDR);
	fprintf(stderr, "Int reg reads as 0x%x 0x%x\n", buffer[0], buffer[1]);

	// Clear interrupts
	clear_interrupt(3);

	fprintf(stderr, "Ready to save data to %s\n", argv[1]);
	fprintf(stderr, "Use Control+C to quit\n");

	enable_capture(1);


	while (1) {

		time(&lastTime);

		while (get_gpio(27) == 0) {

			// 10 microseconds
			//usleep(10);
			time(&currentTime);

			if (quitflag || currentTime - lastTime > 10) {

				if (quitflag) {
					fprintf(stderr, "Stop on Control+C.\n");
				}
				else {
					fprintf(stderr, "No data after 10 seconds.  Quitting.\n");
				}

				// Read buffer pointer register
				wishbone_read((unsigned char *)buffer, 2, POINTER_L_REG_ADDR);
				wishbone_read((unsigned char *)buffer+2, 2, POINTER_H_REG_ADDR);

				enable_capture(0); // Also resets the write pointer...

				ptr = ((unsigned int)buffer[2]) << 16 | ((unsigned int)buffer[1]) << 8 | (unsigned int)buffer[0];

				printf("Pointer ends at: 0x%04x\n", ptr);

				// Pointer is in first half or second half?
				if (ptr < HALF_BUFFER_ADDR) {
					addr = BUFFER_ADDR;
				}
				else {
					addr = BUFFER_ADDR+HALF_BUFFER_ADDR;
				}

				count = (ptr - addr) * 2;

				printf("Final read %d bytes from %04x\n", count, addr);

				if (count > 0) {

					if (get_buffer(addr, count, 0))
						return 1;

				}

				spi_close();
				cleanup_gpio();
				close(outfile_fd);
				return 0;
			}
		}


		wishbone_read((unsigned char *)buffer, 2, INTERRUPT_REG_ADDR);

		if ((buffer[0] & 0x03) == 0x03) {
			fprintf(stderr, "*** ERROR: Buffer overflow\n");
			enable_capture(0);
			spi_close();
			cleanup_gpio();
			close(outfile_fd);
			return 1;
		}


		if ((buffer[0] & 0x01) == 0x01) {
			addr = BUFFER_ADDR;
			bitmask = 1;
		}
		else {
			addr = BUFFER_ADDR + HALF_BUFFER_ADDR;
			bitmask = 2;
		}

		// We can clear the interrupt now because it is
		// triggered as the write pointer moves past the the
		// end of buffer, so we assume that the pointer
		// is now somewhere in the middle of the other half
		//clear_interrupt(bitmask);

		if (get_buffer(addr, HALF_BUFFER_SIZE, bitmask))
			return 1;

		//fprintf(stderr, ".");

	}

	// Should never get here
	spi_close();
	cleanup_gpio();
	close(outfile_fd);

	return 1;
}

