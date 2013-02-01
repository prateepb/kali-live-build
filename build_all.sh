#!/bin/sh

set -e

KALI_VERSION="${VERSION:-daily}"

HOST_ARCH="$(dpkg --print-architecture)"
case "$HOST_ARCH" in
	i386|amd64)
		CONFIG_OPTS="--debian-installer live"
		if [ "$KALI_ARCH" = "i386" ]; then
			CONFIG_OPTS="$CONFIG_OPTS --linux-flavours 686-pae"
		fi
		KALI_ARCHES="amd64 i386"
		IMAGE_NAME="binary.hybrid.iso"
	;;
	armel|armhf)
		# Can only generate images for the host arch
		CONFIG_OPTS="--binary-images hdd"
		KALI_ARCHES="$HOST_ARCH"
		IMAGE_NAME="binary.img"
	;;
	*)
		echo "ERROR: $HOST_ARCH build is not supported"
		exit 1
	;;
esac

# Set sane PATH (cron seems to lack /sbin/ dirs)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# XXX: Use a git checkout of live-build until we have a good version in wheezy
export LIVE_BUILD=/srv/cdimage.kali.org/live/live-build

cd $(dirname $0)

for KALI_ARCH in $KALI_ARCHES; do
	lb clean --purge >prepare.log 2>&1
	lb config --architecture $KALI_ARCH $CONFIG_OPTS >>prepare.log 2>&1
	lb build >/dev/null
	if [ $? -ne 0 ] || [ ! -e $IMAGE_NAME ]; then
		echo "Build of $KALI_ARCH live image failed" >&2
		echo "Last 50 lines of the log:" >&2
		tail -n 50 binary.log >&2
		exit 1
	fi
	mv $IMAGE_NAME images/kali-$KALI_VERSION-$KALI_ARCH.${IMAGE_NAME##*.}
	mv binary.log images/kali-$KALI_VERSION-$KALI_ARCH.log
done

cd images
sha1sum *.${IMAGE_NAME##*.} >SHA1SUMS

