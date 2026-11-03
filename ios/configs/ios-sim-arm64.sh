# iOS simulator configuration (arm64, Apple Silicon hosts).
# Requires configs/common.sh first.
: "${IOS_DIR:?source configs/common.sh before this file}"
ARCH=arm64
SDK=iphonesimulator
MIN_FLAG="-mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
OUT_DIR="$BUILD_DIR/ios-sim-$ARCH"
