import SwiftUI
import UIKit

/// A highlight stored as a normalised rectangle on a PDF page.
struct PDFRectMark: Hashable {
    var id: UUID
    var pageIndex: Int
    /// x, y, width, height — y measured from the top of the page, all 0...1.
    var normalizedRect: [Double]
    var colorIndex: Int
    var kind: AnnotationKind
}

/// Fallback renderer: shows the original PDF page fitted to the screen, with
/// rectangle highlights, pinch zoom and tap zones.
///
/// The page itself arrives as a pre-rendered, cached `UIImage` — re-running
/// `PDFPage.draw` on every swipe is far too slow.
final class PDFPageUIView: UIView {

    private var image: UIImage?
    private var theme: ReaderTheme = .light
    private var marks: [PDFRectMark] = []
    private var zoomScale: CGFloat = 1
    private var pendingRect: CGRect?

    var onTap: ((TapZone) -> Void)?
    var onRectSelected: ((CGRect) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0.35
        press.cancelsTouchesInView = false
        tap.require(toFail: press)
        addGestureRecognizer(tap)
        addGestureRecognizer(pinch)
        addGestureRecognizer(press)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func apply(image: UIImage?, theme: ReaderTheme, marks: [PDFRectMark]) {
        self.image = image
        self.theme = theme
        self.marks = marks
        backgroundColor = theme.background
        setNeedsDisplay()
    }

    func resetZoom() {
        zoomScale = 1
        setNeedsDisplay()
    }

    // MARK: - Geometry

    /// Where the page image currently sits inside the view.
    private var imageRect: CGRect {
        guard let image, let size = image.cgImage.map({ CGSize(width: $0.width, height: $0.height) }), size.width > 0, size.height > 0 else {
            return .zero
        }
        let fit = min(bounds.width / size.width, bounds.height / size.height) * zoomScale
        let width = size.width * fit
        let height = size.height * fit
        return CGRect(
            x: (bounds.width - width) / 2,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(theme.background.cgColor)
        context.fill(bounds)

        let frame = imageRect
        guard frame.width > 1, frame.height > 1, let image else { return }
        image.draw(in: frame)

        context.saveGState()
        for mark in marks {
            guard let target = Self.viewRect(for: mark, in: frame) else { continue }
            let color = mark.kind == .underline
                ? theme.text.withAlphaComponent(0.8)
                : theme.highlightColor(mark.colorIndex)
            context.setFillColor(color.cgColor)
            if mark.kind == .underline {
                context.fill(CGRect(x: target.minX, y: target.maxY - 1.5, width: target.width, height: 1.5))
            } else {
                context.fill(target)
            }
        }
        if let pending = pendingRect {
            context.setFillColor(theme.highlightColor(0).cgColor)
            context.fill(pending)
        }
        context.restoreGState()
    }

    private static func viewRect(for mark: PDFRectMark, in frame: CGRect) -> CGRect? {
        guard mark.normalizedRect.count == 4 else { return nil }
        let rect = CGRect(
            x: frame.minX + CGFloat(mark.normalizedRect[0]) * frame.width,
            y: frame.minY + CGFloat(mark.normalizedRect[1]) * frame.height,
            width: CGFloat(mark.normalizedRect[2]) * frame.width,
            height: CGFloat(mark.normalizedRect[3]) * frame.height
        )
        guard rect.width > 0.5, rect.height > 0.5 else { return nil }
        return rect
    }

    /// Converts a view rectangle into normalised page coordinates for storage.
    private func normalised(_ rect: CGRect) -> CGRect? {
        let frame = imageRect
        guard frame.width > 1, frame.height > 1 else { return nil }
        let clipped = rect.standardized.intersection(frame)
        guard !clipped.isNull, clipped.width > 0.01, clipped.height > 0.01 else { return nil }
        return CGRect(
            x: (clipped.minX - frame.minX) / frame.width,
            y: (clipped.minY - frame.minY) / frame.height,
            width: clipped.width / frame.width,
            height: clipped.height / frame.height
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: - Gestures

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        if zoomScale > 1.02 {
            resetZoom()
            return
        }
        onTap?(tapZone(for: recognizer.location(in: self)))
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .changed:
            zoomScale = min(max(zoomScale * recognizer.scale, 1), 5)
            recognizer.scale = 1
            setNeedsDisplay()
        case .ended, .cancelled, .failed:
            if zoomScale < 1.05 { resetZoom() }
        default:
            break
        }
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            pendingRect = CGRect(origin: point, size: .zero)
            setNeedsDisplay()
        case .changed:
            guard let start = pendingRect?.origin else { return }
            pendingRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            setNeedsDisplay()
        case .ended:
            let rect = pendingRect
            pendingRect = nil
            setNeedsDisplay()
            if let rect, rect.width > 10, rect.height > 10, let value = normalised(rect) {
                onRectSelected?(value)
            }
        default:
            pendingRect = nil
            setNeedsDisplay()
        }
    }

    private func tapZone(for point: CGPoint) -> TapZone {
        guard bounds.width > 0 else { return .menu }
        let fraction = point.x / bounds.width
        if fraction < 0.28 { return .previous }
        if fraction > 0.72 { return .next }
        return .menu
    }
}

extension PDFPageUIView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        false
    }
}

/// SwiftUI bridge for `PDFPageUIView`.
struct PDFPageContainer: UIViewRepresentable {

    let image: UIImage?
    let theme: ReaderTheme
    let marks: [PDFRectMark]

    var onTap: (TapZone) -> Void
    var onRectSelected: (CGRect) -> Void

    func makeUIView(context: Context) -> PDFPageUIView {
        let view = PDFPageUIView()
        view.onTap = { [onTap] in onTap($0) }
        view.onRectSelected = { [onRectSelected] in onRectSelected($0) }
        return view
    }

    func updateUIView(_ uiView: PDFPageUIView, context: Context) {
        uiView.onTap = { [onTap] in onTap($0) }
        uiView.onRectSelected = { [onRectSelected] in onRectSelected($0) }
        uiView.apply(image: image, theme: theme, marks: marks)
    }
}