import UIKit

extension NSAttributedString.Key {
    /// Source PDF page index for the run — powers progress, TOC and the page counter.
    static let inkwellPageIndex = NSAttributedString.Key("InkwellPageIndex")
}

/// Builds the drawable attributed string for one book at one set of reader settings.
enum ReflowTypography {

    static func font(
        settings: ReaderSettings,
        pdfSize: Double,
        bold: Bool,
        italic: Bool,
        heading: Bool
    ) -> UIFont {
        let base = settings.fontSize
        let multiplier = heading ? 1.22 : 1.0
        let size = max(8, min(72, base * CGFloat(multiplier)))
        return resolveFont(family: settings.fontFamily, size: size, bold: bold || heading, italic: italic)
    }

    static func resolveFont(family: FontFamilyID, size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        let base = baseFont(family: family, size: size)
        guard bold || italic else { return base }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }

        // Serif designs can lose their family when traits are applied, so validate.
        if let descriptor = base.fontDescriptor.withSymbolicTraits(traits) {
            let candidate = UIFont(descriptor: descriptor, size: size)
            if candidate.pointSize > 0 { return candidate }
        }
        if bold, family == .sans {
            return UIFont.systemFont(ofSize: size, weight: .semibold)
        }
        return base
    }

    static func baseFont(family: FontFamilyID, size: CGFloat) -> UIFont {
        switch family {
        case .sans:
            return UIFont.systemFont(ofSize: size)
        case .serif:
            let system = UIFont.systemFont(ofSize: size)
            if let descriptor = system.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return system
        case .charter:
            if let font = UIFont(name: "Charter-Roman", size: size) ?? UIFont(name: "Charter", size: size) {
                return font
            }
            let system = UIFont.systemFont(ofSize: size)
            if let descriptor = system.fontDescriptor.withDesign(.serif) {
                return UIFont(descriptor: descriptor, size: size)
            }
            return system
        }
    }

    static func paragraphStyle(settings: ReaderSettings, heading: Bool, paragraphStart: Bool) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = settings.justified && !heading ? .justified : .left
        style.lineSpacing = CGFloat(settings.extraLineSpacing)
        style.paragraphSpacing = paragraphStart ? CGFloat(settings.extraLineSpacing * 1.4) : 0
        style.lineHeightMultiple = heading ? 1.05 : 1.0
        style.hyphenationFactor = settings.hyphenation ? 1.0 : 0.0
        style.usesDefaultHyphenation = settings.hyphenation
        style.hyphenationPunctuationOverride = .standard
        style.firstLineHeadIndent = 0
        style.headIndent = 0
        style.tailIndent = 0
        style.lineBreakMode = .byWordWrapping
        style.baseWritingDirection = .natural
        return style
    }

    /// `imageResolver` returns a rendered page image for a PDF page that could not be
    /// reflowed, scaled to the text column width.
    static func attributedString(
        model: ReflowModel,
        settings: ReaderSettings,
        textAreaSize: CGSize,
        imageResolver: (Int) -> UIImage?
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let full = model.text as NSString

        // Fonts and paragraph styles are shared between runs to keep memory in check.
        var fontCache: [String: UIFont] = [:]
        var styleCache: [String: NSParagraphStyle] = [:]

        for run in model.runs {
            guard run.loc >= 0, NSMaxRange(run.range) <= full.length else { continue }

            if run.kind == .image {
                guard let attachment = pageAttachment(
                    pageIndex: run.pageIndex,
                    width: textAreaSize.width,
                    maxHeight: textAreaSize.height,
                    resolver: imageResolver
                ) else { continue }
                let length = output.length
                output.append(NSAttributedString(attachment: attachment))
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                style.paragraphSpacing = CGFloat(settings.extraLineSpacing * 2)
                output.addAttributes(
                    [.paragraphStyle: style, .inkwellPageIndex: run.pageIndex],
                    range: NSRange(location: length, length: output.length - length)
                )
                continue
            }

            let fontKey = "\(run.size)-\(run.bold)-\(run.italic)-\(run.heading)"
            let font = fontCache[fontKey] ?? font(
                settings: settings, pdfSize: run.size, bold: run.bold, italic: run.italic, heading: run.heading
            )
            fontCache[fontKey] = font

            let styleKey = "\(run.heading)-\(run.paragraphStart)"
            let paragraphStyle = styleCache[styleKey] ?? paragraphStyle(
                settings: settings, heading: run.heading, paragraphStart: run.paragraphStart
            )
            styleCache[styleKey] = paragraphStyle

            let length = output.length
            output.append(NSAttributedString(string: full.substring(with: run.range)))
            // No `.foregroundColor` here on purpose: Core Text falls back to the
            // context's fill colour, which is how the reader themes the text.
            output.addAttributes(
                [
                    .font: font,
                    .paragraphStyle: paragraphStyle,
                    .inkwellPageIndex: run.pageIndex
                ],
                range: NSRange(location: length, length: output.length - length)
            )
        }
        return output
    }

    private static func pageAttachment(
        pageIndex: Int,
        width: CGFloat,
        maxHeight: CGFloat,
        resolver: (Int) -> UIImage?
    ) -> NSTextAttachment? {
        guard width > 10, maxHeight > 10, let image = resolver(pageIndex) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        let sourceWidth = max(image.size.width, 1)
        let sourceHeight = max(image.size.height, 1)
        var targetWidth = width
        var targetHeight = targetWidth * (sourceHeight / sourceWidth)
        if targetHeight > maxHeight {
            targetHeight = maxHeight
            targetWidth = targetHeight * (sourceWidth / sourceHeight)
        }
        attachment.bounds = CGRect(x: 0, y: -6, width: targetWidth, height: targetHeight)
        return attachment
    }
}