CC = gcc


all: dac_capture

clean:
	rm -f *.o dac_capture

gpio.o: gpio.c
	$(CC) -c gpio.c

wishbone_wrapper.o: wishbone_wrapper.c
	$(CC) -c wishbone_wrapper.c

dac_capture : dac_capture.c wishbone_wrapper.o gpio.o
	$(CC) -Wall -o $@ dac_capture.c wishbone_wrapper.o gpio.o
