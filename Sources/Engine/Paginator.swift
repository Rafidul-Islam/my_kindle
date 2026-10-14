import Foundation
import CoreText
import UIKit

/// A contiguous run of the book's text that fits on one screen.
struct PageSlice: Hashable, Sendable {
    var start: Int
    var length: Int

    var end: Int { start + length }
    var range: NSRange { NSRange(location: start, length: length) }
}

/// One entry in the reader's page model. Reflow pages point into the paginated text,
/// page-image pages point at a PDF page index.
enum PageContent: Hashable {
    case reflow(PageSlice)
    case pdf(Int)

    var pdfPageIndex: Int? {
        if case .pdf(let index) = self { return index }
        return nil
    }

    var reflowSlice: PageSlice? {
        if case .reflow(let slice) = self { return slice }
        return nil
    }

    /// Source PDF page, resolved from the first character of the page.
    var sourcePageIndex: Int? {
        if case .pdf(let index) = self { return index }
        return nil
    }
}

/// Lays text out into fixed-size pages using Core Text.
enum Paginator {

    static func paginate(_ attributed: NSAttributedString, textRect: CGRect, maxPages: Int = 5000) -> [PageSlice] {
        let total = attributed.length
        guard total > 0, textRect.width > 1, textRect.height > 1 else { return [] }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: textRect, transform: nil)

        var pages: [PageSlice] = []
        var location = 0

        while location < total && pages.count < maxPages {
            guard let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            ) else { break }

            let visible = CTFrameGetVisibleStringRange(frame)
            let advance = visible.length

            if advance <= 0 {
                // Nothing fits on this page (an oversized attachment or an unbreakable
                // run). Skip forward so we cannot loop forever.
                let forced = forceAdvance(attributed, from: location)
                guard forced > 0 else { break }
                pages.append(PageSlice(start: location, length: forced))
                location += forced
                continue
            }

            pages.append(PageSlice(start: location, length: advance))
            location += advance
        }

        return trimTrailingBlankPages(pages, in: attributed)
    }

    /// Drops trailing pages that contain nothing but whitespace, which would otherwise
    /// show up as blank screens at the end of a book.
    private static func trimTrailingBlankPages(_ pages: [PageSlice], in attributed: NSAttributedString) -> [PageSlice] {
        var result = pages
        while result.count > 1, let last = result.last {
            let text = (attributed.string as NSString).substring(with: NSRange(location: last.start, length: last.length))
            let hasAttachment = text.unicodeScalars.contains { $0.value == 0xFFFC }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty && !hasAttachment {
                result.removeLast()
            } else {
                break
            }
        }
        return result
    }

    private static func forceAdvance(_ attributed: NSAttributedString, from location: Int) -> Int {
        let string = attributed.string as NSString
        guard location < string.length else { return 0 }
        let window = NSRange(location: location, length: min(string.length - location, 1024))
        let newline = string.range(of: "\n", options: [], range: window)
        if newline.location != NSNotFound {
            return newline.location + 1 - location
        }
        return min(string.length - location, 256)
    }
}