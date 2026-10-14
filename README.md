# My Kindle

An iPhone PDF reader that re-typesets books so they read like a Kindle.

Text-based PDFs are extracted, analysed and re-flowed with your own typeface, size
and theme. Anything that cannot be reflowed honestly — scanned pages, multi-column
layouts, tables — falls back to showing the original page, with pinch zoom and
rectangle highlights.

Everything is on-device. No account, no network, no analytics.

## Requirements

- macOS with **Xcode 16** or newer
- iOS 18.0+ (iPhone only)
- No third-party dependencies

## Build and run

```bash
open my_kindle.xcodeproj
```

Pick the **my_kindle** scheme and any iPhone simulator, then press Run. To run the
tests, press `⌘U`.

To build and test from the command line:

```bash
# Build
xcodebuild -project my_kindle.xcodeproj -scheme my_kindle \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Test
xcodebuild -project my_kindle.xcodeproj -scheme my_kindle \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Workflow

The loop is three commands. Edit code, regenerate the project, build.

```bash
python3 tools/genproj.py      # 1. after adding or removing files
python3 tools/checkproj.py    # 2. optional structural check
open my_kindle.xcodeproj      # 3. build and run
```

Step 1 matters because `my_kindle.xcodeproj` is **generated**, not hand-edited:
adding a file under `Sources/` or `Tests/` does nothing on its own until the
project is regenerated. This keeps the project file reproducible and free of merge
conflicts. The generator emits a classic (objectVersion 56) pbxproj, so the project
also opens in older Xcode versions and is parseable by fastlane and CocoaPods.

Because the project file is rebuilt from scratch, never make changes inside Xcode
that you need to keep — signing, bundle IDs and per-machine settings belong in
`Config/Local.xcconfig` (see below), which lives outside the generated project.

## Signing and bundle ID

Building for the **Simulator** needs no setup at all.

To run on a **physical device**, Apple requires a bundle ID registered to *your*
team. The shared `com.rafid.my_kindle` belongs to the upstream author, so you
cannot sign for it — the build fails with a provisioning error. Give yourself a
unique one:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Then edit `Config/Local.xcconfig`:

```
MY_KINDLE_BUNDLE_ID = com.yourname.my_kindle
DEVELOPMENT_TEAM    = ABCDE12345
```

Your Team ID is in Xcode ▸ Settings ▸ Accounts, or the **Team** picker under
target `my_kindle` ▸ Signing & Capabilities. A free personal Apple ID is enough
for a 7-day profile; a paid account lasts a year.

`Config/Local.xcconfig` is **gitignored**, so your Team ID never reaches the repo
and never appears in a commit. You only need it for device builds — a simulator
build works without the file existing.

Why an xcconfig and not Xcode's UI: `my_kindle.xcodeproj` is generated, so any
change you make to signing inside Xcode is silently overwritten the next time
someone runs `tools/genproj.py`. The `.xcconfig` sits outside the generated
project, so your overrides survive regeneration.

The test target derives its bundle ID automatically — override
`MY_KINDLE_BUNDLE_ID` once and both the app (`…my_kindle`) and the tests
(`…my_kindle.tests`) follow.

## Continuous integration

`.github/workflows/ios.yml` runs `xcodebuild build` and `xcodebuild test` on a
`macos-15` runner. Push to `main` (or open a pull request) and it will tell you
whether the project builds before you ever open Xcode.

## How it works

```
Import ──▶ PDFTextExtractor ──▶ LayoutAnalysis ──▶ ReflowBuilder ──▶ ReflowModel
              (lines + geometry)   (columns,        (one flat text      (cached to
                                   headers)         stream + runs)      Caches/)
                                                                         │
                                             ReflowTypography ◀────────┘
                                          (fonts, themes, images)
                                                    │
                                               Paginator
                                       (Core Text → page slices)
                                                    │
                                 ┌──────────────────┴──────────────────┐
                          ReflowPageView                        PDFPageUIView
                        (CTFrame, highlights,                (cached page image,
                         press-drag selection)                pinch, rect marks)
```

### Reflow, honestly

| Situation | What happens |
|---|---|
| Single-column text PDF | Re-typeset with your typeface and size |
| Scanned / image-only page | Inserted as an image block between the text |
| Two or more columns | That page is kept as an image |
| Running headers, footers, page numbers | Detected across the book and dropped |
| Table of contents | PDF outline mapped onto the reflow text |

If less than half the book reflows, the reader falls back to page-image mode on its
own. You can override either way from the `Aa` panel.

### Positions that survive restyling

Highlights and bookmarks are stored as **character offsets into the extracted
text**, not page numbers. Changing the font size rebuilds the layout but not the
text, so your highlights stay exactly where you left them. Each anchor also keeps a
quoted snippet as a safety net.

### Layout

```
Sources/
  App/        entry point, paths
  Models/     Book, Annotation, Locator, ReaderSettings
  Store/      JSON-backed library store
  Import/     file import and cover rendering
  Engine/     extraction, layout analysis, model, typography, pagination, rendering
  Reader/     reader screen, page views, sheets
  Export/     Markdown and annotated-PDF export
  Views/      library shelf, covers
Tests/        engine and store tests
Config/      shared build settings; per-machine Local.xcconfig is gitignored
tools/        project generator and checker
```

## Known limits

- No OCR: scanned books stay images until you read a text-based PDF version.
- No full-text search inside a book.
- No iCloud sync — the library lives on the device.
- Figures that sit inside a text page are not extracted; only whole pages are
  either re-flowed or shown as images.