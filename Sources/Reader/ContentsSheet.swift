import SwiftUI

struct ContentsSheet: View {

    let chapters: [Chapter]
    let currentPage: Int
    let onSelect: (Chapter) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if chapters.isEmpty {
                    ContentUnavailableView(
                        "No contents",
                        systemImage: "list.bullet",
                        description: Text("This PDF has no bookmark outline.")
                    )
                } else {
                    List {
                        ForEach(chapters) { chapter in
                            Button {
                                onSelect(chapter)
                            } label: {
                                HStack(spacing: 12) {
                                    Text(chapter.title)
                                        .font(chapter.level == 0 ? .headline : .body)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Text("\(chapter.pageIndex + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(
                                top: chapter.level == 0 ? 10 : 6,
                                leading: 16 + CGFloat(chapter.level) * 18,
                                bottom: chapter.level == 0 ? 10 : 6,
                                trailing: 16
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct BookmarksSheet: View {

    let store: LibraryStore
    let bookID: UUID
    let onSelect: (Locator) -> Void
    let onDelete: (Annotation) -> Void

    @Environment(\.dismiss) private var dismiss

    private var bookmarks: [Annotation] {
        store.annotations(for: bookID).filter { $0.kind == .bookmark }
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No bookmarks",
                        systemImage: "bookmark",
                        description: Text("Select text while reading and tap the bookmark button.")
                    )
                } else {
                    List {
                        ForEach(bookmarks.reversed()) { bookmark in
                            Button {
                                onSelect(bookmark.locator)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    if let chapter = bookmark.chapterTitle {
                                        Text(chapter)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(bookmark.quote.isEmpty ? "Marked area" : bookmark.quote)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    onDelete(bookmark)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}