# Wallpaper store fixtures

Binary property lists in the shape of WallpaperAgent's store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`), for `WallpaperStoreTests`. One is a real store; the others are built from it by `make-stores.py`, which reads only the files here.

| File | Where it came from |
|---|---|
| `wallpaper-store-livepaper.plist` | A byte-for-byte copy of the development Mac's store, taken read-only on 2026-09-24 (macOS 27.0, one display, no per-Space wallpaper). Livepaper was last chosen in System Settings on 2026-09-23 (on-screen checks; nothing of Livepaper's wrote the store then, and the spike wrote `$null` where this has a blob), so both Desktop entries (`SystemDefault`, `AllSpacesAndDisplays`) are WallpaperAgent's own writing: provider `app.livepaper.Livepaper.WallpaperExtension`, configuration `livepaper`, `EncodedOptionValues` a 54-byte property list of an empty `values` dictionary. The Idle entries name the Aerial Wallper left in the store on 2026-09-21 (its asset slot's UUID). It holds no file path and no user name |
| `wallpaper-store-aerial.plist` | Built: the same store as it was before Livepaper, each Desktop entry naming that Aerial in the Idle entries' own form, with Wallper's dates. It is the 607-byte store the research note describes, give or take the order of keys |
| `wallpaper-store-idle-only.plist` | Built: the same store with its Desktop entries taken out |
| `wallpaper-store-spaces.plist` | Built, since no store with Spaces of their own exists on the development Mac: 24 Desktop entries across 11 Spaces, the count of the larger store the spike edited, which was not kept. The tree has the places that store and this one have (`SystemDefault`, `AllSpacesAndDisplays`, `Displays` by display UUID, `Spaces` by Space UUID each with `Default` and `Displays`, a `Type` in every place) and a few Idle entries inside Spaces. The entries are the real Aerial one and image choices: the image entries' `Files` are placeholders (two of macOS's own pictures and one under a made-up user), and their `Configuration` and `EncodedOptionValues` are stand-ins in the observed form, a binary property list; the edit carries them without reading them. The UUIDs are made up |

To build the three again: `python3 make-stores.py`.
