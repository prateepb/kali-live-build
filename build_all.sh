#!/bin/sh

set -e

KALI_VERSION="${VERSION:-daily}"

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
temp=$(getopt -o s -l single -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
		-s|--single) OPT_single="1"; shift 1; ;;
		--) shift; break; ;;
		*) echo "ERROR: Invalid command-line option: $1" >&2; exit 1; ;;
        esac
done

if [ -n "$OPT_single" ]; then
	echo "Building a single arch ($HOST_ARCH)..."
	KALI_ARCHES="$HOST_ARCH"
fi

# Set sane PATH (cron seems to lack /sbin/ dirs)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Either we use a git checkout of live-build
# export LIVE_BUILD=/srv/cdimage.kali.org/live/live-build

# Or we ensure we have proper version installed
ver_live_build=$(dpkg-query -f '${Version}' -W live-build)
if dpkg --compare-versions "$ver_live_build" lt 3.0~b6; then
	echo "You need live-build (>= 3.0~b6), you have $ver_live_build" >&2
	exit 1
fi

cd $(dirname $0)

for KALI_ARCH in $KALI_ARCHES; do
	lb clean --purge >prepare.log 2>&1
	lb config -a $KALI_ARCH >>prepare.log 2>&1
	lb build >/dev/null
	if [ $? -ne 0 ] || [ ! -e $IMAGE_NAME ]; then
		echo "Build of $KALI_ARCH live image failed" >&2
		echo "Last 50 lines of the log:" >&2
		tail -n 50 binary.log >&2
		exit 1
	fi
	[ -d images ] || mkdir images
	if [ "$IMAGE_NAME" = "binary.img" ]; then
		xz -6 $IMAGE_NAME
		IMAGE_NAME="$IMAGE_NAME.xz"
		IMAGE_EXT="img.xz"
	fi
	IMAGE_EXT="${IMAGE_EXT:-${IMAGE_NAME##*.}}"
	mv $IMAGE_NAME images/kali-$KALI_VERSION-$KALI_ARCH.$IMAGE_EXT
	mv binary.log images/kali-$KALI_VERSION-$KALI_ARCH.log
done

../bin/update-checksums images
