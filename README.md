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
designated => identifier "app.livepaper.Livepaper" and certificate leaf = H"4389775aa4a3dc7facd524a7d06bbae62f77fccf"
designated => identifier "app.livepaper.Livepaper.WallpaperExtension" and certificate leaf = H"4389775aa4a3dc7facd524a7d06bbae62f77fccf"
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
| `make notices` | Write the notices into `Resources/Credits.rtf`, and the signing requirement into this README |
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

[MIT](LICENSE). The ffmpeg helper is a separate program under the LGPL, built from source by `Helpers/ffmpeg/build.sh`; see `Helpers/ffmpeg/README.md`. The shader tools are separate programs under permissive licences, built from source by `Helpers/shader-tools/build.sh`; see `Helpers/shader-tools/README.md` and [NOTICE](NOTICE).
