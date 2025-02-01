#!/bin/sh -e
#
# SPDX-License-Identifier: LGPL-2.1-only
#
# utils/kernel_size_time.sh - Check build size, and boot time for given command
#
# Copyright (c) 2025 Red Hat GmbH
# Author: Stefano Brivio <sbrivio@redhat.com>

CONFIG="${CONFIG:-config-libkrunfw_x86_64}"
RUNS=${RUNS:-10}
TIME_CMD="${TIME_CMD:-~/muvm/target/release/muvm --mem=64 --vram=0 -c 0,1 -- true}"
PREV_SIZE_FILE="prev_size"
PREV_TIME_FILE="prev_time"
LOG_FILE="log"

find_time_dash_p() {
	REEXEC_BASH=n
	if time -p ':'; then
		TIME_DASH_P='time -p'
	elif command -v /usr/bin/time; then
		TIME_DASH_P='/usr/bin/time -p'
	elif command -v bash; then
		# Simply re-execute under bash to avoid further eval tricks
		REEXEC_BASH=y
	fi
}

build() {
	for KERNELDIR in linux-*/; do
		cp "${CONFIG}" "${KERNELDIR}/.config"
	done

	rm -f linux-*/vmlinux
	make clean
	make -j$(nproc) || make -j$(($(nproc) / 2)) || make
}

measure_runs() {
	export LD_PRELOAD=$(ls $(pwd)/libkrunfw.so.*)
	for i in $(seq 1 ${RUNS}); do eval ${TIME_CMD}; done
}

measure() {
	NEW_SIZE=$(stat -c %s linux-*/vmlinux)
	NEW_TIME="$( eval ${TIME_DASH_P} measure_runs 2>&1 | grep real | tr -dc [:digit:] )5"
}

log() {
	BASE_SIZE="$(cat ${PREV_SIZE_FILE} 2>/dev/null || :)"
	BASE_TIME="$(cat ${PREV_TIME_FILE} 2>/dev/null || :)"

	[ -e "${PREV_SIZE_FILE}" ] || FIRST="y"

	echo "$NEW_SIZE" > "${PREV_SIZE_FILE}"
	echo "$NEW_TIME" > "${PREV_TIME_FILE}"

	git rev-parse HEAD >> ${LOG_FILE}

	if [ "${FIRST}" = "y" ]; then
		NEW_TIME="$(echo 'scale=0; '$NEW_TIME' / '${RUNS} | bc -l)"
		printf "Baseline:
- %i bytes in the uncompressed kernel image

- %i ms (average of ${RUNS} runs) for:
    ${TIME_CMD}

" $NEW_SIZE $NEW_TIME >> ${LOG_FILE}
		exit 0
	fi

	DIFF_SIZE="$((BASE_SIZE - NEW_SIZE))"
	DIFF_TIME="$((BASE_TIME - NEW_TIME))"

	DIFF_TIME="$(echo 'scale=0; '$DIFF_TIME' / '${RUNS} | bc -l)"
	BASE_TIME="$(echo 'scale=0; '$BASE_TIME' / '${RUNS} | bc -l)"
	NEW_TIME="$(echo 'scale=0; '$NEW_TIME' / '${RUNS} | bc -l)"

	printf "This saves:
- %i bytes (%i -> %i) in the uncompressed kernel image

- %i ms (%i -> %i, average of ${RUNS} runs) for:
    ${TIME_CMD}

" $DIFF_SIZE $BASE_SIZE $NEW_SIZE $DIFF_TIME $BASE_TIME $NEW_TIME >> ${LOG_FILE}
}

build
find_time_dash_p >/dev/null 2>&1 || { echo "No implementation of 'time -p', exiting"; exit 1; }

if [ ${REEXEC_BASH} = "y" ]; then
	bash $0
else
	measure
	log
fi
