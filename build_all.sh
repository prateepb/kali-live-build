#!/bin/sh

set -e

KALI_DIST=kali
KALI_VERSION="${VERSION:-daily}"
TARGET_DIR=$(dirname $0)/images/kali-$KALI_VERSION

HOST_ARCH="$(dpkg --print-architecture)"
case "$HOST_ARCH" in
	i386|amd64)
		KALI_ARCHES="amd64 i386"
		IMAGE_NAME="binary.hybrid.iso"
	;;
	armel|armhf)
		KALI_ARCHES="$HOST_ARCH"
		IMAGE_NAME="binary.img"
	;;
	*)
		echo "ERROR: $HOST_ARCH build is not supported"
		exit 1
	;;
esac

# Parsing command line options
temp=$(getopt -o spdr -l single,proposed-updates,kali-dev,kali-rolling -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
		-s|--single) OPT_single="1"; shift 1; ;;
		-p|--proposed-updates) OPT_pu="1"; shift 1; ;;
		-d|--kali-dev) OPT_kali_dev="1"; shift 1; ;;
		-r|--kali-rolling) OPT_kali_rolling="1"; shift 1; ;;
		--) shift; break; ;;
		*) echo "ERROR: Invalid command-line option: $1" >&2; exit 1; ;;
        esac
done

if [ -n "$OPT_single" ]; then
	echo "Building a single arch ($HOST_ARCH)..."
	KALI_ARCHES="$HOST_ARCH"
fi

KALI_CONFIG_OPTS="--"
if [ -n "$OPT_kali_rolling" ]; then
	echo "Using kali-rolling as the base distribution"
	KALI_CONFIG_OPTS="$KALI_CONFIG_OPTS --kali-rolling"
	if [ "$KALI_VERSION" = "daily" ]; then
		KALI_VERSION="rolling"
	fi
	KALI_DIST="kali-rolling"
elif [ -n "$OPT_kali_dev" ]; then
	echo "Using kali-dev as the base distribution"
	KALI_CONFIG_OPTS="$KALI_CONFIG_OPTS --kali-dev"
	if [ "$KALI_VERSION" = "daily" ]; then
		KALI_VERSION="dev"
	fi
	KALI_DIST="kali-dev"
fi
if [ -n "$OPT_pu" ]; then
	echo "Integrating proposed-updates in the image"
	KALI_CONFIG_OPTS="$KALI_CONFIG_OPTS --proposed-updates"
	KALI_DIST="$KALI_DIST+pu"
fi

# Set sane PATH (cron seems to lack /sbin/ dirs)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Either we use a git checkout of live-build
# export LIVE_BUILD=/srv/cdimage.kali.org/live/live-build

# Or we ensure we have proper version installed
ver_live_build=$(dpkg-query -f '${Version}' -W live-build)
if dpkg --compare-versions "$ver_live_build" lt 3.0.5-1kali7; then
	echo "You need live-build (>= 3.0.5-1kali7), you have $ver_live_build" >&2
	exit 1
fi

cd $(dirname $0)
mkdir -p $TARGET_DIR

for KALI_ARCH in $KALI_ARCHES; do
	lb clean --purge >prepare.log 2>&1
	lb config -a $KALI_ARCH $KALI_CONFIG_OPTS >>prepare.log 2>&1
	lb build >/dev/null
	if [ $? -ne 0 ] || [ ! -e $IMAGE_NAME ]; then
		echo "Build of $KALI_DIST/$KALI_ARCH live image failed" >&2
		echo "Last 50 lines of the log:" >&2
		tail -n 50 binary.log >&2
		exit 1
	fi
	[ -d images ] || mkdir images
	IMAGE_EXT="${IMAGE_EXT:-${IMAGE_NAME##*.}}"
	mv $IMAGE_NAME $TARGET_DIR/kali-linux-$KALI_VERSION-$KALI_ARCH.$IMAGE_EXT
	mv binary.log $TARGET_DIR/kali-linux-$KALI_VERSION-$KALI_ARCH.log
done

if [ -x ../bin/update-checksums ]; then
	../bin/update-checksums $TARGET_DIR
fi
