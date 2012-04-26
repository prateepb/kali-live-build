#!/bin/sh

set -e

ARCHES="i386 amd64"
DATE=$(date +%Y%m%d)

for ARCH in ARCHES; do
	lb clean --purge
	lb config --architecture $ARCH
	lb build
	mv binary.iso kali-$ARCH.iso
done

