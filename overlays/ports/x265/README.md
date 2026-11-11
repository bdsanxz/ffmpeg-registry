Override of upstream vcpkg:x265 to build a multilib static library.

Upstream vcpkg builds x265 with the default 8-bit configuration only
(`HIGH_BIT_DEPTH=OFF`), so FFmpeg's `libx265` wrapper reports only
8-bit pixel formats (`yuv420p`). 10/12-bit HEVC encoding via
`-pix_fmt yuv420p10le` then silently downgrades to 8-bit.

This overlay builds the canonical x265 multilib (8 + 10 + 12 bit) as
produced by `build/linux/multilib.sh` / `build/vc18/multilib.bat`:

* 12-bit: `-DHIGH_BIT_DEPTH=ON -DMAIN12=ON -DEXPORT_C_API=OFF`
* 10-bit: `-DHIGH_BIT_DEPTH=ON -DEXPORT_C_API=OFF`
* 8-bit : `-DEXTRA_LIB=<10bit>;<12bit> -DLINKED_10BIT=ON -DLINKED_12BIT=ON`

and merges the three static archives into a single `libx265` (or
`x265-static.lib` on Windows). FFmpeg detects the full multilib via
`x265_api_get(10)` / `x265_api_get(12)` and advertises
`yuv420p10le` / `yuv420p12le` (and related 422/444/RGB variants) on
`libx265`.

Applies to static linkage only (the registry's triplets). Dynamic
linkage falls back to the upstream single-build behaviour.

Windows merge uses `lib.exe`, macOS uses `libtool -static`, other
Unix uses `ar rcs`.

Patches are vendored from upstream vcpkg (see portfile.cmake).
