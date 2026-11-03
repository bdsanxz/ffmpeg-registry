#!/bin/sh -e
# Merge the per-architecture static libraries into FFmpeg.xcframework.
# Steps: lipo the simulator slices into one simulator library per
# module, combine each platform's modules into a single archive with
# libtool (one -library entry per platform), then create the framework.
. "$(dirname "$0")/../configs/common.sh"

LIBS="avcodec avformat avutil avfilter avdevice swscale swresample"
DEVICE_DIR="$BUILD_DIR/ios-arm64"
SIM_DIR="$BUILD_DIR/ios-simulator"
MERGED_DIR="$BUILD_DIR/merged"
HEADERS="$DEVICE_DIR/include"

rm -rf "$MERGED_DIR" "$DIST_DIR/FFmpeg.xcframework" "$DIST_DIR/FFmpeg.xcframework.zip"
mkdir -p "$DIST_DIR" "$SIM_DIR/lib" "$MERGED_DIR/ios" "$MERGED_DIR/sim"

for lib in $LIBS; do
  lipo -create \
    "$BUILD_DIR/ios-sim-arm64/lib/lib${lib}.a" \
    "$BUILD_DIR/ios-sim-x86_64/lib/lib${lib}.a" \
    -output "$SIM_DIR/lib/lib${lib}.a"
done

collect() {
  # $1 = source dir, $2 = output archive
  src=$1
  out=$2
  set --
  for lib in $LIBS; do
    set -- "$@" "$src/lib${lib}.a"
  done
  libtool -static -o "$out" "$@"
}

collect "$DEVICE_DIR/lib" "$MERGED_DIR/ios/libffmpeg.a"
collect "$SIM_DIR/lib" "$MERGED_DIR/sim/libffmpeg.a"

xcodebuild -create-xcframework \
  -library "$MERGED_DIR/ios/libffmpeg.a" -headers "$HEADERS" \
  -library "$MERGED_DIR/sim/libffmpeg.a" -headers "$HEADERS" \
  -output "$DIST_DIR/FFmpeg.xcframework"
cd "$DIST_DIR" && zip -qr FFmpeg.xcframework.zip FFmpeg.xcframework
echo "xcframework ready: $DIST_DIR/FFmpeg.xcframework.zip"
