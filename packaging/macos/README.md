# macOS app

The normal `macos-release` preset links FFmpeg and SDL from Homebrew by
absolute `/opt/homebrew` paths. That is useful for development, but the
resulting binary only starts on a Mac with the same Homebrew packages
installed.

Homebrew's libraries also require the macOS version they were built on
(currently 27), so they are not bundled. `build-app.sh` first runs
`build-deps.sh`, which downloads pinned, checksummed sources of FFmpeg, SDL3
and sdl2-compat and builds them for macOS 26 into `build/macos-deps/prefix`.
FFmpeg is cut down to MPEG-1/2 video decoding, which is all the cutscenes
need. The script then builds the game against those libraries with the
`macos-app` preset (`build/macos-app`), packages it into `ProjectCane.app`
and copies the libraries in. The app runs on Apple Silicon Macs with macOS 26
or newer.

The first run takes a few minutes to build the libraries; later runs reuse
them until a version in `build-deps.sh` changes.

## Requirements

- An Apple Silicon Mac (building on macOS 26 or newer)
- Xcode command line tools (`xcode-select --install`)
- Homebrew packages: `brew install cmake ninja pkgconf`
- For the `macos-release` development build only: `brew install ffmpeg sdl2-compat sdl3`

## Build

From the repository root:

```bash
packaging/macos/build-app.sh
```

The result is `dist/ProjectCane.app`. The script finishes by running
`packaging/macos/check-app.sh`, which fails if anything in the bundle still
loads a library from outside it, is not arm64, needs a newer macOS than the
bundle's `LSMinimumSystemVersion` (26.0), or is not signed. It can also be run
on its own:

```bash
packaging/macos/check-app.sh --require Contents/Frameworks/libSDL3.dylib dist/ProjectCane.app
```

## Running

Put the extracted `Worlds` and `Cutscenes` directories and
`extraction_manifest.json` in one of these places; the first one that has
`Worlds` is used:

1. `~/Library/Application Support/ProjectCane`
2. The folder that contains `ProjectCane.app`

To use another folder, start the game from Terminal with `--data-dir`:

```bash
dist/ProjectCane.app/Contents/MacOS/ProjectCane --data-dir /path/to/extracted-game
```

Saves and settings are kept in `~/Library/Application Support/ProjectCane`.

The app is signed ad hoc, not with a Developer ID, and is not notarised, so
macOS refuses to open a downloaded copy. Remove the quarantine flag once,
after moving the app to where it will stay:

```bash
xattr -dr com.apple.quarantine ProjectCane.app
```

Alternatively, try to open it once, then choose Open Anyway in System
Settings → Privacy & Security. While the flag is set and the app has not been
moved in Finder, macOS runs it from a temporary read-only copy, so data placed
beside the app is not found; use `~/Library/Application Support/ProjectCane`
in that case.

## File Extractor

`build-extractor-app.sh` packages the File Extractor (the .NET app that turns
a Sly 1 ISO into the `Worlds`, `Cutscenes` and `extraction_manifest.json` the
game reads) as `dist/ProjectCane File Extractor.app`. It also needs the .NET
SDK 9 or newer (<https://dotnet.microsoft.com/download>); the CMake step that
builds its two native tools uses the game's `macos-app` build, so it also
runs `build-deps.sh`.

```bash
packaging/macos/build-extractor-app.sh
```

Like the game's, the bundle is checked by `check-app.sh` before the script
reports success. To check it on its own:

```bash
packaging/macos/check-app.sh --require Contents/MacOS/Sly1BrxRebuilder \
    --require Contents/MacOS/Sly1PalExtractor "dist/ProjectCane File Extractor.app"
```

The app carries its own .NET runtime, so nothing else has to be installed to
run it. It extracts into `~/Library/Application Support/ProjectCane` by
default, where the game looks first; Change Folder picks another folder. Like
the game it is signed ad hoc and not notarised, so remove the quarantine flag
once after moving it to where it will stay:

```bash
xattr -dr com.apple.quarantine "ProjectCane File Extractor.app"
```
