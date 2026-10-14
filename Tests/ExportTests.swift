import XCTest
@testable import my_kindle

@MainActor
final class ExportTests: XCTestCase {

    private let book = Book(
        id: UUID(),
        title: "The 48 Laws of Power",
        author: "Robert Greene",
        fileName: "book.pdf",
        coverFileName: nil,
        pageCount: 100,
        byteSize: 1024,
        addedAt: Date(),
        lastOpenedAt: nil,
        progress: .start,
        preferredMode: .auto
    )

    private func annotation(
        kind: AnnotationKind,
        offset: Int,
        quote: String,
        note: String = "",
        chapter: String? = nil
    ) -> Annotation {
        Annotation(
            bookID: book.id,
            kind: kind,
            locator: .reflow(charOffset: offset, length: quote.count, quote: quote),
            quote: quote,
            note: note,
            chapterTitle: chapter
        )
    }

    func testMarkdownGroupsByChapter() {
        let markdown = ExportService.markdown(books: [book], annotations: [
            annotation(kind: .highlight, offset: 10, quote: "Never outshine the master", chapter: "Law 1"),
            annotation(kind: .highlight, offset: 200, quote: "Court people without being servile", chapter: "Law 2"),
            annotation(kind: .highlight, offset: 400, quote: "Master appearances", chapter: "Law 2")
        ])

        XCTAssertTrue(markdown.contains("# The 48 Laws of Power"))
        XCTAssertTrue(markdown.contains("*Robert Greene*"))
        XCTAssertTrue(markdown.contains("## Law 1"))
        XCTAssertTrue(markdown.contains("## Law 2"))
        XCTAssertTrue(markdown.contains("> Never outshine the master"))
        XCTAssertEqual(markdown.components(separatedBy: "## Law 2").count - 1, 1, "A chapter header should appear once")
    }

    func testMarkdownIncludesNotes() {
        let markdown = ExportService.markdown(books: [book], annotations: [
            annotation(kind: .highlight, offset: 0, quote: "Seduce with reason", note: "Applies to the project lead", chapter: "Law 5")
        ])

        XCTAssertTrue(markdown.contains("**Note:** Applies to the project lead"))
    }

    func testMarkdownHandlesEmptyInput() {
        let markdown = ExportService.markdown(books: [book], annotations: [])
        XCTAssertTrue(markdown.contains("Nothing saved yet"))
    }

    func testMarkdownIgnoresOtherBooks() {
        var other = book
        other.id = UUID()
        let markdown = ExportService.markdown(books: [book], annotations: [
            annotation(kind: .highlight, offset: 0, quote: "other book text", chapter: "Law 1")
        ])
        XCTAssertFalse(markdown.contains("other book text"))
    }

    func testLibraryStorePersistsBooksAndAnnotations() {
        let store = LibraryStore()
        let existing = store.books.count
        let existingNotes = store.annotations.count

        let scratch = Book(
            id: UUID(),
            title: "Export Test Book",
            author: "",
            fileName: "scratch.pdf",
            coverFileName: nil,
            pageCount: 10,
            byteSize: 1,
            addedAt: Date(),
            lastOpenedAt: nil,
            progress: .start,
            preferredMode: .auto
        )
        store.upsert(scratch)
        store.add(annotation(kind: .highlight, offset: 0, quote: "stored quote", chapter: "One"))
        store.saveNow()

        let reloaded = LibraryStore()
        XCTAssertEqual(reloaded.books.count, existing + 1)
        XCTAssertTrue(reloaded.books.contains { $0.title == "Export Test Book" })
        XCTAssertGreaterThanOrEqual(reloaded.annotations.count, existingNotes + 1)
        XCTAssertTrue(reloaded.annotations.contains { $0.quote == "stored quote" })

        store.delete(bookID: scratch.id)
        store.saveNow()

        let afterDelete = LibraryStore()
        XCTAssertEqual(afterDelete.books.count, existing)
        XCTAssertEqual(afterDelete.annotations.count, existingNotes)
    }

    func testProgressFractionClampsToZeroOne() {
        let store = LibraryStore()
        let scratch = Book(
            id: UUID(), title: "Clamp", author: "", fileName: "c.pdf", coverFileName: nil,
            pageCount: 1, byteSize: 1, addedAt: Date(), lastOpenedAt: nil,
            progress: .start, preferredMode: .auto
        )
        store.upsert(scratch)
        store.updateProgress(bookID: scratch.id, locator: .reflow(charOffset: 5, length: 1, quote: nil), fraction: 3.5)

        XCTAssertEqual(store.book(id: scratch.id)?.progress.fraction, 1.0)

        store.delete(bookID: scratch.id)
        store.saveNow()
    }
}