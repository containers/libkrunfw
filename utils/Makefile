.PHONY: clean

all: sev_launch_measurement

sev_launch_measurement: sev_launch_measurement.c
	gcc -o $@ $< -lcrypto

clean:
	rm -rf sev_launch_measurement
