.PHONY: clean

all: krunfw_measurement

krunfw_measurement: krunfw_measurement.c
	gcc -o $@ $< -lcrypto

clean:
	rm -rf krunfw_measurement
