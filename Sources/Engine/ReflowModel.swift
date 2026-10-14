import Foundation

/// A run of the book's extracted text. `kind` distinguishes real text from the
/// single-character placeholder that stands in for a page we could not reflow.
struct ModelRun: Codable, Sendable {
    enum Kind: Int, Codable, Sendable {
        case text = 0
        case image = 1
    }

    var loc: Int
    var len: Int
    var size: Double
    var bold: Bool
    var italic: Bool
    var heading: Bool
    /// True when this line starts a new paragraph in the original layout.
    var paragraphStart: Bool
    var pageIndex: Int
    var kind: Kind

    var range: NSRange { NSRange(location: loc, length: len) }
}

struct Chapter: Codable, Hashable, Identifiable, Sendable {
    var title: String
    var pageIndex: Int
    var level: Int

    var id: String { "\(pageIndex)-\(level)-\(title)" }
}

/// The cached, settings-independent result of analysing a PDF. Building this once per
/// book means font-size and theme changes never re-parse the document.
struct ReflowModel: Codable, Sendable {
    static let currentVersion = 1

    var version: Int = ReflowModel.currentVersion
    var bookID: UUID = UUID()
    var fingerprint: String = ""
    var text: String = ""
    var runs: [ModelRun] = []
    /// Character offset in `text` where each PDF page's content begins.
    var pageStartOffsets: [Int] = []
    var chapters: [Chapter] = []

    var length: Int { (text as NSString).length }

    func run(at offset: Int) -> ModelRun? {
        var low = 0
        var high = runs.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let run = runs[mid]
            if offset < run.loc {
                high = mid - 1
            } else if offset >= run.loc + run.len {
                low = mid + 1
            } else {
                return run
            }
        }
        return nil
    }
}