# iOS builds

This directory builds the registry's iOS distribution: static FFmpeg
libraries for devices and simulators, merged into one `FFmpeg.xcframework`,
plus a native media-engine bridge (`ff_probe` / `ff_transcode`).

Published artifacts live in the repository's versioned releases:

- `FFmpeg.xcframework.zip`
- `ios-manifest.json`
- `ios-checksums.txt`

## Targets

| Slice                 | Arch    | SDK              |
| --------------------- | ------- | ---------------- |
| iOS device            | arm64   | iphoneos         |
| iOS simulator         | arm64   | iphonesimulator  |
| iOS simulator (Intel) | x86_64  | iphonesimulator  |

The pinned FFmpeg source (`VERSION`) is verified against `SOURCE_SHA256`
before every build.

## Layout

- `configs/` — one file per slice plus shared settings.
- `scripts/` — `download-source.sh`, `build-arch.sh`,
  `create-xcframework.sh`, `verify.sh`, `manifest.sh`.
- `native/` — C bridge (`ffmpeg_bridge.h`, `bridge.c`) and the Swift
  media-engine interface (`MediaEngine.swift`).

## Local build

```
./scripts/download-source.sh
./scripts/build-arch.sh ios-arm64
./scripts/build-arch.sh ios-sim-arm64
./scripts/build-arch.sh ios-sim-x86_64
./scripts/create-xcframework.sh
./scripts/verify.sh
./scripts/manifest.sh
```

Requires Xcode with the iPhoneOS and iPhoneSimulator SDKs.

## License profile

The default configuration is LGPL-compatible: no `--enable-gpl`, no
external GPL or nonfree libraries. Hardware H.264/HEVC comes from
VideoToolbox, audio from the native AAC encoder. The static libraries
link only against Apple system frameworks plus zlib/bzip2.

Distributors of the produced framework must still follow the FFmpeg
license rules: ship the applicable license notices, document the exact
source and configuration used, and evaluate the static-linking
obligations for their own integration. See <https://ffmpeg.org/legal.html>.
