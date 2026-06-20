# HEIC to Resolve

A tiny, native macOS app that converts iPhone/iPad **HEIC** photos into **sRGB PNG** files that
look correct when you drop them into **DaVinci Resolve** — no more oversaturated, blown-out, or
wrong‑looking stills.

## The problem it solves

Photos from a modern iPhone/iPad can come in as **wide‑gamut (Display P3)** and/or **HDR (PQ)** —
not plain sRGB. When you import one of those onto a standard **Rec.709** Resolve timeline, Resolve
interprets that P3/PQ tagging literally and the image can render oversaturated and wrong.

This app does one thing: it color‑matches each image to **sRGB** (which shares Rec.709 primaries),
so it drops into Resolve and just looks right.

## Download

Grab the latest `.app` from the [**Releases**](https://github.com/MrBenJ/heic-to-resolve/releases) page:

1. Download `HEIC-to-Resolve.zip` and unzip it.
2. Move **HEIC to Resolve.app** to your `/Applications` folder.
3. The app is ad‑hoc signed (not notarized), so the first time you launch it,
   **right‑click → Open** and confirm. After that it opens normally.

Prefer to build it yourself? See [Build from source](#build-from-source).

## Use it

1. Open **HEIC to Resolve**.
2. **Drag one or more HEIC files onto the window.**
3. A spinner shows while it converts (the work runs off the main thread, so the UI stays live).
4. When it's done you get a ✓ and two buttons: **Show in Finder** and **Convert another**.

Each converted file is written **next to the original** as `<name>-resolve.png` — your originals are
never touched. You can also drop files onto the app's Dock/Finder icon.

Accepts `.heic`, `.heif`, `.png`, `.jpg`, `.tiff` — anything macOS can read.

## How it works

Under the hood it runs Apple's built‑in `sips` per file — zero third‑party dependencies:

```sh
sips --matchTo '/System/Library/ColorSync/Profiles/sRGB Profile.icc' \
     -s format png "input.heic" --out "input-resolve.png"
```

Output is **sRGB, 8‑bit** PNG. (`sips` cannot write 16‑bit PNG — `--matchTo` downsamples to 8‑bit
and `bitsPerSample` is read‑only — and 8‑bit sRGB is the format that actually fixes the color
problem.)

## Build from source

No Xcode project needed — just the Swift toolchain from the macOS Command Line Tools:

```sh
git clone https://github.com/MrBenJ/heic-to-resolve.git
cd heic-to-resolve
./build.sh
open "build/HEIC to Resolve.app"      # try it
cp -R "build/HEIC to Resolve.app" /Applications/   # install it
```

### Project layout

| File | Purpose |
| --- | --- |
| `HEICToResolve.swift` | The SwiftUI app — window, drop handling, async `sips` conversion, UI states |
| `make-icon.swift` | Draws the app icon (AppKit) at 1024px |
| `Info.plist` | App bundle metadata |
| `build.sh` | Compiles, builds the icon, assembles + ad‑hoc signs the `.app` |
| `package.sh` | Runs `build.sh` and zips the `.app` for distribution |
| `.github/workflows/release.yml` | On a `v*` tag push: builds, packages, and publishes a GitHub Release |

### Cutting a release

Push a version tag and CI does the rest (builds on a macOS runner, attaches
`HEIC-to-Resolve.zip` to a generated release):

```sh
git tag v1.0.0
git push origin v1.0.0
```

To build the release artifact locally instead, run `./package.sh` — it produces
`build/HEIC-to-Resolve.zip`.

## Notes

- The app is **ad‑hoc code‑signed**, not notarized. On first launch from a download you may need to
  right‑click → **Open** once to get past Gatekeeper. Building locally avoids this.
- Color conversion is colorimetric (ICC `--matchTo`). For most stills this is exactly what you want;
  extreme HDR highlights are not tone‑mapped.

## License

[MIT](LICENSE) © 2026 Ben Junya
