import SwiftUI
import UIKit

/// One screen of reflowed text. Draws a Core Text frame, highlights stored marks and
/// turns touches into either a tap zone or a word selection.
final class ReflowPageUIView: UIView {

    private(set) var layout: CTPageLayout?
    private var attributed: NSAttributedString?
    private var slice: PageSlice?
    private var textRect: UIKitSpaceRect?
    private var palette: [UIColor] = ReaderTheme.light.highlightPalette
    private var textColor: UIColor = .black
    private var backgroundColorValue: UIColor = .white
    private var spans: [HighlightSpan] = []
    private var currentInsets: UIEdgeInsets = .zero

    var onTap: ((TapZone) -> Void)?
    var onSelectionFinished: ((NSRange) -> Void)?

    private var anchorOffset: Int?
    private var focusOffset: Int?
    private var dragStart: CGPoint = .zero
    private var didDrag = false
    private let selectionSlop: CGFloat = 8

    // MARK: - Configuration

    func apply(
        attributed: NSAttributedString,
        slice: PageSlice,
        insets: UIEdgeInsets,
        theme: ReaderTheme,
        spans: [HighlightSpan]
    ) {
        let previousAttributed = self.attributed
        let previousSlice = self.slice
        self.attributed = attributed
        self.slice = slice
        currentInsets = insets

        let targetRect = textAreaRect
        let needsRebuild = previousAttributed !== attributed
            || previousSlice != slice
            || textRect?.rect != targetRect
            || textRect?.pageHeight != bounds.height

        if previousAttributed !== attributed || previousSlice != slice {
            // A different page means the old selection is meaningless.
            anchorOffset = nil
            focusOffset = nil
        }

        self.palette = theme.highlightPalette
        self.textColor = theme.text
        self.backgroundColorValue = theme.background
        self.spans = spans

        backgroundColor = theme.background

        if needsRebuild || layout == nil {
            rebuildLayout(insets: insets)
        }
        setNeedsDisplay()
    }

    func clearSelection() {
        anchorOffset = nil
        focusOffset = nil
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let slice, let attributed else { return }
        let rect = textAreaRect
        if textRect?.rect != rect || textRect?.pageHeight != bounds.height {
            let space = UIKitSpaceRect(rect: rect, pageHeight: bounds.height)
            textRect = space
            layout = CTPageLayout(attributed: attributed, slice: slice, rect: space)
            setNeedsDisplay()
        }
    }

    private var textAreaRect: CGRect {
        CGRect(
            origin: CGPoint(x: currentInsets.left, y: currentInsets.top),
            size: CGSize(
                width: max(bounds.width - currentInsets.left - currentInsets.right, 1),
                height: max(bounds.height - currentInsets.top - currentInsets.bottom, 1)
            )
        )
    }

