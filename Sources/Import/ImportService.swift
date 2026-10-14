import Foundation
import PDFKit
import UIKit

enum ImportError: LocalizedError {
    case unreadable
    case empty

    var errorDescription: String? {
        switch self {
        case .unreadable: return "That file could not be opened as a PDF."
        case .empty: return "That PDF has no pages."
        }
    }
}

@MainActor
final class ImportService {
    static let shared = ImportService()

    /// Copies the picked file into the app's own storage, reads its metadata and
    /// renders a cover thumbnail.
    ///
    /// The parsing and rendering happen off the main thread — a 30 MB scan would
    /// otherwise freeze the shelf while it imports.
    func importBook(from url: URL) async throws -> Book {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        let id = UUID()
        let destination = AppPaths.books.appendingPathComponent("\(id.uuidString).pdf")
        let coverURL = AppPaths.covers.appendingPathComponent("\(id.uuidString).jpg")
        let fileTitle = url.deletingPathExtension().lastPathComponent

        return try await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else { throw ImportError.unreadable }
            guard document.pageCount > 0 else { throw ImportError.empty }

            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)

            let attributes = PDFDocument.documentAttributes ?? [:]
            let metadataTitle = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let title = metadataTitle.flatMap { $0.isEmpty ? nil : $0 } ?? fileTitle
            let author = ((attributes[PDFDocumentAttribute.authorAttribute] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""

            var coverFileName: String?
            if let firstPage = document.page(at: 0) {
                let thumbnail = firstPage.thumbnail(of: CGSize(width: 600, height: 900), for: .cropBox)
                if let data = thumbnail.jpegData(compressionQuality: 0.85),
                   (try? data.write(to: coverURL, options: .atomic)) != nil {
                    coverFileName = coverURL.lastPathComponent
                }
            }

            let attributesOfFile = try? FileManager.default.attributesOfItem(atPath: destination.path)
            let byteSize = (attributesOfFile?[.size] as? NSNumber)?.int64Value ?? 0

            return Book(
                id: id,
                title: title,
                author: author,
                fileName: destination.lastPathComponent,
                coverFileName: coverFileName,
                pageCount: document.pageCount,
                byteSize: byteSize,
                addedAt: Date(),
                lastOpenedAt: nil,
                progress: .start,
                preferredMode: .auto
            )
        }.value
    }

    /// Re-renders the cover for a book whose thumbnail is missing. Safe to call from
    /// any thread or task, which is why it is not actor-isolated.
    nonisolated static func regenerateCoverIfNeeded(for book: Book) {
        guard book.coverFileName == nil,
              let document = PDFDocument(url: AppPaths.bookURL(book)),
              let firstPage = document.page(at: 0) else { return }
        let thumbnail = firstPage.thumbnail(of: CGSize(width: 600, height: 900), for: .cropBox)
        guard let data = thumbnail.jpegData(compressionQuality: 0.85) else { return }
        let coverURL = AppPaths.covers.appendingPathComponent("\(book.id.uuidString).jpg")
        try? data.write(to: coverURL, options: .atomic)
    }
}