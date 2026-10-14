import Foundation

enum AppPaths {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var caches: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    static var library: URL { documents.appendingPathComponent("Library", isDirectory: true) }
    static var books: URL { library.appendingPathComponent("Books", isDirectory: true) }
    static var covers: URL { library.appendingPathComponent("Covers", isDirectory: true) }
    static var exports: URL { library.appendingPathComponent("Exports", isDirectory: true) }
    static var reflowCache: URL { caches.appendingPathComponent("Reflow", isDirectory: true) }

    static var libraryFile: URL { library.appendingPathComponent("library.json") }
    static var notesFile: URL { library.appendingPathComponent("notes.json") }

    static func ensureDirectories() {
        for directory in [library, books, covers, exports, reflowCache] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    static func bookURL(_ book: Book) -> URL {
        books.appendingPathComponent(book.fileName)
    }

    static func coverURL(_ book: Book) -> URL? {
        guard let name = book.coverFileName else { return nil }
        return covers.appendingPathComponent(name)
    }
}