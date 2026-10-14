# Inkwell

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
open Inkwell.xcodeproj
```

Pick the **Inkwell** scheme and any iPhone simulator, then press Run. To run the
tests, press `⌘U`.

To build from the command line:

```bash
xcodebuild -project Inkwell.xcodeproj -scheme Inkwell \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Adding or removing source files

`Inkwell.xcodeproj` is **generated**, not hand-edited. After adding a file under
`Sources/` or `Tests/`, regenerate it:

```bash
python3 tools/genproj.py
python3 tools/checkproj.py   # optional structural check
```

This keeps the project file reproducible and free of merge conflicts. The
generator emits a classic (objectVersion 56) pbxproj, so the project also opens in
older Xcode versions and is parseable by fastlane and CocoaPods.

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
tools/        project generator and checker
```

## Known limits

- No OCR: scanned books stay images until you read a text-based PDF version.
- No full-text search inside a book.
- No iCloud sync — the library lives on the device.
- Figures that sit inside a text page are not extracted; only whole pages are
  either re-flowed or shown as images.