#!/bin/sh -e
# Verify a built ffmpeg binary exposes the registry contract:
#  - libx265 with 10/12-bit pixel formats (multilib)
#  - volumedetect, loudnorm, eval filters
# Usage: scripts/verify-capabilities.sh [path-to-ffmpeg]
set -eu

FFMPEG="${1:-ffmpeg}"
# If relative path given, respect it; if not found, try in PATH
if [ ! -x "$FFMPEG" ]; then
    if ! command -v "$FFMPEG" >/dev/null 2>&1; then
        echo "FAIL: ffmpeg not found: $FFMPEG" >&2
        exit 1
    fi
fi

# Run once so output is available for multiple greps
VERSION_OUT="$( "$FFMPEG" -hide_banner -version 2>&1 || true)"
FILTERS_OUT="$( "$FFMPEG" -hide_banner -filters 2>&1 || true)"
ENCODER_OUT="$( "$FFMPEG" -hide_banner -h encoder=libx265 2>&1 || true)"

fail=0
check() {
    # $1 = description, $2 = haystack, $3 = needle
    desc="$1"
    hay="$2"
    needle="$3"
    if echo "$hay" | grep -Fq "$needle"; then
        echo "ok: $desc contains $needle"
    else
        echo "FAIL: $desc missing '$needle'" >&2
        fail=1
    fi
}

echo "--- ffmpeg -version ---"
echo "$VERSION_OUT" | head -n 2 | sed 's/^/  /'

# Note: libx265 must be present; if not, report FAIL (not silent)
if echo "$ENCODER_OUT" | grep -qi "libx265"; then
    echo "ok: encoder libx265 present"
else
    echo "FAIL: encoder libx265 not present" >&2
    fail=1
fi

# 10-bit multilib — the Sprint 25 gate
check "libx265 pixel formats (10-bit)" "$ENCODER_OUT" "yuv420p10le"
check "libx265 pixel formats (10-bit 422)" "$ENCODER_OUT" "yuv422p10le"
check "libx265 pixel formats (10-bit 444)" "$ENCODER_OUT" "yuv444p10le"
# 12-bit
check "libx265 pixel formats (12-bit)" "$ENCODER_OUT" "yuv420p12le"
check "libx265 pixel formats (12-bit 422)" "$ENCODER_OUT" "yuv422p12le"

# Filter capabilities
check "filters" "$FILTERS_OUT" "volumedetect"
check "filters" "$FILTERS_OUT" "loudnorm"
# eval evaluator is exposed as `aeval`/`aevalsrc` (libavutil/eval); check for aeval
if echo "$FILTERS_OUT" | grep -Ei "aeval" | grep -q "aeval"; then
    echo "ok: filters contains aeval (eval evaluator)"
else
    echo "FAIL: filters missing 'aeval' (eval evaluator)" >&2
    fail=1
fi

# libsoxr note (loudnorm quality); warn but do not fail if missing on Windows
if echo "$VERSION_OUT" | grep -q "libsoxr"; then
    echo "ok: --enable-libsoxr"
else
    echo "warn: --enable-libsoxr not found in -version (loudnorm precision reduced)" >&2
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL: capabilities verification failed for $FFMPEG" >&2
    echo "--- libx265 ---" >&2
    echo "$ENCODER_OUT" >&2 | head -n 80 >&2
    echo "--- filters (volumedetect/loudnorm/aeval) ---" >&2
    echo "$FILTERS_OUT" | grep -Ei "volumedetect|loudnorm|aeval" >&2 || true
    # full version for debugging
    echo "$VERSION_OUT" >&2
    exit 1
fi

echo "ok: all required capabilities present in $FFMPEG"
