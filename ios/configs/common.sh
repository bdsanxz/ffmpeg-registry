# Shared iOS build settings, sourced by configs/*.sh and scripts/*.sh.
#
# License profile: LGPL-compatible. No --enable-gpl, no external
# GPL/nonfree libraries. Hardware H.264/HEVC comes from VideoToolbox,
# audio from the native AAC encoder.

FFMPEG_VERSION="$(cat "$(dirname "$0")/../VERSION")"
IOS_DEPLOYMENT_TARGET=15.0

# Architectures built for devices and simulators.
ARCHS_DEVICE="arm64"
ARCHS_SIMULATOR="arm64 x86_64"

# Directory layout, relative to the ios/ directory.
IOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$IOS_DIR/build"
DIST_DIR="$IOS_DIR/dist"
SRC_DIR="$BUILD_DIR/src/ffmpeg-$FFMPEG_VERSION"
