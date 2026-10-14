import SwiftUI
import UIKit

/// Loads a book's cover from disk off the main thread, with a generated placeholder
/// for books whose thumbnail is missing.
struct CoverImage: View {

    let book: Book

    @State private var image: UIImage?
    @State private var loadedID: UUID?

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .task(id: book.id) { await load() }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.24, green: 0.22, blue: 0.30),
                        Color(red: 0.36, green: 0.30, blue: 0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "text.book.closed")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(initials)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            )
    }

    private var initials: String {
        let words = book.title.split(separator: " ").prefix(2)
        let value = words.compactMap { $0.first }.map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }

    private func load() async {
        guard loadedID != book.id else { return }
        loadedID = book.id
        guard let url = AppPaths.coverURL(book) else {
            ImportService.regenerateCoverIfNeeded(for: book)
            if let regenerated = AppPaths.coverURL(book) {
                image = await Self.loadImage(at: regenerated)
            }
            return
        }
        image = await Self.loadImage(at: url)
    }

    private nonisolated static func loadImage(at url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let data = try? Data(contentsOf: url)
                let image = data.flatMap { UIImage(data: $0) }
                continuation.resume(returning: image)
            }
        }
    }
}