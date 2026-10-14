import Foundation

enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case highlight
    case underline
    case note
    case bookmark
}

struct Annotation: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var bookID: UUID
    var kind: AnnotationKind
    var locator: Locator
    /// The text this annotation covers. Used for display, list rows and export.
    var quote: String
    var note: String
    var colorIndex: Int
    var createdAt: Date
    var modifiedAt: Date
    /// Chapter title resolved at creation time so lists stay readable.
    var chapterTitle: String?

    init(
        id: UUID = UUID(),
        bookID: UUID,
        kind: AnnotationKind,
        locator: Locator,
        quote: String,
        note: String = "",
        colorIndex: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        chapterTitle: String? = nil
    ) {
        self.id = id
        self.bookID = bookID
        self.kind = kind
        self.locator = locator
        self.quote = quote
        self.note = note
        self.colorIndex = colorIndex
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.chapterTitle = chapterTitle
    }

    var isMark: Bool { kind == .highlight || kind == .underline }
}

/// A highlight as the renderer needs it: a range in the book's full text.
struct HighlightSpan: Hashable {
    var id: UUID
    var range: NSRange
    var colorIndex: Int
    var kind: AnnotationKind
}