import Foundation
import PDFKit
import UIKit
import Observation

/// `PDFDocument` is not `Sendable`, but it is only ever touched by one background
/// queue at a time in this app.
private final class PDFBox: @unchecked Sendable {
    let document: PDFDocument
    init(_ document: PDFDocument) { self.document = document }
}

private final class ImageCache: @unchecked Sendable {
    private let cache = NSCache<NSNumber, UIImage>()
    func image(for key: Int) -> UIImage? { cache.object(forKey: NSNumber(value: key)) as? UIImage }
    func insert(_ image: UIImage, for key: Int) { cache.setObject(image, forKey: NSNumber(value: key)) }
}

/// Everything the reader screen needs for one book: which mode it is in, the page
/// model, and the plumbing to rebuild it when settings or screen size change.
///
/// Only ever touched from the main thread, so it is not actor-isolated.
@Observable
final class ReaderDocument {

    enum Mode: String, Sendable {
        case reflow
        case pageImage
    }

    let book: Book

    private(set) var mode: Mode = .pageImage
    private(set) var pages: [PageContent] = []
    private(set) var isPreparing = true
    private(set) var preparationProgress: Double = 0
    private(set) var preparationMessage: String = ""
    private(set) var model: ReflowModel?
    private(set) var attributed: NSAttributedString?
    private(set) var chapters: [Chapter] = []
    private(set) var textAreaSize: CGSize = .zero

    var settings: ReaderSettings

    private let pdfBox: PDFBox?
    private let imageCache = ImageCache()
    private var generation = 0
    private var didPrepare = false

    init(book: Book, settings: ReaderSettings, textAreaSize: CGSize = .zero) {
        self.book = book
        self.settings = settings
        self.textAreaSize = textAreaSize
        AppPaths.ensureDirectories()
        self.pdfBox = PDFDocument(url: AppPaths.bookURL(book)).map { PDFBox($0) }
    }

    // MARK: - Lifecycle

