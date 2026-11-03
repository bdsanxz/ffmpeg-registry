#!/bin/sh -e
# Configure and build the static libraries for one Apple target.
# Usage: build-arch.sh <config-name>   (e.g. ios-arm64)
. "$(dirname "$0")/../configs/common.sh"
. "$IOS_DIR/configs/$1.sh"

SDKROOT="$(xcrun -sdk "$SDK" --show-sdk-path)"
CC="xcrun -sdk $SDK clang"
export CC

echo "building $1 -> $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

cd "$SRC_DIR"
# The source tree is shared between slices: drop all generated files so
# no object from another architecture leaks into this one.
make distclean > /dev/null 2>&1 || true
./configure \
  --target-os=darwin \
  --arch="$ARCH" \
  --enable-cross-compile \
  --cc="$CC" \
  --sysroot="$SDKROOT" \
  --ar="$(xcrun -sdk "$SDK" -f ar)" \
  --ranlib="$(xcrun -sdk "$SDK" -f ranlib)" \
  --nm="$(xcrun -sdk "$SDK" -f nm)" \
  --strip="$(xcrun -sdk "$SDK" -f strip)" \
  --prefix="$OUT_DIR" \
  --extra-cflags="-arch $ARCH $MIN_FLAG" \
  --extra-ldflags="-arch $ARCH $MIN_FLAG" \
  --enable-static \
  --disable-shared \
  --disable-programs \
  --disable-doc \
  --disable-debug \
  --disable-autodetect \
  --enable-pic \
  --enable-videotoolbox \
  --enable-audiotoolbox \
  --enable-zlib \
  --enable-bzlib

make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
make install
echo "installed: $OUT_DIR"
