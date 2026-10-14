import SwiftUI
import UIKit

struct PendingSelection: Identifiable {
    let id = UUID()
    var range: NSRange?
    var normalizedRect: [Double]?
    var quote: String
    var pageIndex: Int
    var chapterTitle: String?
}

struct ReaderView: View {

    let book: Book
    let store: LibraryStore

    @Environment(\.dismiss) private var dismiss

    @State private var document: ReaderDocument
    @State private var currentIndex: Int = 0
    @State private var chromeVisible = true
    @State private var pendingSelection: PendingSelection?
    @State private var selectedColorIndex: Int = 0
    @State private var showSettings = false
    @State private var showTOC = false
    @State private var showBookmarks = false
    @State private var showHighlights = false
    @State private var didRestorePosition = false

    init(book: Book, store: LibraryStore) {
        self.book = book
        self.store = store
        _document = State(initialValue: ReaderDocument(book: book, settings: store.settings))
    }

    private var theme: ReaderTheme {
        ReaderTheme.theme(document.settings.theme)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.background.ignoresSafeArea()

                pageStack(size: proxy.size)

                if document.isPreparing {
                    preparingOverlay
                }

                if chromeVisible {
                    chromeOverlay
                }

                if let selection = pendingSelection {
                    selectionBar(for: selection)
                }
            }
            .onAppear {
                store.markOpened(bookID: book.id)
                document.update(textAreaSize: proxy.size)
                document.prepare()
                restorePositionIfNeeded()
            }
            .onChange(of: document.pages.count) { _, _ in
                restorePositionIfNeeded()
            }
            .onChange(of: proxy.size) { _, newSize in
                guard newSize.width > 40, newSize.height > 40 else { return }
                let previous = document.locator(forPageIndex: currentIndex)
                document.update(textAreaSize: newSize)
                if let target = document.pageIndex(for: previous) {
                    currentIndex = target
                }
            }
            .onChange(of: currentIndex) { _, index in
                pendingSelection = nil
                saveProgress(at: index)
            }
            .onChange(of: document.settings) { _, newSettings in
                store.settings = newSettings
                let previous = document.locator(forPageIndex: currentIndex)
                document.update(settings: newSettings, textAreaSize: document.textAreaSize)
                if let target = document.pageIndex(for: previous) {
                    currentIndex = target
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(false)
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(settings: document.settings, mode: document.mode) { newSettings, newMode in
                document.update(settings: newSettings, textAreaSize: document.textAreaSize)
                store.settings = newSettings
                if let newMode, newMode != document.mode {
                    document.setMode(newMode)
                    store.updateMode(
                        bookID: book.id,
                        mode: newMode == ReaderDocument.Mode.reflow ? RenderModePreference.reflow : RenderModePreference.pageImage
                    )
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(theme.background)
        }
        .sheet(isPresented: $showTOC) {
            ContentsSheet(chapters: document.chapters, currentPage: currentIndex) { chapter in
                if let target = document.jumpTarget(for: chapter) {
                    go(to: target)
                }
                showTOC = false
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(theme.background)
        }
        .sheet(isPresented: $showBookmarks) {
            BookmarksSheet(store: store, bookID: book.id) { locator in
                if let index = document.pageIndex(for: locator) { go(to: index) }
                showBookmarks = false
            } onDelete: { annotation in
                store.deleteAnnotation(id: annotation.id)
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(theme.background)
        }
        .sheet(isPresented: $showHighlights) {
            HighlightsSheet(store: store, book: book, settings: document.settings) { locator in
                if let index = document.pageIndex(for: locator) { go(to: index) }
                showHighlights = false
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(theme.background)
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageStack(size: CGSize) -> some View {
        if document.pages.isEmpty {
            Color.clear
        } else {
            TabView(selection: $currentIndex) {
                ForEach(0..<document.pages.count, id: \.self) { index in
                    page(at: index)
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private func page(at index: Int) -> some View {
        switch document.pages[safe: index] {
        case .some(.reflow(let slice)):
            if let attributed = document.attributed {
                ReflowPageContainer(
                    attributed: attributed,
                    slice: slice,
                    insets: document.settings.insets,
                    theme: theme,
                    spans: spans(forPage: index),
                    onTap: { zone in handle(zone: zone) },
                    onSelectionFinished: { range in
                        let quote = quote(in: range)
                        pendingSelection = PendingSelection(
                            range: range,
                            normalizedRect: nil,
                            quote: quote,
                            pageIndex: document.sourcePageIndex(forPageIndex: index) ?? 0,
                            chapterTitle: document.chapterTitle(forPageIndex: index)
                        )
                    }
                )
                .ignoresSafeArea()
            } else {
                Color.clear
            }
        case .some(.pdf(let pdfIndex)):
            PDFPageContainer(
                image: document.pageImage(forPageIndex: pdfIndex, width: sizeProxyWidth),
                theme: theme,
                marks: marks(forPDFPage: pdfIndex),
                onTap: { zone in handle(zone: zone) },
                onRectSelected: { normalised in
                    pendingSelection = PendingSelection(
                        range: nil,
                        normalizedRect: [normalised.origin.x, normalised.origin.y, normalised.width, normalised.height],
                        quote: "",
                        pageIndex: pdfIndex,
                        chapterTitle: nil
                    )
                }
            )
            .ignoresSafeArea()
        case .none:
            Color.clear
        }
    }

    private var sizeProxyWidth: CGFloat {
        let width = document.textAreaSize.width
        return width > 40 ? width : UIScreen.main.bounds.width
    }

    // MARK: - Data helpers

    private func spans(forPage index: Int) -> [HighlightSpan] {
        guard let slice = document.pages[safe: index]?.reflowSlice else { return [] }
        return store.annotations(for: book.id).compactMap { annotation in
            guard annotation.isMark, let range = annotation.locator.reflowRange else { return nil }
            guard NSIntersectionRange(range, slice.range).length > 0 else { return nil }
            return HighlightSpan(id: annotation.id, range: range, colorIndex: annotation.colorIndex, kind: annotation.kind)
        }
    }

    private func marks(forPDFPage index: Int) -> [PDFRectMark] {
        store.annotations(for: book.id).compactMap { annotation in
            guard case .pdfRect(let pageIndex, let rect) = annotation.locator, pageIndex == index else { return nil }
            return PDFRectMark(
                id: annotation.id,
                pageIndex: pageIndex,
                normalizedRect: rect,
                colorIndex: annotation.colorIndex,
                kind: annotation.kind
            )
        }
    }

    private func quote(in range: NSRange) -> String {
        guard let attributed = document.attributed, range.location >= 0, range.location + range.length <= attributed.length else {
            return ""
        }
        let text = (attributed.string as NSString).substring(with: range)
        return text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Navigation

    private func handle(zone: TapZone) {
        switch zone {
        case .previous:
            go(to: currentIndex - 1)
        case .next:
            go(to: currentIndex + 1)
        case .menu:
            withAnimation(.easeInOut(duration: 0.18)) { chromeVisible.toggle() }
        }
    }

    private func go(to index: Int) {
        guard !document.pages.isEmpty else { return }
        let clamped = min(max(index, 0), document.pages.count - 1)
        guard clamped != currentIndex else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            currentIndex = clamped
        }
    }

    private func restorePositionIfNeeded() {
        guard !didRestorePosition else { return }
        didRestorePosition = true
        guard let target = document.pageIndex(for: book.progress.locator), target > 0 else { return }
        currentIndex = target
    }

    private func saveProgress(at index: Int) {
        guard !document.pages.isEmpty else { return }
        let locator = document.locator(forPageIndex: index)
        let fraction = document.fraction(forPageIndex: index)
        store.updateProgress(bookID: book.id, locator: locator, fraction: fraction)
    }

    // MARK: - Overlays

    private var preparingOverlay: some View {
        VStack(spacing: 14) {
            if document.preparationProgress > 0.01 {
                ProgressView(value: document.preparationProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 180)
            } else {
                ProgressView()
            }
            Text(document.preparationMessage.isEmpty ? "Preparing…" : document.preparationMessage)
                .font(.footnote)
                .foregroundStyle(theme.secondary)
        }
        .padding(22)
        .background(theme.background.opacity(0.94), in: RoundedRectangle(cornerRadius: 16))
        .transition(.opacity)
    }

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomBar
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button {
                store.saveNow()
                dismiss()
            } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            .accessibilityLabel("Back to library")

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let chapter = document.chapterTitle(forPageIndex: currentIndex) {
                    Text(chapter)
                        .font(.caption2)
                        .foregroundStyle(theme.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            chromeButton("list.bullet", "Contents") { showTOC = true }
            chromeButton("bookmark", "Bookmarks") { showBookmarks = true }
            chromeButton("highlighter", "Highlights") { showHighlights = true }
            chromeButton("textformat.size", "Appearance") { showSettings = true }
        }
        .font(.title3)
        .foregroundStyle(theme.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.background)
    }

    private func chromeButton(_ systemName: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .accessibilityLabel(label)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { Double(currentIndex) },
                    set: { go(to: Int($0.rounded())) }
                ),
                in: 0...Double(max(document.pages.count - 1, 1)),
                step: 1
            )
            .tint(theme.secondary)

            HStack {
                Text(chapterOrPageLabel)
                    .font(.caption)
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                Spacer()
                Text("\(currentIndex + 1) of \(max(document.pages.count, 1))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondary)
                Spacer()
                Button {
                    store.saveNow()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export annotations")
                .font(.caption)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(theme.background)
    }

    private var chapterOrPageLabel: String {
        let percent = Int((document.fraction(forPageIndex: currentIndex) * 100).rounded())
        let sourcePage = document.sourcePageIndex(forPageIndex: currentIndex)
        if let sourcePage {
            return "PDF page \(sourcePage + 1) · \(percent)%"
        }
        return "\(percent)%"
    }

    // MARK: - Selection bar

    private func selectionBar(for selection: PendingSelection) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                colorDots

                Button {
                    applySelection(selection, kind: .underline)
                } label: {
                    Image(systemName: "underline")
                }
                .accessibilityLabel("Underline")

                Button {
                    applySelection(selection, kind: .highlight)
                } label: {
                    Image(systemName: "highlighter")
                }
                .accessibilityLabel("Highlight")

                Button {
                    applySelection(selection, kind: .bookmark)
                } label: {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel("Add bookmark")

                Button {
                    UIPasteboard.general.string = selection.quote
                    pendingSelection = nil
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy")
                .disabled(selection.quote.isEmpty)

                Button {
                    pendingSelection = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Dismiss")
            }
            .font(.title3)
            .foregroundStyle(theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(theme.secondary.opacity(0.25), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, selectionBarBottomInset)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var selectionBarBottomInset: CGFloat {
        chromeVisible ? 74 : 24
    }

    private var colorDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(theme.highlightColor(index))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(theme.text, lineWidth: selectedColorIndex == index ? 2 : 0)
                    )
                    .onTapGesture { selectedColorIndex = index }
            }
        }
    }

    private func applySelection(_ selection: PendingSelection, kind: AnnotationKind) {
        let locator: Locator
        if let range = selection.range {
            locator = .reflow(charOffset: range.location, length: range.length, quote: selection.quote)
        } else if let rect = selection.normalizedRect {
            locator = .pdfRect(pageIndex: selection.pageIndex, rect: rect)
        } else {
            pendingSelection = nil
            return
        }

        let annotation = Annotation(
            bookID: book.id,
            kind: kind,
            locator: locator,
            quote: selection.quote,
            colorIndex: selectedColorIndex,
            chapterTitle: selection.chapterTitle
        )
        store.add(annotation)
        pendingSelection = nil
        Haptics.tap()
    }
}

enum Haptics {
    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}