# The ffmpeg helper

AVFoundation cannot open WebM, MKV, AVI or WMV. At import, Livepaper converts those files, and GIFs, to HEVC once, with an ffmpeg binary that ships inside the app and runs as a separate process. Playback never involves it.

`build.sh` builds that binary from source. Nothing here is downloaded as a binary.

## What is in the build

- One static `ffmpeg` for macOS arm64. It links only system libraries and frameworks.
- Demuxers for Matroska/WebM, AVI, ASF/WMV, GIF and MOV. Decoders for the codecs those containers usually carry. The decoders are ffmpeg's own; there are no external libraries.
- Two encoders: `hevc_videotoolbox` (Apple's encoder, through VideoToolbox) and ffmpeg's AAC. One output format: MOV/MP4.
- Two protocols: `file` and `pipe`. Network support is compiled out, so the helper cannot open a URL whatever a file asks for.
- No AV1. ffmpeg's own AV1 decoder only drives hardware decoders, and the software ones are external libraries.

The lists are at the top of `build.sh`. The binary is about 8 MB.

## Why LGPL only

Livepaper is MIT. ffmpeg is LGPL 2.1 or later unless it is configured with `--enable-gpl`, `--enable-version3` or `--enable-nonfree`, and this build uses none of them. That rules out x264, x265 and a few filters, none of which the import needs: the encoder is VideoToolbox.

An MIT app can ship an LGPL program next to it on three conditions, and the build is arranged around them:

- The helper is a separate executable. The app starts it as a process and links none of its code.
- The exact source, the build script and the licence texts are published with the binary.
- The user can replace the binary with their own build. See below.

`build.sh` checks the result before it installs it. It fails if the configuration mentions GPL, version 3 or non-free, if `ffmpeg -L` reports anything but the LGPL, if any protocol other than `file` and `pipe` is present, or if the binary links anything outside `/usr/lib` and `/System/Library`.

## Rebuilding

```
make ffmpeg
```

This needs an Apple silicon Mac with Xcode, and nothing else. The script uses only the system toolchain, so Homebrew cannot leak into the binary. It downloads `ffmpeg-<version>.tar.xz` from ffmpeg.org into `src/`, refuses to go on if the sha256 is not the pinned one, builds out of tree, and writes `out/`:

| File | What |
|---|---|
| `ffmpeg` | The binary |
| `ffmpeg-<version>.tar.xz` | The exact source archive it was built from |
| `BUILD-INFO.txt` | Version, sha256, the full configure line, and what the binary reports about itself |
| `build.sh`, `licenses/` | The script and the licence texts |

`src/` and `out/` are ignored by git. A second run with the same version and flags checks the binary again and stops. A full build takes about a minute on a recent Mac.

To move to a new ffmpeg release, change `FFMPEG_VERSION` and `FFMPEG_SHA256` in `build.sh`. Check the new sha256 against a second source first: the `.asc` signature next to the archive on ffmpeg.org (release key `FCF9 86EA 15E6 E293 A564 4F10 B432 2F04 D676 58D8`), or the hash Homebrew's formula pins. If the release changed `COPYING.LGPLv2.1` or `LICENSE.md`, the script stops and says so; copy the new text into `licenses/`, read what changed, and commit it.

## Replacing the binary

The LGPL gives the user the right to run a modified ffmpeg in place of ours. Livepaper looks for a replacement first: if the user has pointed it at an ffmpeg of their own, `FFmpegTool` runs that one and ignores the bundled copy. Any build works if it has the decoders for the files being imported, `hevc_videotoolbox`, the AAC encoder and the MOV muxer. Building this directory with different flags is the short way to get one.

## Where CI publishes it

The `ffmpeg` job in `.github/workflows/ci.yml` runs `make ffmpeg` on every pull request and every push to `master`, and uploads the whole of `out/` as the artefact `ffmpeg-helper-arm64`: binary, source archive, `BUILD-INFO.txt`, `build.sh` and licence texts together. The `check` job downloads that artefact and runs the import tests against it, with `LIVEPAPER_REQUIRE_FFMPEG=1` so that a missing helper fails the tests.

Each release carries the same files next to the app: `ffmpeg-helper-arm64.zip`, which is this artefact, and the source archive on its own, which the notices link to (`Tools/release/README.md`).
