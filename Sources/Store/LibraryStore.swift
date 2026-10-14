import Foundation
import Observation

/// In-memory library backed by two small JSON files. Writes are debounced so that
/// flipping through pages does not hammer the disk.
///
/// Deliberately not `@MainActor`: it is only ever touched from the main thread, and
/// leaving it non-isolated keeps call sites free of actor-annotation friction.
@Observable
final class LibraryStore {

    private(set) var books: [Book] = []
    private(set) var annotations: [Annotation] = []
    var settings: ReaderSettings = .default

    private var saveTask: Task<Void, Never>?

    init() {
        AppPaths.ensureDirectories()
        load()
    }

    // MARK: - Persistence

    private func load() {
        if let data = try? Data(contentsOf: AppPaths.libraryFile),
           let file = try? JSONDecoder.inwell.decode(LibraryFile.self, from: data) {
            books = file.books
            settings = file.settings
        }
        if let data = try? Data(contentsOf: AppPaths.notesFile),
           let file = try? JSONDecoder.inwell.decode(NotesFile.self, from: data) {
            annotations = file.annotations
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        if let data = try? JSONEncoder.inwell.encode(LibraryFile(books: books, settings: settings)) {
            try? data.write(to: AppPaths.libraryFile, options: .atomic)
        }
        if let data = try? JSONEncoder.inwell.encode(NotesFile(annotations: annotations)) {
            try? data.write(to: AppPaths.notesFile, options: .atomic)
        }
    }

    // MARK: - Books

    var sortedBooks: [Book] {
        books.sorted { lhs, rhs in
            let lhsDate = lhs.lastOpenedAt ?? lhs.addedAt
            let rhsDate = rhs.lastOpenedAt ?? rhs.addedAt
            return lhsDate > rhsDate
        }
    }

    var continueReading: [Book] {
        sortedBooks.filter { $0.progress.fraction > 0.001 && !$0.progress.isAtEnd }
    }

    func book(id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    func upsert(_ book: Book) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index] = book
        } else {
            books.append(book)
        }
        scheduleSave()
    }

    func delete(bookID: UUID) {
        guard let book = book(id: bookID) else { return }
        try? FileManager.default.removeItem(at: AppPaths.bookURL(book))
        if let cover = AppPaths.coverURL(book) {
            try? FileManager.default.removeItem(at: cover)
        }
        try? FileManager.default.removeItem(at: ReflowCache.url(for: bookID))
        books.removeAll { $0.id == bookID }
        annotations.removeAll { $0.bookID == bookID }
        saveNow()
    }

    func markOpened(bookID: UUID) {
        guard var book = book(id: bookID) else { return }
        book.lastOpenedAt = Date()
        upsert(book)
    }

    func updateProgress(bookID: UUID, locator: Locator, fraction: Double) {
        guard var book = book(id: bookID) else { return }
        book.progress = ReadingProgress(locator: locator, fraction: min(max(fraction, 0), 1))
        upsert(book)
    }

    func updateMode(bookID: UUID, mode: RenderModePreference) {
        guard var book = book(id: bookID) else { return }
        book.preferredMode = mode
        upsert(book)
    }

    // MARK: - Annotations

    func annotations(for bookID: UUID) -> [Annotation] {
        annotations
            .filter { $0.bookID == bookID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func add(_ annotation: Annotation) {
        annotations.append(annotation)
        scheduleSave()
    }

    func update(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        var updated = annotation
        updated.modifiedAt = Date()
        annotations[index] = updated
        scheduleSave()
    }

    func deleteAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: - Derived

var totalAnnotationCount: Int { annotations.count }
}