    private func rebuildLayout(insets: UIEdgeInsets) {
        currentInsets = insets
        let rect = textAreaRect
        let space = UIKitSpaceRect(rect: rect, pageHeight: bounds.height)
        textRect = space
        layout = attributed.flatMap {
            CTPageLayout(attributed: $0, slice: slice ?? PageSlice(start: 0, length: 0), rect: space)
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(backgroundColorValue.cgColor)
        context.fill(bounds)

        guard let layout, let textRect else { return }
        var allSpans = spans
        if let selection = currentSelectionRange() {
            allSpans.append(HighlightSpan(id: UUID(), range: selection, colorIndex: -1, kind: .note))
        }

        context.saveGState()
        context.setFillColor(textColor.cgColor)
        ReflowRenderer.drawPage(
            layout: layout,
            pageHeight: bounds.height,
            textRect: textRect,
            context: context,
            highlightSpans: allSpans,
            palette: palette,
            textColor: textColor
        )
        context.restoreGState()
    }

    // MARK: - Selection

    private func currentSelectionRange() -> NSRange? {
        guard let anchor = anchorOffset, let focus = focusOffset else { return nil }
        let lower = min(anchor, focus)
        let upper = max(anchor, focus)
        guard upper > lower else { return nil }
        return NSRange(location: lower, length: upper - lower)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        dragStart = touch.location(in: self)
        didDrag = false
        anchorOffset = nil
        focusOffset = nil
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, let attributed else { return }
        let point = touch.location(in: self)

        if !didDrag {
            let distance = hypot(point.x - dragStart.x, point.y - dragStart.y)
            guard distance > selectionSlop else { return }
            didDrag = true
            guard let layout = self.layout, let startIndex = layout.characterIndex(at: dragStart, pageHeight: bounds.height) else {
                return
            }
            let word = Self.wordRange(in: attributed, around: startIndex)
            anchorOffset = word.location
            focusOffset = NSMaxRange(word)
        }

        if didDrag, let layout = self.layout, let current = layout.characterIndex(at: point, pageHeight: bounds.height) {
            focusOffset = wordBoundary(in: attributed, at: current)
            setNeedsDisplay()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if !didDrag {
            onTap?(tapZone(for: dragStart))
            return
        }
        finishSelection()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        anchorOffset = nil
        focusOffset = nil
        setNeedsDisplay()
    }

    private func finishSelection() {
        guard let range = currentSelectionRange() else {
            anchorOffset = nil
            focusOffset = nil
            setNeedsDisplay()
            return
        }
        onSelectionFinished?(range)
    }

    private func wordBoundary(in attributed: NSAttributedString, at offset: Int) -> Int {
        let range = Self.wordRange(in: attributed, around: offset)
        // Whichever word edge is nearer the touch wins.
        let centre = range.location + range.length / 2
        return offset >= centre ? NSMaxRange(range) : range.location
    }

    private func tapZone(for point: CGPoint) -> TapZone {
        let width = bounds.width
        guard width > 0 else { return .menu }
        let fraction = point.x / width
        if fraction < 0.28 { return .previous }
        if fraction > 0.72 { return .next }
        return .menu
    }

    // MARK: - Word snapping

    static func wordRange(in attributed: NSAttributedString, around index: Int) -> NSRange {
        let string = attributed.string as NSString
        let length = string.length
        guard length > 0 else { return NSRange(location: 0, length: 0) }
        let clamped = min(max(index, 0), length - 1)

        func isWord(at position: Int) -> Bool {
            guard position >= 0, position < length else { return false }
            let unit = string.character(at: position)
            guard let scalar = UnicodeScalar(unit) else { return false }
            if CharacterSet.alphanumerics.contains(scalar) { return true }
            return scalar == "'" || scalar == "\u{2019}"
        }

        var probe = clamped
        if !isWord(at: probe) {
            var forward = probe
            while forward < length, !isWord(at: forward) { forward += 1 }
            var backward = probe
            while backward > 0, !isWord(at: backward - 1) { backward -= 1 }
            probe = (length - forward) <= backward ? forward : backward - 1
            if !isWord(at: probe) {
                return NSRange(location: clamped, length: 1)
            }
        }

        var start = probe
        while start > 0, isWord(at: start - 1) { start -= 1 }
        var end = probe
        while end < length, isWord(at: end) { end += 1 }
        return NSRange(location: start, length: max(end - start, 1))
    }
}

/// SwiftUI bridge for `ReflowPageUIView`.
struct ReflowPageContainer: UIViewRepresentable {

    let attributed: NSAttributedString
    let slice: PageSlice
    let insets: UIEdgeInsets
    let theme: ReaderTheme
    let spans: [HighlightSpan]

    var onTap: (TapZone) -> Void
    var onSelectionFinished: (NSRange) -> Void

    func makeUIView(context: Context) -> ReflowPageUIView {
        let view = ReflowPageUIView()
        view.onTap = { [onTap] in onTap($0) }
        view.onSelectionFinished = { [onSelectionFinished] in onSelectionFinished($0) }
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ uiView: ReflowPageUIView, context: Context) {
        uiView.onTap = { [onTap] in onTap($0) }
        uiView.onSelectionFinished = { [onSelectionFinished] in onSelectionFinished($0) }
        uiView.apply(attributed: attributed, slice: slice, insets: insets, theme: theme, spans: spans)
    }
}