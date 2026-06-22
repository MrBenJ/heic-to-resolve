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

## Install

Grab the latest `.app` from the [**Releases**](https://github.com/MrBenJ/heic-to-resolve/releases) page:

1. Download **`HEIC-to-Resolve.zip`** from the latest release's **Assets** and unzip it
   (double‑click in Finder).
2. Drag **HEIC to Resolve.app** into your `/Applications` folder.
3. The app is ad‑hoc signed (not notarized), so the first launch is blocked by Gatekeeper.
   **Right‑click the app → Open**, then confirm in the dialog. After that it opens normally.

### If macOS still won't open it

On recent macOS (Sequoia and later) the right‑click → Open bypass is sometimes refused with a
"developer cannot be verified" / "damaged" message. Strip the download quarantine and it'll launch:

```sh
xattr -cr "/Applications/HEIC to Resolve.app"
```

**Keep the quotes** — the app name has spaces, and without them the shell reads it as three separate
paths and silently clears nothing. (`-cr` clears all extended attributes, including the newer
`com.apple.provenance` flag that the narrower `-dr com.apple.quarantine` leaves behind.)

Then open it normally. (You can also approve it under **System Settings → Privacy & Security →
"Open Anyway"** right after the first blocked attempt.)

Prefer to build it yourself? See [Build from source](#build-from-source).

## Use it

1. Open **HEIC to Resolve**.
2. Pick your output depth — **8‑bit or 16‑bit** (defaults to 16‑bit; the choice is remembered).
3. **Drag one or more HEIC files onto the window.**
4. A spinner shows while it converts (the work runs off the main thread, so the UI stays live).
5. When it's done you get a ✓ and two buttons: **Show in Finder** and **Convert another**.

Each converted file is written **next to the original** as `<name>-resolve.png` — your originals are
never touched. You can also drop files onto the app's Dock/Finder icon.

Accepts `.heic`, `.heif`, `.png`, `.jpg`, `.tiff` — anything macOS can read.

## How it works

Conversion happens **in‑process** with Apple's ImageIO + Core Graphics — still zero third‑party
dependencies. Each image is read, drawn into an **sRGB** bitmap context (which performs the same
colorimetric match `sips --matchTo` does, converting Display P3 / PQ down to sRGB), and written
back out as a PNG.

Output is **sRGB** PNG, with a toggle for **8‑bit or 16‑bit** per channel — 16‑bit by default.
8‑bit produces smaller files; 16‑bit preserves more tonal precision for grading. (The earlier
`sips`‑based pipeline could only write 8‑bit; doing the conversion natively lets us choose the
bit depth.)

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
| `HEICToResolve.swift` | The SwiftUI app — window, drop handling, async ImageIO/Core Graphics conversion, UI states |
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
