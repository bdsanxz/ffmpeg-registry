#!/bin/sh -e
# Validate the built libraries: architecture slices, key symbols, headers.
. "$(dirname "$0")/../configs/common.sh"

fail=0

check_arch() {
  # $1 = archive, $2 = expected archs (order-insensitive)
  got="$(lipo -archs "$1" 2>/dev/null | tr ' ' '\n' | sort | tr '\n' ' ')"
  want="$(echo "$2" | tr ' ' '\n' | sort | tr '\n' ' ')"
  if [ "$got" != "$want" ]; then
    echo "FAIL: $1 archs=[$got] want [$2]" >&2
    fail=1
  else
    echo "ok: $1 [$got]"
  fi
}

check_sym() {
  # $1 = archive, $2 = symbol
  if ! nm -g "$1" 2>/dev/null | grep -q "$2"; then
    echo "FAIL: $1 missing symbol $2" >&2
    fail=1
  else
    echo "ok: $1 exports $2"
  fi
}

check_arch "$BUILD_DIR/ios-arm64/lib/libavcodec.a" "arm64"
check_arch "$BUILD_DIR/ios-sim-arm64/lib/libavcodec.a" "arm64"
check_arch "$BUILD_DIR/ios-sim-x86_64/lib/libavcodec.a" "x86_64"
check_arch "$BUILD_DIR/ios-simulator/lib/libavcodec.a" "arm64 x86_64"
check_arch "$BUILD_DIR/merged/ios/libffmpeg.a" "arm64"
check_arch "$BUILD_DIR/merged/sim/libffmpeg.a" "arm64 x86_64"

check_sym "$BUILD_DIR/merged/ios/libffmpeg.a" "avcodec_version"
check_sym "$BUILD_DIR/merged/ios/libffmpeg.a" "avformat_version"
check_sym "$BUILD_DIR/ios-arm64/lib/libavcodec.a" "avcodec_version"
check_sym "$BUILD_DIR/ios-arm64/lib/libavformat.a" "avformat_version"

for h in libavcodec/avcodec.h libavformat/avformat.h libavutil/avutil.h; do
  if [ ! -f "$BUILD_DIR/ios-arm64/include/$h" ]; then
    echo "FAIL: missing header $h" >&2
    fail=1
  else
    echo "ok: header $h"
  fi
done

if [ ! -f "$DIST_DIR/FFmpeg.xcframework/Info.plist" ]; then
  echo "FAIL: FFmpeg.xcframework missing" >&2
  fail=1
else
  echo "ok: FFmpeg.xcframework"
fi

exit $fail
