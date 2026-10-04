# Livepaper

Live wallpapers for macOS. Give it a video or a Wallpaper Engine scene and it becomes your wallpaper, on the desktop and the lock screen. Free, open source, no account of its own, no marketplace, no telemetry. To get items from Wallpaper Engine's Workshop, it can sign in to your own Steam account.

## Installing

1. Download `Livepaper-<version>.dmg` from the [latest release](https://github.com/oTerminal/Livepaper/releases/latest) and open it.
2. Drag Livepaper to the Applications folder, then open it from there. Opened from the disk image, Livepaper asks for the drag and starts nothing.
3. macOS says Apple could not verify that Livepaper is free of malware. Click **Done**.
4. Open **System Settings → Privacy & Security**. Under Security it says "Livepaper" was blocked to protect your Mac: click **Open Anyway**, enter your password, then click **Open Anyway** in the dialog that follows.

That is all. No Terminal step is needed, and none is safe to copy from elsewhere: do not remove the quarantine attribute with `xattr`. macOS asks once; updates do not ask again.

### Why macOS asks

Livepaper is not notarized. Notarization needs a paid Apple Developer account, which this project does not have. Each release is signed instead with the project's own self-signed certificate, so that every version is the same app to macOS, and Gatekeeper asks for the one Open Anyway.

To check that a copy is the project's, compare its designated requirement with the one every release keeps:

```sh
codesign -d -r- /Applications/Livepaper.app
codesign -d -r- /Applications/Livepaper.app/Contents/Extensions/WallpaperExtension.appex
```

<!-- requirement: made by `make notices` from Tools/release/designated-requirement.txt; edit that, not this -->
```text
Not made yet: Tools/release/make-cert.sh records it with the certificate, before the first release.
```
<!-- /requirement -->

Livepaper is not in Homebrew, and these steps do not rely on it.

### Updates

Livepaper checks for an update once a day, through [Sparkle](https://sparkle-project.org), and downloads and installs one only when you click for it; **Check for Updates…** is in the menu-bar item's menu (Control-click it) and in the app menu. Every update is signed with the project's EdDSA key, which Sparkle checks before it installs anything. The check sends nothing about your Mac.

## Requirements

- macOS 26 or later, Apple Silicon
- To build: Xcode 26 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), [SwiftLint](https://github.com/realm/SwiftLint)

## Building

```sh
brew install xcodegen swiftlint
make            # generate the Xcode project, lint, test, build
```

`make gen` writes `Livepaper.xcodeproj` from `project.yml`; the project file is not checked in. Open it in Xcode after generating.

| Command | Does |
|---|---|
| `make gen` | Generate the Xcode project |
| `make lint` | SwiftLint, including the design rules |
| `make test` | Swift Testing suites in both packages and the release tools |
| `make build` | Build the app, the Gallery and the CLI |
| `make ffmpeg` | Build the ffmpeg helper from source (`Helpers/ffmpeg/`). The import tests that convert WebM, MKV, AVI, WMV and GIF are skipped without it |
| `make notices` | Write the notices into `Resources/Credits.rtf` and this README, from what ships |
| `make release-dry-run` | Every release step but publishing, ad-hoc signed, into `build/release/` (`Tools/release/README.md`) |
| `make shader-tools` | Build the shader tools, glslang and SPIRV-Cross, from source (`Helpers/shader-tools/`). Import uses them to translate a scene's shaders to Metal, and the tests that translate shaders are skipped without them |

## Layout

| Path | Holds |
|---|---|
| `App/` | The menu-bar app |
| `Gallery/` | Every design-system component in isolation, for review |
| `CLI/` | The `livepaper` command-line tool |
| `Packages/LivepaperKit/` | Core models and rules, import, scenes, playback, system services, the Workshop |
| `Packages/DesignSystem/` | Tokens and components |
| `Helpers/ffmpeg/` | Build script, licences and notes for the bundled LGPL ffmpeg helper |
| `Helpers/shader-tools/` | Build script, licences and notes for the bundled shader tools |
| `Tools/release/` | Signing, the disk image, the appcast and the release workflow's scripts |

## License

[MIT](LICENSE). The notices below are the ones the app's About panel shows and the disk image's `Licenses` folder holds, with the licence texts:

<!-- notices: made by `make notices` from what ships; edit Tools/release/Sources/ReleaseKit/Notices.swift, not this -->
```text
Livepaper is free software under the MIT License. Copyright (c) 2026 Livepaper
contributors.

It includes, or ships beside it, the work below. The licence texts are in the
Licenses folder on the disk image and in the source repository.

Phosphene, commit 8b5bd57
  https://github.com/kageroumado/phosphene
  MIT License. Copyright (c) 2026 kageroumado. The wallpaper extension adapts
  code from it; NOTICE lists the files.

Sparkle 2.10.0
  https://sparkle-project.org
  MIT License, with the notices of the code it includes. It checks for and
  installs Livepaper's updates.

ffmpeg 9.0.2, the import helper
  https://ffmpeg.org
  GNU Lesser General Public License, version 2.1 or later. A separate program,
  Livepaper.app/Contents/MacOS/ffmpeg, that converts WebM, MKV, AVI, WMV and GIF
  files at import. Built without GPL or non-free parts and without network
  support, from this source archive:
    https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz
    sha256 8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
  This release of Livepaper carries a copy of that archive, with the build
  script and the configure line:
    https://github.com/oTerminal/Livepaper/releases/download/v0.1.0/ffmpeg-9.0.2.tar.xz
  To run your own ffmpeg build instead of this one:
    defaults write app.livepaper.Livepaper FFmpegReplacement /path/to/ffmpeg
  and to go back to this one:
    defaults delete app.livepaper.Livepaper FFmpegReplacement

glslang 16.6.0, a shader tool
  https://github.com/KhronosGroup/glslang
  BSD-3-Clause, with BSD-2-Clause, Apache-2.0 and MIT for some files, NVIDIA's
  licence for the preprocessor, and GPL-3.0-or-later with the Bison exception
  2.2 for its generated parser. A separate program that translates a scene's
  shaders at import.

SPIRV-Cross vulkan-sdk-1.4.357.0, a shader tool
  https://github.com/KhronosGroup/SPIRV-Cross
  Apache-2.0; the SPIR-V headers it compiles in are MIT and Khronos's free-use
  licence. A separate program that translates a scene's shaders at import.

The sample wallpapers
  Autumn Stream: "Autumn Leaves in River Water" by Free Nature Stock, CC0 1.0
    https://freenaturestock.com/video/autumn-leaves-in-river-water/
  Golden Maple: "Clouds Above a Maple Tree" by Free Nature Stock, CC0 1.0
    https://freenaturestock.com/video/clouds-above-a-maple-tree/
  Tall Grass: "Tall Grass Blowing in the Wind" by Free Nature Stock, CC0 1.0
    https://freenaturestock.com/video/tall-grass-blowing-in-the-wind/
  Cut from the videos above. CC0 1.0 is a public-domain dedication:
  https://creativecommons.org/publicdomain/zero/1.0/
```
<!-- /notices -->

The ffmpeg helper is a separate program under the LGPL, built from source by `Helpers/ffmpeg/build.sh`; see `Helpers/ffmpeg/README.md`. The shader tools are separate programs under permissive licences, built from source by `Helpers/shader-tools/build.sh`; see `Helpers/shader-tools/README.md` and [NOTICE](NOTICE).
