#!/bin/sh -e
# Write the distribution manifest and checksums.
. "$(dirname "$0")/../configs/common.sh"

mkdir -p "$DIST_DIR"
cd "$DIST_DIR"

shasum -a 256 FFmpeg.xcframework.zip > ios-checksums.txt

cat > ios-manifest.json <<EOF
{
  "version": "$FFMPEG_VERSION",
  "platform": "ios",
  "license_profile": "lgpl",
  "minimumOSVersion": "$IOS_DEPLOYMENT_TARGET",
  "architectures": [
    "ios-arm64",
    "ios-simulator-arm64",
    "ios-simulator-x86_64"
  ],
  "artifacts": {
    "ffmpeg": {
      "url": "FFmpeg.xcframework.zip",
      "checksum": "SHA256:$(cut -d' ' -f1 ios-checksums.txt)"
    }
  }
}
EOF

echo "manifest ready: $DIST_DIR/ios-manifest.json"
