import Foundation
import PDFKit
import UIKit

enum ExportService {

    // MARK: - Markdown

    static func markdown(books: [Book], annotations: [Annotation]) -> String {
        var lines: [String] = []

        for book in books {
            let relevant = annotations.filter { $0.bookID == book.id }.sorted { $0.createdAt < $1.createdAt }
            guard !relevant.isEmpty else { continue }

            lines.append("# \(book.title)")
            if !book.author.isEmpty {
                lines.append("*\(book.author)*")
            }
            lines.append("")

            var currentChapter: String?
            for annotation in relevant {
                if let chapter = annotation.chapterTitle, chapter != currentChapter {
                    currentChapter = chapter
                    lines.append("")
                    lines.append("## \(chapter)")
                    lines.append("")
                }
                if !annotation.quote.isEmpty {
                    lines.append("> \(annotation.quote)")
                }
                if !annotation.note.isEmpty {
                    lines.append("")
                    lines.append("**Note:** \(annotation.note)")
                }
                if let page = annotation.locator.pdfPageIndex {
                    lines.append("")
                    lines.append("_Page \(page + 1)_")
                }
                lines.append("")
            }
            lines.append("---")
            lines.append("")
        }

        if lines.isEmpty {
            return "# Highlights\n\nNothing saved yet.\n"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Annotated PDF

    /// Writes a new PDF with the annotations baked in. Rectangle annotations are
    /// written back onto the original pages; reflow annotations are re-rendered
    /// from the paginated text.
    static func annotatedPDF(book: Book, annotations: [Annotation], settings: ReaderSettings) async -> URL? {
        let rectAnnotations = annotations.filter {
            if case .pdfRect = $0.locator { return true }
            return false
        }
        let reflowAnnotations = annotations.filter {
            if case .reflow = $0.locator { return true }
            return false
        }

        let sourceURL = AppPaths.bookURL(book)
        guard PDFDocument(url: sourceURL) != nil else { return nil }

        let destination = AppPaths.exports
            .appendingPathComponent("\(safeName(book.title))-annotated.pdf")

        if !reflowAnnotations.isEmpty {
            let rendered = await renderReflowPDF(
                book: book,
                annotations: reflowAnnotations,
                settings: settings,
                destination: destination
            )
            if rendered { return destination }
        }

        guard let document = PDFDocument(url: sourceURL) else { return nil }
        let theme = ReaderTheme.theme(settings.theme)

        for annotation in rectAnnotations {
            guard case .pdfRect(let pageIndex, let rect) = annotation.locator,
                  rect.count == 4,
                  let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .cropBox)
            let highlight = PDFAnnotation(bounds: CGRect(
                x: bounds.minX + CGFloat(rect[0]) * bounds.width,
                y: bounds.minY + CGFloat(rect[1]) * bounds.height,
                width: CGFloat(rect[2]) * bounds.width,
                height: CGFloat(rect[3]) * bounds.height
            ), forType: annotation.kind == .underline ? .underline : .highlight, withProperties: nil)
            highlight.color = theme.highlightColor(annotation.colorIndex)
            if !annotation.note.isEmpty {
                highlight.contents = annotation.note
            }
            page.addAnnotation(highlight)
        }

        guard let data = document.dataRepresentation() else { return nil }
        return (try? data.write(to: destination, options: .atomic)) != nil ? destination : nil
    }

    private static func renderReflowPDF(
        book: Book,
        annotations: [Annotation],
        settings: ReaderSettings,
        destination: URL
    ) async -> Bool {
        let sourceURL = AppPaths.bookURL(book)

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = performReflowRender(
                    sourceURL: sourceURL,
                    book: book,
                    annotations: annotations,
                    settings: settings,
                    destination: destination
                )
                continuation.resume(returning: result)
            }
        }
    }

    private static func performReflowRender(
        sourceURL: URL,
        book: Book,
        annotations: [Annotation],
        settings: ReaderSettings,
        destination: URL
    ) -> Bool {
        guard let document = PDFDocument(url: sourceURL) else { return false }

        let fingerprint = ReflowBuilder.fingerprint(for: sourceURL)
        var model = ReflowCache.load(bookID: book.id, fingerprint: fingerprint)
        if model == nil {
            model = ReflowBuilder.build(document: document, bookID: book.id, fingerprint: fingerprint)
            ReflowCache.save(model!)
        }
        guard let model, !model.runs.isEmpty else { return false }

        // A4 at 72dpi, which is what Kindle-style reflow exports look like.
        let pageSize = CGSize(width: 432, height: 648)
        let insets = UIEdgeInsets(top: 48, left: 48, bottom: 48, right: 48)
        let textSize = CGSize(
            width: pageSize.width - insets.left - insets.right,
            height: pageSize.height - insets.top - insets.bottom
        )
        let theme = ReaderTheme.theme(settings.theme)

        let attributed = ReflowTypography.attributedString(
            model: model,
            settings: settings,
            textAreaSize: textSize
        ) { pageIndex in
            guard let page = document.page(at: pageIndex) else { return nil }
            let bounds = page.bounds(for: .cropBox)
            guard bounds.width > 1, bounds.height > 1 else { return nil }
            let scale = (textSize.width * 2) / bounds.width
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.setFillColor(UIColor.white.cgColor)
                context.cgContext.fill(CGRect(origin: .zero, size: size))
                // PDF content is drawn in a y-up space; the renderer gives us y-down.
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                context.cgContext.scaleBy(x: scale, y: scale)
                context.cgContext.translateBy(x: -bounds.minX, y: -bounds.minY)
                page.draw(with: .cropBox, to: context.cgContext)
            }
        }

        let slices = Paginator.paginate(attributed, textRect: CGRect(origin: .zero, size: textSize))
        guard !slices.isEmpty else { return false }

        let spansByPage = annotations.compactMap { annotation -> (NSRange, Int, AnnotationKind)? in
            guard let range = annotation.locator.reflowRange else { return nil }
            return (range, annotation.colorIndex, annotation.kind)
        }

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: book.title,
            kCGPDFContextCreator as String: "Inkwell"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)

        let data = renderer.pdfData { context in
            for (pageNumber, slice) in slices.enumerated() {
                context.beginPage()
                let ctx = context.cgContext
                ctx.setFillColor(theme.background.cgColor)
                ctx.fill(CGRect(origin: .zero, size: pageSize))

                guard let layout = CTPageLayout(attributed: attributed, slice: slice, rect: UIKitSpaceRect(
                    rect: CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: textSize),
                    pageHeight: pageSize.height
                )) else { continue }

                let pageSpans = spansByPage.compactMap { span -> HighlightSpan? in
                    guard NSIntersectionRange(span.0, slice.range).length > 0 else { return nil }
                    return HighlightSpan(id: UUID(), range: span.0, colorIndex: span.1, kind: span.2)
                }

                ctx.saveGState()
                ctx.setFillColor(theme.text.cgColor)
                ReflowRenderer.drawPage(
                    layout: layout,
                    pageHeight: pageSize.height,
                    textRect: UIKitSpaceRect(
                        rect: CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: textSize),
                        pageHeight: pageSize.height
                    ),
                    context: ctx,
                    highlightSpans: pageSpans,
                    palette: theme.highlightPalette,
                    textColor: theme.text
                )
                ctx.restoreGState()

                let footer = "\(book.title) · \(pageNumber + 1)"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 8),
                    .foregroundColor: theme.secondary
                ]
                let footerSize = (footer as NSString).size(withAttributes: attributes)
                (footer as NSString).draw(
                    at: CGPoint(x: (pageSize.width - footerSize.width) / 2, y: pageSize.height - 30),
                    withAttributes: attributes
                )
            }
        }

        return (try? data.write(to: destination, options: .atomic)) != nil
    }

    private static func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let filtered = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let result = String(filtered).trimmingCharacters(in: .whitespaces)
        return result.isEmpty ? "book" : result
    }
}