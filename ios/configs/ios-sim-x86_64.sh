# iOS simulator configuration (x86_64, Intel hosts).
# Requires configs/common.sh first.
: "${IOS_DIR:?source configs/common.sh before this file}"
ARCH=x86_64
SDK=iphonesimulator
MIN_FLAG="-mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET"
OUT_DIR="$BUILD_DIR/ios-sim-$ARCH"
