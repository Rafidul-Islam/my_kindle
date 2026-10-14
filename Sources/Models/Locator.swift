import Foundation

/// Where an annotation / bookmark lives inside a book.
///
/// Positions are stored in a way that survives restyling: in reflow mode we keep a
/// character offset into the book's stable extracted text (font size and theme never
/// change the text, only its attributes), plus a quoted snippet as a safety net.
/// In page-image mode we keep a normalised rectangle on a PDF page.
enum Locator: Codable, Hashable, Sendable {
    case reflow(charOffset: Int, length: Int, quote: String?)
    case pdfRect(pageIndex: Int, rect: [Double])

    var charOffset: Int? {
        if case .reflow(let offset, _, _) = self { return offset }
        return nil
    }

    var pdfPageIndex: Int? {
        if case .pdfRect(let page, _) = self { return page }
        return nil
    }

    /// Range of the whole book covered by this locator, for reflow locations.
    var reflowRange: NSRange? {
        if case .reflow(let offset, let length, _) = self, length > 0 {
            return NSRange(location: max(0, offset), length: length)
        }
        return nil
    }
}

enum RenderModePreference: String, Codable, CaseIterable, Sendable {
    case auto
    case reflow
    case pageImage
}