import Foundation
import PDFKit
import UIKit

/// One line of text found on a PDF page, with its box in PDF page coordinates.
struct LineBox {
    var text: String
    var rect: CGRect
    var pageWidth: CGFloat
    var pageHeight: CGFloat
}

/// How a page should be treated. Anything that isn't `.text` is rendered as an image,
/// because mangling columns or scanned pages would be worse than showing them as-is.
enum PageKind: String, Codable, Sendable {
    case text
    case imageOnly
    case complex
}

struct ExtractedRun: Codable, Sendable {
    var text: String
    /// Estimated font size in PDF points.
    var size: Double
    var bold: Bool
    var italic: Bool
    /// Normalised geometry: x, yTop, width, height. `yTop` is a fraction from the top.
    var rect: [Double]
}

struct ExtractedPage: Codable, Sendable {
    var index: Int
    var kind: PageKind
    var runs: [ExtractedRun]
    var width: Double
    var height: Double
}

/// Pulls text, geometry and font hints out of a `PDFDocument`.
///
/// PDFKit's `attributedString` frequently collapses everything on a page into a single
/// run with a wrong font, so we always keep a geometry-derived estimate as a fallback.
enum PDFTextExtractor {

    static func extract(document: PDFDocument, progress: ((Int, Int) -> Void)? = nil) -> [ExtractedPage] {
        var pages: [ExtractedPage] = []
        pages.reserveCapacity(document.pageCount)
        for index in 0..<document.pageCount {
            if let page = document.page(at: index) {
                pages.append(extract(page: page, index: index))
            }
            progress?(index + 1, document.pageCount)
        }
        return pages
    }

    static func extract(page: PDFPage, index: Int) -> ExtractedPage {
        let box = page.bounds(for: .cropBox)
        let width = abs(box.width)
        let height = abs(box.height)
        let size = CGSize(width: width, height: height)

        guard width > 1, height > 1, let pageSelection = page.selection(for: box) else {
            return ExtractedPage(index: index, kind: .imageOnly, runs: [], width: Double(width), height: Double(height))
        }

        var lines: [LineBox] = []
        for selection in pageSelection.selectionsByLine() {
            guard let raw = selection.string else { continue }
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let rect = selection.bounds(for: page)
            guard rect.width > 0.5, rect.height > 0.5, rect.width.isFinite, rect.height.isFinite else { continue }
            lines.append(LineBox(text: text, rect: rect, pageWidth: width, pageHeight: height))
        }

        guard !lines.isEmpty else {
            return ExtractedPage(index: index, kind: .imageOnly, runs: [], width: Double(width), height: Double(height))
        }

        let multiColumn = LayoutAnalysis.isMultiColumn(lines)
        let fontMapper = FontMapper(page: page, lineTexts: lines.map(\.text))
        let bodyHeight = LayoutAnalysis.medianLineHeight(lines)

        var runs: [ExtractedRun] = []
        runs.reserveCapacity(lines.count)
        for (lineIndex, line) in lines.enumerated() {
            let estimated = estimatedFontSize(for: line)
            let mapped = fontMapper.trustsMapper ? fontMapper.info(atLine: lineIndex) : nil
            let fontSize = mapped?.size ?? estimated

            let minX = Double(line.rect.minX / width)
            let yTop = Double(1.0 - line.rect.maxY / height)
            let w = Double(line.rect.width / width)
            let h = Double(line.rect.height / height)

            runs.append(ExtractedRun(
                text: line.text,
                size: fontSize,
                bold: mapped?.bold ?? false,
                italic: mapped?.italic ?? false,
                rect: [minX, yTop, w, h]
            ))
        }

        // A page whose body text is drastically smaller than its lines is usually
        // footers and stray glyphs; treat a near-empty text page as an image page.
        let meaningful = runs.filter { $0.text.count >= 2 }
        if meaningful.count < 3 && bodyHeight > 0 {
            return ExtractedPage(index: index, kind: .imageOnly, runs: [], width: Double(width), height: Double(height))
        }

        return ExtractedPage(
            index: index,
            kind: multiColumn ? .complex : .text,
            runs: runs,
            width: Double(width),
            height: Double(height)
        )
    }

    /// Glyph boxes are roughly 0.72em tall for body text; good enough for a relative size.
    private static func estimatedFontSize(for line: LineBox) -> Double {
        let value = Double(line.rect.height) / 0.72
        return min(max(value, 5), 96)
    }
}

/// Pulls per-line font information out of `PDFPage.attributedString` by matching its
/// text against the lines PDFKit reports, which preserves reading order.
private struct FontMapper {

    struct Info {
        var size: Double
        var bold: Bool
        var italic: Bool
    }

    private let infos: [Info?]
    let trustsMapper: Bool

    init(page: PDFPage, lineTexts: [String]) {
        guard let attributed = page.attributedString, attributed.length > 0 else {
            infos = Array(repeating: nil, count: lineTexts.count)
            trustsMapper = false
            return
        }

        var spans: [(start: Int, length: Int, info: Info)] = []
        var distinctSizes = Set<String>()
        let full = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.font, in: full) { value, range, _ in
            let font = value as? UIFont ?? UIFont.systemFont(ofSize: 12)
            let traits = font.fontDescriptor.symbolicTraits
            let info = Info(
                size: Double(font.pointSize),
                bold: traits.contains(.traitBold),
                italic: traits.contains(.traitItalic)
            )
            distinctSizes.insert(String(format: "%.2f", font.pointSize))
            spans.append((range.location, range.length, info))
        }

        trustsMapper = distinctSizes.count > 1

        if !trustsMapper {
            infos = Array(repeating: nil, count: lineTexts.count)
            return
        }

        let flat = attributed.string as NSString
        var cursor = 0
        var resolved: [Info?] = []
        resolved.reserveCapacity(lineTexts.count)

        for lineText in lineTexts {
            let needle = lineText as NSString
            var location = NSNotFound
            if needle.length > 0 {
                let searchStart = min(cursor, max(0, flat.length - 1))
                let searchRange = NSRange(location: searchStart, length: flat.length - searchStart)
                location = flat.range(of: needle as String, options: [], range: searchRange).location
                if location == NSNotFound {
                    location = flat.range(of: needle as String, options: [], range: NSRange(location: 0, length: flat.length)).location
                }
            }

            if location == NSNotFound || location + needle.length <= cursor || needle.length == 0 {
                resolved.append(nil)
            } else {
                let probe = location + needle.length / 2
                resolved.append(Self.info(spans: spans, at: probe))
                cursor = location + needle.length
            }
        }
        infos = resolved
    }

    func info(atLine index: Int) -> Info? {
        guard index >= 0, index < infos.count else { return nil }
        return infos[index]
    }

    private static func info(spans: [(start: Int, length: Int, info: Info)], at offset: Int) -> Info? {
        for span in spans {
            if offset >= span.start && offset < span.start + span.length {
                return span.info
            }
        }
        return spans.first?.info
    }
}