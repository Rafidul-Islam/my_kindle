import SwiftUI

struct HighlightsSheet: View {

    let store: LibraryStore
    let book: Book
    let settings: ReaderSettings
    let onSelect: (Locator) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var isExporting = false

    private var marks: [Annotation] {
        store.annotations(for: book.id).filter { $0.isMark || $0.kind == .note }
    }

    var body: some View {
        NavigationStack {
            Group {
                if marks.isEmpty {
                    ContentUnavailableView(
                        "No highlights",
                        systemImage: "highlighter",
                        description: Text("Press and drag across text to highlight it.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(marks.reversed()) { annotation in
                                row(annotation)
                            }
                            .onDelete { offsets in
                                let targets = marks.reversed()
                                for offset in offsets {
                                    store.deleteAnnotation(id: targets[offset].id)
                                }
                            }
                        } footer: {
                            Text("\(marks.count) saved")
                        }
                    }
                }
            }
            .navigationTitle("Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            exportMarkdown()
                        } label: {
                            Label("Export Markdown", systemImage: "doc.plaintext")
                        }
                        Button {
                            exportPDF()
                        } label: {
                            Label("Export annotated PDF", systemImage: "doc.richtext")
                        }
                    } label: {
                        if isExporting {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(marks.isEmpty || isExporting)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let exportURL {
                    ActivityView(items: [exportURL])
                }
            }
        }
    }

    private func row(_ annotation: Annotation) -> some View {
        Button {
            onSelect(annotation.locator)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let chapter = annotation.chapterTitle {
                    Text(chapter)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if !annotation.quote.isEmpty {
                    Text(annotation.quote)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("Marked area on page \(annotation.locator.pdfPageIndex.map { $0 + 1 } ?? 0)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !annotation.note.isEmpty {
                    Label(annotation.note, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func exportMarkdown() {
        isExporting = true
        let markdown = ExportService.markdown(books: [book], annotations: marks)
        let url = AppPaths.exports.appendingPathComponent("\(safeName(book.title))-highlights.md")
        if (try? markdown.write(to: url, atomically: true, encoding: .utf8)) != nil {
            exportURL = url
            showShareSheet = true
        }
        isExporting = false
    }

    private func exportPDF() {
        isExporting = true
        let captured = marks
        let capturedSettings = settings
        Task { @MainActor in
            let url = await ExportService.annotatedPDF(
                book: book,
                annotations: captured,
                settings: capturedSettings
            )
            isExporting = false
            if let url {
                exportURL = url
                showShareSheet = true
            }
        }
    }

    private func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let filtered = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(filtered).trimmingCharacters(in: .whitespaces)
    }
}

struct ActivityView: UIViewControllerRepresentable {

    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}