    func prepare() {
        guard !didPrepare else { return }
        didPrepare = true

        guard pdfBox != nil else {
            mode = .pageImage
            pages = []
            isPreparing = false
            preparationMessage = "This file could not be opened."
            return
        }

        switch book.preferredMode {
        case .pageImage:
            buildPageImagePages()
        case .reflow:
            loadReflowModel(preference: .reflow)
        case .auto:
            loadReflowModel(preference: .auto)
        }
    }

    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        generation += 1
        if newMode == .pageImage {
            buildPageImagePages()
        } else if let model {
            rebuildReflowPages(model: model)
        } else {
            loadReflowModel(preference: .reflow)
        }
    }

    func update(settings newSettings: ReaderSettings, textAreaSize newSize: CGSize) {
        settings = newSettings
        guard newSize != textAreaSize else { return }
        textAreaSize = newSize
        guard let model, mode == .reflow else { return }
        rebuildReflowPages(model: model)
    }

    func update(textAreaSize newSize: CGSize) {
        update(settings: settings, textAreaSize: newSize)
    }

    // MARK: - Page image mode

    private func buildPageImagePages() {
        mode = .pageImage
        isPreparing = false
        preparationProgress = 1
        preparationMessage = ""
        let count = pdfBox?.document.pageCount ?? book.pageCount
        pages = (0..<max(count, 0)).map { PageContent.pdf($0) }
    }

    // MARK: - Reflow mode

    private func loadReflowModel(preference: RenderModePreference) {
        isPreparing = true
        preparationProgress = 0
        preparationMessage = "Analysing book…"

        guard let pdfBox else {
            buildPageImagePages()
            return
        }

        let fingerprint = ReflowBuilder.fingerprint(for: AppPaths.bookURL(book))
        if let cached = ReflowCache.load(bookID: book.id, fingerprint: fingerprint) {
            applyReflow(model: cached, preference: preference)
            return
        }

        generation += 1
        let token = generation
        let box = pdfBox
        let bookID = book.id

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let progress = ProgressRelay()
            let built = ReflowBuilder.build(
                document: box.document,
                bookID: bookID,
                fingerprint: fingerprint
            ) { fraction in
                progress.value = fraction
            }

            Task { @MainActor in
                guard let self else { return }
                self.preparationProgress = progress.value
                ReflowCache.save(built)
                self.applyReflow(model: built, preference: preference)

                if token == self.generation, built.runs.isEmpty {
                    self.buildPageImagePages()
                } else {
                    self.rebuildReflowPages(model: built)
                }
            }
        }
    }

    private func applyReflow(model newModel: ReflowModel, preference: RenderModePreference) {
        model = newModel
        chapters = newModel.chapters
        mode = .reflow

        // A page that is not plain single-column text becomes an image marker, so the
        // share of those markers tells us how much of the book reflow actually helps.
        let totalPages = max(newModel.pageStartOffsets.count - 1, 1)
        let imagePages = newModel.runs.filter { $0.kind == .image }.count
        let coverage = Double(totalPages - imagePages) / Double(totalPages)

        switch preference {
        case .reflow:
            rebuildReflowPages(model: newModel)
        case .pageImage:
            buildPageImagePages()
        case .auto:
            if coverage < 0.5 {
                buildPageImagePages()
            } else {
                rebuildReflowPages(model: newModel)
            }
        }
    }

    private func rebuildReflowPages(model modelValue: ReflowModel) {
        mode = .reflow
        guard let pdfBox else { return }

        generation += 1
        let token = generation
        let box = pdfBox
        let cache = imageCache
        let size = effectiveTextAreaSize
        let currentSettings = settings
        let documentModel = modelValue

        isPreparing = true
        preparationMessage = "Laying out pages…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let attributed = ReflowTypography.attributedString(
                model: documentModel,
                settings: currentSettings,
                textAreaSize: size
            ) { pageIndex in
                ReaderDocument.renderPageImage(pageIndex: pageIndex, box: box, cache: cache, width: size.width * 2)
            }

            let slices = Paginator.paginate(attributed, textRect: CGRect(origin: .zero, size: size))

            Task { @MainActor in
                guard let self, token == self.generation else { return }
                self.attributed = attributed
                self.pages = slices.map { PageContent.reflow($0) }
                self.isPreparing = false
                self.preparationProgress = 1
                self.preparationMessage = ""
            }
        }
    }

    private var effectiveTextAreaSize: CGSize {
        if textAreaSize.width > 40, textAreaSize.height > 40 { return textAreaSize }
        return CGSize(width: 320, height: 480)
    }

    private static func renderPageImage(pageIndex: Int, box: PDFBox, cache: ImageCache, width: CGFloat) -> UIImage? {
        if let cached = cache.image(for: pageIndex) { return cached }
        guard let page = box.document.page(at: pageIndex) else { return nil }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let targetWidth = max(width, 200)
        let scale = targetWidth / bounds.width
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let ctx = context.cgContext
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            // PDF content is drawn in a y-up space; the renderer gives us y-down.
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            page.draw(with: .cropBox, to: ctx)
        }
        cache.insert(image, for: pageIndex)
        return image
    }

    func pageImage(forPageIndex index: Int, width: CGFloat) -> UIImage? {
        guard let box = pdfBox else { return nil }
        return Self.renderPageImage(pageIndex: index, box: box, cache: imageCache, width: width)
    }

    // MARK: - Position mapping

    var pageCount: Int { pages.count }

    func sourcePageIndex(forPageIndex index: Int) -> Int? {
        guard index >= 0, index < pages.count else { return nil }
        if let pdfIndex = pages[index].pdfPageIndex { return pdfIndex }
        guard let slice = pages[index].reflowSlice,
              let attributed,
              let model else { return nil }
        let probe = min(slice.start, attributed.length - 1)
        guard probe >= 0 else { return model.pageStartOffsets.first }
        if let page = attributed.attribute(.myKindlePageIndex, at: probe, effectiveRange: nil) as? Int {
            return page
        }
        return model.pageStartOffsets.first ?? 0
    }

    func locator(forPageIndex index: Int) -> Locator {
        switch pages[safe: index] ?? .pdf(0) {
        case .pdf(let pdfIndex):
            return .pdfRect(pageIndex: pdfIndex, rect: [0, 0, 1, 1])
        case .reflow(let slice):
            let quote = sliceQuote(slice)
            return .reflow(charOffset: slice.start, length: slice.length, quote: quote)
        }
    }

    private func sliceQuote(_ slice: PageSlice) -> String? {
        guard let attributed, slice.start < attributed.length else { return nil }
        let length = min(slice.length, 120)
        let text = (attributed.string as NSString).substring(with: NSRange(location: slice.start, length: length))
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }

    func fraction(forPageIndex index: Int) -> Double {
        guard !pages.isEmpty else { return 0 }
        switch pages[safe: index] {
        case .some(.pdf(let pdfIndex)):
            let total = max(pdfBox?.document.pageCount ?? 1, 1)
            return Double(pdfIndex) / Double(max(total - 1, 1))
        case .some(.reflow(let slice)):
            let total = max(attributed?.length ?? 1, 1)
            return Double(slice.start) / Double(total)
        case .none:
            return 0
        }
    }

    /// Resolves a stored position back to a page index in the current layout.
    func pageIndex(for locator: Locator) -> Int? {
        switch locator {
        case .pdfRect(let pageIndex, _):
            if mode == .pageImage { return min(max(pageIndex, 0), max(pages.count - 1, 0)) }
            return nil
        case .reflow(let offset, _, _):
            guard mode == .reflow else { return nil }
            return pageIndex(forCharacterOffset: offset)
        }
    }

    func pageIndex(forCharacterOffset offset: Int) -> Int? {
        for (index, page) in pages.enumerated() {
            if let slice = page.reflowSlice, slice.start <= offset {
                return index
            }
        }
        return pages.isEmpty ? nil : 0
    }

    func chapterTitle(forPageIndex index: Int) -> String? {
        guard !chapters.isEmpty, let model else { return nil }
        let offset: Int
        if let slice = pages[safe: index]?.reflowSlice {
            offset = slice.start
        } else if let pdfIndex = pages[safe: index]?.pdfPageIndex {
            offset = model.pageStartOffsets[safe: pdfIndex] ?? 0
        } else {
            return nil
        }
        var resolved: String?
        for chapter in chapters {
            guard chapter.pageIndex < model.pageStartOffsets.count else { continue }
            if model.pageStartOffsets[chapter.pageIndex] <= offset {
                resolved = chapter.title
            } else {
                break
            }
        }
        return resolved
    }

    /// Chapter label for a stored character offset (used when creating annotations).
    func chapterTitle(forCharacterOffset offset: Int) -> String? {
        guard !chapters.isEmpty, let model else { return nil }
        var resolved: String?
        for chapter in chapters {
            guard chapter.pageIndex < model.pageStartOffsets.count else { continue }
            if model.pageStartOffsets[chapter.pageIndex] <= offset {
                resolved = chapter.title
            } else {
                break
            }
        }
        return resolved
    }

    func jumpTarget(forChapter chapter: Chapter) -> Int? {
        if mode == .pageImage {
            return min(max(chapter.pageIndex, 0), max(pages.count - 1, 0))
        }
        guard let model, chapter.pageIndex < model.pageStartOffsets.count else { return nil }
        return pageIndex(forCharacterOffset: model.pageStartOffsets[chapter.pageIndex])
    }

    /// Character offset currently on screen, used when saving progress.
    func characterOffset(forPageIndex index: Int) -> Int {
        pages[safe: index]?.reflowSlice?.start ?? 0
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Tiny thread-safe box so the extraction loop can report progress from a background queue.
private final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Double = 0
    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}