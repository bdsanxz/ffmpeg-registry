# FFmpeg capability matrix

Registry builds are produced from a single [vcpkg](https://github.com/microsoft/vcpkg)
manifest ([`vcpkg.json`](vcpkg.json)) plus overlay port patches. The matrix below is
derived from that manifest and from the built binary's own `-version` / `-filters` /
`-h encoder` output. Verify any extracted asset with
[`scripts/verify-capabilities.sh`](scripts/verify-capabilities.sh)
(or the Windows equivalent, see below).

## x265 multilib (10-bit / 12-bit)

| Build                          | `libx265` present | 10-bit `yuv420p10le` / `yuv422p10le` / `yuv444p10le` / `gbrp10le` | 12-bit `yuv420p12le` … | Notes |
|--------------------------------|-------------------|------------------------------------------------------------------|------------------------|-------|
| macOS `arm64` (`arm64-osx`)    | ✅                | ✅ (`overlays/ports/x265` multilib)                            | ✅                     | Fixed in this change |
| macOS `x64` (`x64-osx`)        | ✅                | ✅                                                             | ✅                     | Same overlay |
| Linux `x64` (`x64-linux`)      | ✅                | ✅                                                             | ✅                     | Same overlay |
| Windows `x64` (`x64-windows`)  | ✅                | ✅                                                             | ✅                     | Same overlay (MSVC `lib.exe` merge) |
| Android `arm64-v8a`            | ✅                | ⚠️ 8-bit only (multilib pending)                               | ⚠️                     | Excluded: NDK `llvm-ar` merge yields `x265_10bit` undefined symbols — fallback to upstream 8-bit. To be fixed. |
| Android `x86_64`               | ✅                | ⚠️ 8-bit only                                                  | ⚠️                     | Same (excluded) |
| Windows `arm64` (planned)      | ❌ (excluded in `vcpkg.json`: `!(windows & arm64)`) | — | — | No `libx265`; use VideoToolbox/AMF/QSV |
| iOS (`FFmpeg.xcframework`)     | ❌                | —                                                              | —                      | Intentionally LGPL (`--disable-gpl`, no `--enable-libx265`); HEVC via `hevc_videotoolbox` |

Upstream vcpkg builds x265 8-bit only (`HIGH_BIT_DEPTH=OFF`), so `ffmpeg -h encoder=libx265`
lists only `yuv420p/yuvj420p/yuv422p/gbrp/gray8` and `-pix_fmt yuv420p10le` silently
downgrades to `yuv420p`. The overlay [`overlays/ports/x265/`](overlays/ports/x265/) builds
the canonical 8+10+12-bit multilib (`build/linux/multilib.sh`) and merges the three static
archives into one `libx265`/`x265-static.lib`. After the fix, `libx265` reports the `10`
and `12` variants and `x265_api_get(10)` / `x265_api_get(12)` succeed.

Check:

```sh
ffmpeg -hide_banner -h encoder=libx265
# should list yuv420p10le, yuv422p10le, yuv444p10le, gray10, yuv420p12le, yuv422p12le, yuv444p12le, gray12
ffmpeg -hide_banner -h encoder=libx265 2>&1 | grep -E "yuv420p10le|yuv420p12le"
ffmpeg -hide_banner -filters | grep -E "volumedetect|loudnorm|aeval"
```

## Filter / decoder matrix

All registry FFmpeg builds enable `avfilter`, `avcodec`, `avformat`, `swresample`,
`swscale`, `soxr` and `gpl/nonfree` from the manifest, so the following are present on
every leg below unless a platform `supports` excludes them (none of these three are
excluded).

| Capability | Filter / API | Present on macOS / Linux / Windows / Android | Notes |
|------------|--------------|----------------------------------------------|-------|
| `volumedetect` | `volumedetect` (video) `volumedetect` (audio alias) | ✅ | `ffmpeg -filters | grep volumedetect`; uses `libavfilter` only, no external dep. `ffmpeg -i in -vn -af volumedetect -f null -` |
| `loudnorm` | `loudnorm` (audio) | ✅ | `ffmpeg -filters | grep loudnorm`; requires `libsoxr` for high-quality resampling — enabled via `soxr` feature. `ffmpeg -i in -vn -af loudnorm=print_format=json -f null -` |
| `eval` (expression) | `eval`/`aeval` (libavutil evaluator) + `aeval`/`aevalsrc` | ✅ | `ffmpeg -filters | grep aeval` and `ffmpeg -h filter=aeval`; `libavutil/eval` evaluates `PI`, `E`, `N`, `T`, `t`. Always present when `avfilter` is enabled (IEEE-754 double). Distinct from the removed `eval` video filter name; check is `aeval`. |

### Subtleties

* **loudnorm + soxr**: Without `libsoxr`, loudnorm still runs but uses the built-in
  resampler with lower precision. Registry enables `soxr`, so verification should show
  `--enable-libsoxr` in `ffmpeg -version`.
* **volumedetect** is sample-accurate regardless of `swresample` configuration.
* **eval / `aeval`** exposes `PI`, `E` and the `N`, `T`, `t` constants (libavutil `eval.c`); no platform divergence.

## SPDX / License

Registry builds are GPL (`gpl` + `nonfree` from the manifest) → `--enable-gpl
--enable-nonfree` in the configure line. iOS is LGPL (`--disable-gpl`, `-- Taken from
`ios/configs/common.sh`) and omits x265/x264.

## Verifying a build

```sh
# Unix (macOS/Linux/Android host for checking local ffmpeg)
scripts/verify-capabilities.sh ./ffmpeg

# Windows (PowerShell, checks ffmpeg.exe in current directory)
powershell -ExecutionPolicy Bypass -File scripts/verify-capabilities.ps1 -FFmpegPath .\ffmpeg.exe
```

The script exits non-zero and prints `FAIL:` lines when a required capability is missing.
The CI job runs the same checks after `vcpkg install` so a regression fails the build
instead of shipping a downgrade.

CI gate reference for Framesmith Sprint 25 (Windows/Linux): use `ffmpeg-x64-windows.zip`
and `ffmpeg-x64-linux.zip` after this fix; they now advertise 10-bit x265. Re-pin to a
registry tag ≥ the first release that includes `overlays/ports/x265`.
