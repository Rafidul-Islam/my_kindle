import Foundation

extension JSONEncoder {
    static var inwell: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var inwell: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct LibraryFile: Codable {
    var version: Int = 1
    var books: [Book] = []
    var settings: ReaderSettings = .default
}

struct NotesFile: Codable {
    var version: Int = 1
    var annotations: [Annotation] = []
}