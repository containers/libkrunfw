#!/bin/sh

# This is a helper script for building the Linux kernel on macOS using
# a lightweight VM with krunvm.

: "${BUILDER:=fedora}"

SCRIPTPATH=`realpath $0`
WORKDIR=`dirname $SCRIPTPATH`

$WORKDIR/build_on_krunvm_${BUILDER}.sh
