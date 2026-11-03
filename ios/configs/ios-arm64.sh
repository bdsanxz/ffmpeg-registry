# iOS device configuration (arm64). Requires configs/common.sh first.
: "${IOS_DIR:?source configs/common.sh before this file}"
ARCH=arm64
SDK=iphoneos
MIN_FLAG="-mios-version-min=$IOS_DEPLOYMENT_TARGET"
OUT_DIR="$BUILD_DIR/ios-$ARCH"
