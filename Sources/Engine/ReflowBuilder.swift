import Foundation
import PDFKit
import CryptoKit

/// Turns a `PDFDocument` into a `ReflowModel`: one flat text stream, a table of runs
/// (font size, weight, source page) and a page → character offset map.
enum ReflowBuilder {

    static func build(document: PDFDocument, bookID: UUID, fingerprint: String, progress: ((Double) -> Void)? = nil) -> ReflowModel {
        let pages = PDFTextExtractor.extract(document: document) { done, total in
            progress?(total > 0 ? Double(done) / Double(total) : 0)
        }

        var model = ReflowModel(fingerprint: fingerprint)
        model.bookID = bookID
        model.chapters = chapters(from: document)
        model.pageStartOffsets = [Int](repeating: 0, count: max(document.pageCount, 1))

        let drop = LayoutAnalysis.headerFooterRuns(pages: pages)

        // Body size drives heading detection: a line much larger than the body is a heading.
        let bodySizes = pages.flatMap { page -> [Double] in
            page.runs.enumerated().compactMap { runIndex, run in
                drop.contains(PageRunKey(page: page.index, run: runIndex)) ? nil : run.size
            }
        }
        let bodySize = LayoutAnalysis.median(bodySizes) ?? 11

        var text = ""
        var runs: [ModelRun] = []
        var previousLeft: Double?
        var previousWasShort = false
        let total = max(pages.count, 1)
        var lastReported = 0

        for page in pages {
            if page.index < model.pageStartOffsets.count {
                model.pageStartOffsets[page.index] = (text as NSString).length
            }

            if page.kind != .text {
                // Not reflowable: insert a marker so the reader can drop the page image in.
                if !text.isEmpty { text += "\n" }
                let loc = (text as NSString).length
                text += "\u{FFFC}\n"
                runs.append(ModelRun(
                    loc: loc, len: 1, size: bodySize, bold: false, italic: false,
                    heading: false, paragraphStart: true, pageIndex: page.index, kind: .image
                ))
            } else {
                for (runIndex, run) in page.runs.enumerated() {
                    guard !drop.contains(PageRunKey(page: page.index, run: runIndex)) else { continue }
                    var cleaned = run.text.replacingOccurrences(of: "\u{00A0}", with: " ")
                    cleaned = cleaned.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    let isHeading = run.size > bodySize * 1.18
                    let left = run.rect.first ?? 0
                    let indentBreak = previousLeft.map { abs(left - $0) > 0.02 } ?? false
                    // A line that stops well short of the column usually ends a paragraph.
                    let paragraphStart = isHeading || indentBreak || previousWasShort || (text as NSString).length == 0

                    let lineWidth = run.rect.count >= 3 ? run.rect[2] : 1.0
                    previousWasShort = lineWidth < 0.62 && !isHeading
                    previousLeft = left

                    if (text as NSString).length > 0 { text += "\n" }
                    let loc = (text as NSString).length
                    text += cleaned
                    runs.append(ModelRun(
                        loc: loc, len: (cleaned as NSString).length, size: run.size,
                        bold: run.bold, italic: run.italic, heading: isHeading,
                        paragraphStart: paragraphStart, pageIndex: page.index, kind: .text
                    ))
                }
            }

            let percent = Int(Double(page.index + 1) / Double(total) * 20)
            if percent > lastReported {
                lastReported = percent
                progress?(Double(page.index + 1) / Double(total))
            }
        }

        model.text = text
        model.runs = runs
        model.pageStartOffsets.append((text as NSString).length)
        return model
    }

    static func fingerprint(for url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let payload = Data("\(url.lastPathComponent)|\(size)|\(modified)".utf8)
        return SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    static func chapters(from document: PDFDocument) -> [Chapter] {
        guard let root = document.outlineRoot else { return [] }
        var result: [Chapter] = []

        func walk(_ outline: PDFOutline, level: Int) {
            guard level <= 2, result.count < 500 else { return }
            let label = (outline.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var pageIndex = 0
            if let page = outline.destination?.page {
                pageIndex = document.index(for: page)
                if pageIndex < 0 { pageIndex = 0 }
            }
            if !label.isEmpty {
                result.append(Chapter(title: label, pageIndex: pageIndex, level: level))
            }
            if let children = outline.children {
                for child in children { walk(child, level: level + 1) }
            }
        }

        if let children = root.children, !(root.label ?? "").isEmpty {
            result.append(Chapter(title: root.label ?? "Contents", pageIndex: 0, level: 0))
            for child in children { walk(child, level: 1) }
        } else {
            walk(root, level: 0)
        }
        return result
    }
}