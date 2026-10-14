import Foundation

struct ReadingProgress: Codable, Hashable, Sendable {
    var locator: Locator
    /// 0...1 through the book, measured in characters (reflow) or pages (page image).
    var fraction: Double

    static let start = ReadingProgress(locator: .reflow(charOffset: 0, length: 0, quote: nil), fraction: 0)

    var isAtStart: Bool { fraction <= 0.0001 }
    var isAtEnd: Bool { fraction >= 0.9999 }
}

struct Book: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var author: String
    /// File name inside `Library/Books`.
    var fileName: String
    /// File name inside `Library/Covers`.
    var coverFileName: String?
    var pageCount: Int
    var byteSize: Int64
    var addedAt: Date
    var lastOpenedAt: Date?
    var progress: ReadingProgress
    var preferredMode: RenderModePreference

    var displayAuthor: String { author.isEmpty ? "Unknown author" : author }
}