# ffmpeg-registry

**ffmpeg-registry** is an automation workflow that produces static builds of
[FFmpeg](https://ffmpeg.org) for an array of different platforms.
Ready-to-download assets for each target live in the
[releases](https://github.com/bdsanxz/ffmpeg-registry/releases) of this
repository. Builds are performed using [vcpkg](https://github.com/microsoft/vcpkg).

Currently supported targets:

|                            | macOS | Windows | Linux   | Android            |
| -------------------------- | ----- | ------- | ------- | ------------------ |
| `arm64` / `aarch64`        | ✅    | planned | planned | planned (`arm64-v8a`) |
| `arm`                      | ❌    | —       | —       | planned (`armeabi-v7a`) |
| `x64` / `x86_64` / `amd64` | ✅    | ✅      | ✅      | planned            |
| `x86` / `i386`             | ❌    | planned | planned | planned            |

Windows, Linux, and Android legs follow the same matrix shape (see the
commented rows in `.github/workflows/main.yml`) and are added when
needed. Triplets and dependency scripts for those platforms are
already in the repo.

## Download

- **[Latest version](https://github.com/bdsanxz/ffmpeg-registry/releases/latest)**
- [All versions](https://github.com/bdsanxz/ffmpeg-registry/releases)

To programmatically fetch a specific release, use the following URL pattern:

```
https://github.com/bdsanxz/ffmpeg-registry/releases/download/${VERSION}/ffmpeg-${OS}-${ARCH}.zip
```

Each archive carries `ffmpeg` (plus `ffprobe`/`ffplay` where the platform
builds them) at the top level. Consumers should verify the
publisher-reported archive digest from the release metadata, then verify
the extracted binary (`-version` plus required encoders) before
executing it. No terms apply to these binaries beyond their own
open-source licenses.

## How a release is made

1. The monthly schedule (or a manual dispatch) compares the FFmpeg
   version in vcpkg master against the newest release tag.
2. When a newer version exists, every matrix leg builds FFmpeg through
   vcpkg with the matching overlay triplet and uploads `tools/ffmpeg/`
   as a workflow artifact.
3. A release tagged with the FFmpeg version is created and each leg is
   zipped as `ffmpeg-${OS}-${ARCH}.zip` and attached to it.

## License

GPL-3.0-only. See [LICENSE](LICENSE).
