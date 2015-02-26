#!/bin/bash

set -e
set -o pipefail  # Bashism

KALI_DIST=kali
KALI_VERSION="${VERSION:-daily}"
TARGET_DIR=$(dirname $0)/images/kali-$KALI_VERSION
SUDO="sudo"
VERBOSE=""

image_name() {
	local arch=$1

	case "$arch" in
		i386|amd64)
			IMAGE_TEMPLATE="live-image-ARCH.hybrid.iso"
		;;
		armel|armhf)
			IMAGE_TEMPLATE="live-image-ARCH"
		;;
	esac
	echo $IMAGE_TEMPLATE | sed -e "s/ARCH/$arch/"
}

failure() {
	echo "Build of $KALI_DIST/$KALI_ARCH live image failed" >&2
	if [ -n "$VERBOSE" ]; then
		echo "Last 100 lines of build.log:" >&2
		tail -n 100 build.log >&2
	fi
	exit 2
}

run_and_log() {
	if [ -n "$VERBOSE" ]; then
		"$@" 2>&1 | tee -a build.log
	else
		"$@" >>build.log 2>&1
	fi
	return $?
}

# Parsing command line options
temp=$(getopt -o spdrva: -l single,proposed-updates,kali-dev,kali-rolling,verbose,arch: -- "$@")
eval set -- "$temp"
while true; do
	case "$1" in
		-s|--single) OPT_single="1"; shift 1; ;;
		-p|--proposed-updates) OPT_pu="1"; shift 1; ;;
		-d|--kali-dev) OPT_kali_dev="1"; shift 1; ;;
		-r|--kali-rolling) OPT_kali_rolling="1"; shift 1; ;;
		-a|--arch) KALI_ARCHES="${KALI_ARCHES:+$KALI_ARCHES } $2"; shift 2; ;;
		-v|--verbose) VERBOSE="1"; shift 1; ;;
		--) shift; break; ;;
		*) echo "ERROR: Invalid command-line option: $1" >&2; exit 1; ;;
        esac
done

if [ -n "$OPT_single" ]; then
	echo "WARNING: The --single option is deprecated, it's the default behaviour now." >&2
fi

HOST_ARCH=$(dpkg --print-architecture)
KALI_ARCHES=${KALI_ARCHES:-$HOST_ARCH}

for arch in $KALI_ARCHES; do
	if [ "$arch" = "$HOST_ARCH" ]; then
		continue
	fi
	case "$HOST_ARCH/$arch" in
		amd64/i386|i386/amd64)
		;;
		*)
			echo "Can't build $arch image on $HOST_ARCH system." >&2
			exit 1
		;;
	esac
done

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
if dpkg --compare-versions "$ver_live_build" lt 4.0.4-1kali2; then
	echo "ERROR: You need live-build (>= 4.0.4-1kali2), you have $ver_live_build" >&2
	exit 1
fi
if ! echo "$ver_live_build" | grep -q kali; then
	echo "ERROR: You need a Kali patched live-build. Your current version: $ver_live_build"
	exit 1
fi

# We need root rights at some point
if [ "$(whoami)" != "root" ]; then
	if ! which $SUDO >/dev/null; then
		echo "ERROR: $0 is not run as root and $SUDO is not available"
		exit 1
	fi
else
	SUDO="" # We're already root
fi

cd $(dirname $0)
mkdir -p $TARGET_DIR

for KALI_ARCH in $KALI_ARCHES; do
	IMAGE_NAME="$(image_name $KALI_ARCH)"
	set +e
	: > build.log
	run_and_log $SUDO lb clean --purge
	[ $? -eq 0 ] || failure
	run_and_log lb config -a $KALI_ARCH $KALI_CONFIG_OPTS "$@"
	[ $? -eq 0 ] || failure
	run_and_log $SUDO lb build
	if [ $? -ne 0 ] || [ ! -e $IMAGE_NAME ]; then
		failure
	fi
	set -e
	IMAGE_EXT="${IMAGE_NAME##*.}"
	if [ "$IMAGE_EXT" = "$IMAGE_NAME" ]; then
		IMAGE_EXT="img"
	fi
	mv -f $IMAGE_NAME $TARGET_DIR/kali-linux-$KALI_VERSION-$KALI_ARCH.$IMAGE_EXT
	mv -f build.log $TARGET_DIR/kali-linux-$KALI_VERSION-$KALI_ARCH.log
done

if [ -x ../bin/update-checksums ]; then
	../bin/update-checksums $TARGET_DIR
fi
