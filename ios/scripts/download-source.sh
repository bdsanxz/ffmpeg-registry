#!/bin/sh -e
# Download the pinned FFmpeg source and verify its checksum.
. "$(dirname "$0")/../configs/common.sh"

TARBALL="ffmpeg-$FFMPEG_VERSION.tar.xz"
URL="https://ffmpeg.org/releases/$TARBALL"
EXPECTED="$(cut -d' ' -f1 "$IOS_DIR/SOURCE_SHA256")"

mkdir -p "$BUILD_DIR/src"
cd "$BUILD_DIR/src"

if [ ! -f "$TARBALL" ]; then
  curl -sL -o "$TARBALL" "$URL"
fi

ACTUAL="$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$EXPECTED" ]; then
  echo "checksum mismatch for $TARBALL" >&2
  echo "expected: $EXPECTED" >&2
  echo "actual:   $ACTUAL" >&2
  exit 1
fi

if [ ! -d "ffmpeg-$FFMPEG_VERSION" ]; then
  tar -xf "$TARBALL"
fi

echo "source ready: $SRC_DIR"
