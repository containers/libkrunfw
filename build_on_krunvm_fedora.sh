#!/bin/sh

# This is a helper script for building the Linux kernel on macOS using
# a lightweight VM with krunvm.

KRUNVM=`which krunvm`
if [ -z "$KRUNVM" ]; then
	echo "Couldn't find krunvm binary"
	exit -1
fi

# realpath does not exist by default on macOS, use `brew install coreutils` to get it
SCRIPTPATH=`realpath $0`
WORKDIR=`dirname $SCRIPTPATH`
krunvm create fedora --name libkrunfw-builder --cpus 2 --mem 2048 -v $WORKDIR:/work -w /work
if [ $? != 0 ]; then
	echo "Error creating lightweight VM"
	exit -1
fi

krunvm start libkrunfw-builder /usr/bin/dnf -- install -y 'dnf-command(builddep)' python3-pyelftools
if [ $? != 0 ]; then
	echo "Error installing dnf-builddep on VM"
	krunvm delete libkrunfw-builder
	exit -1
fi

krunvm start libkrunfw-builder /usr/bin/dnf -- builddep -y kernel
if [ $? != 0 ]; then
	echo "Error installing build dependencies for kernel"
	krunvm delete libkrunfw-builder
	exit -1
fi

krunvm start libkrunfw-builder /usr/bin/make -- -j2
if [ $? != 0 ]; then
	echo "Error running command on VM"
	krunvm delete libkrunfw-builder
	exit -1
fi

krunvm delete libkrunfw-builder

if [ ! -e "kernel.c" ]; then
	echo "There was a problem building the kernel bundle in the VM"
	exit -1
fi

exit 0
