import SwiftUI
import UIKit

struct LibraryView: View {

    let store: LibraryStore

    @State private var isImporterPresented = false
    @State private var importError: String?
    @State private var isImporting = false

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 170), spacing: 18)]

    var body: some View {
        NavigationStack {
            Group {
                if store.books.isEmpty {
                    emptyState
                } else {
                    shelf
                }
            }
            .navigationTitle("My Kindle")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isImporterPresented = true
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Image(systemName: "plus")
                        }
                    }
                    .accessibilityLabel("Import a PDF")
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    importBooks(urls)
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("Import failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    // MARK: - Shelf

    private var shelf: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !store.continueReading.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Continue reading")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(store.continueReading) { book in
                                    NavigationLink {
                                        ReaderView(book: book, store: store)
                                    } label: {
                                        ContinueCard(book: book)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(store.sortedBooks) { book in
                        NavigationLink {
                            ReaderView(book: book, store: store)
                        } label: {
                            BookCard(book: book)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(bookID: book.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No books yet", systemImage: "books.vertical")
        } description: {
            Text("Import PDFs from Files, iCloud Drive or any app that shares them.")
        } actions: {
            Button("Import PDF") { isImporterPresented = true }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Import

    private func importBooks(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        Task { @MainActor in
            var failures: [String] = []
            for url in urls {
                do {
                    let book = try await ImportService.shared.importBook(from: url)
                    store.upsert(book)
                    ImportService.regenerateCoverIfNeeded(for: book)
                } catch {
                    failures.append(url.lastPathComponent)
                }
            }
            store.saveNow()
            isImporting = false
            isImporterPresented = false
            if let first = failures.first {
                importError = failures.count == 1 ? "Could not import \(first)" : "Could not import \(failures.count) files."
            }
        }
    }
}

private struct ContinueCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(book: book)
                .frame(width: 92, height: 138)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 3)

            Text(book.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 92, alignment: .leading)

            ProgressView(value: book.progress.fraction)
                .frame(width: 92)
        }
    }
}

struct BookCard: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(book: book)
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)

            Text(book.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        if book.progress.isAtStart {
            return "\(book.pageCount) pages"
        }
        let percent = Int((book.progress.fraction * 100).rounded())
        return "\(percent)% read"
    }
}