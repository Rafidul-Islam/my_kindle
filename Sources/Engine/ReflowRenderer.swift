import UIKit
import CoreText

enum TapZone {
    case previous
    case next
    case menu
}

/// Wraps one Core Text frame plus the line geometry we need for hit testing and
/// highlight placement.
final class CTPageLayout {

    let frame: CTFrame
    let lines: [CTLine]
    let origins: [CGPoint]
    let slice: PageSlice

    init?(attributed: NSAttributedString, slice: PageSlice, rect: UIKitSpaceRect) {
        guard attributed.length > 0, slice.start >= 0, slice.start < attributed.length else { return nil }
        guard rect.size.width > 1, rect.size.height > 1 else { return nil }

        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let cgRect = rect.coreTextRect(pageHeight: rect.pageHeight)
        let path = CGPath(rect: cgRect, transform: nil)

        guard let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: slice.start, length: 0), path, nil) else {
            return nil
        }
        self.frame = frame
        self.slice = slice

        let cfLines = CTFrameGetLines(frame)
        let count = CFArrayGetCount(cfLines)
        var collected: [CTLine] = []
        collected.reserveCapacity(count)
        for index in 0..<count {
            guard let pointer = CFArrayGetValueAtIndex(cfLines, index) else { continue }
            collected.append(unsafeBitCast(pointer, to: CTLine.self))
        }
        self.lines = collected

        var points = [CGPoint](repeating: .zero, count: max(count, 1))
        if count > 0 {
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &points)
        }
        self.origins = points
    }

    /// Nearest character index for a touch point given in UIKit coordinates (y-down).
    func characterIndex(at point: CGPoint, pageHeight: CGFloat) -> Int? {
        guard !lines.isEmpty else { return nil }
        let probe = CGPoint(x: point.x, y: pageHeight - point.y)

        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for (index, line) in lines.enumerated() {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let origin = origins[index]
            let verticalDistance = max(origin.y - ascent - probe.y, 0) + max(probe.y - (origin.y + descent), 0)

            if verticalDistance <= 1, best == nil {
                let location = CTLineGetStringIndexForPosition(line, probe, nil)
                if location != kCFNotFound {
                    return clamped(Int(location), toLine: index)
                }
            }

            if verticalDistance < bestDistance {
                bestDistance = verticalDistance
                let location = CTLineGetStringIndexForPosition(line, CGPoint(x: min(max(probe.x, 0), width), y: probe.y), nil)
                best = location == kCFNotFound ? best : clamped(Int(location), toLine: index)
            }
        }
        return best
    }

    private func clamped(_ value: Int, toLine index: Int) -> Int {
        let range = CTLineGetStringRange(lines[index])
        return min(max(value, Int(range.location)), Int(NSMaxRange(range)))
    }

    /// Rects covering `range`, expressed in Core Text (y-up) coordinates.
    func rects(for range: NSRange, includeZeroLength: Bool = false) -> [CGRect] {
        var results: [CGRect] = []
        for (index, line) in lines.enumerated() {
            guard index < origins.count else { break }
            let lineRange = CTLineGetStringRange(line)

            let overlaps = NSIntersectionRange(lineRange, range)
            let containsCaret = includeZeroLength
                && range.length == 0
                && range.location >= Int(lineRange.location)
                && range.location <= Int(NSMaxRange(lineRange))

            guard overlaps.length > 0 || containsCaret else { continue }

            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

            var startX: CGFloat = 0
            var endX = lineWidth

            if overlaps.length > 0 {
                if overlaps.location > Int(lineRange.location) {
                    startX = CGFloat(CTLineGetOffsetForStringIndex(line, overlaps.location, nil))
                }
                if NSMaxRange(overlaps) < NSMaxRange(lineRange) {
                    endX = CGFloat(CTLineGetOffsetForStringIndex(line, NSMaxRange(overlaps), nil))
                }
            } else {
                let x = CGFloat(CTLineGetOffsetForStringIndex(line, range.location, nil))
                startX = x
                endX = min(lineWidth, x + 3)
            }

            let rect = CGRect(
                x: origins[index].x + startX,
                y: origins[index].y - descent,
                width: max(1, endX - startX),
                height: ascent + descent
            )
            results.append(rect)
        }
        return results
    }

    /// Baseline rects used for underline annotations.
    func underlineRects(for range: NSRange) -> [CGRect] {
        rects(for: range).map { rect in
            CGRect(x: rect.minX, y: rect.minY + 1, width: rect.width, height: 1.5)
        }
    }
}

/// A rectangle plus the page height it lives on, so it can be converted between
/// UIKit's y-down space and Core Text's y-up space.
struct UIKitSpaceRect {
    var rect: CGRect
    var pageHeight: CGFloat

    var size: CGSize { rect.size }

    func coreTextRect(pageHeight height: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

enum ReflowRenderer {

    static let selectionColor = UIColor.systemBlue.withAlphaComponent(0.32)

    /// Draws one reflow page into `context`, which is expected to be in UIKit
    /// coordinates (origin top-left, y down) — the same space a `UIView` or a
    /// `UIGraphicsPDFRenderer` page uses.
    static func drawPage(
        layout: CTPageLayout,
        pageHeight: CGFloat,
        textRect: UIKitSpaceRect,
        context: CGContext,
        highlightSpans: [HighlightSpan],
        palette: [UIColor],
        textColor: UIColor
    ) {
        context.saveGState()

        // Flip into Core Text's y-up space.
        context.translateBy(x: 0, y: pageHeight)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity

        context.clip(to: textRect.coreTextRect(pageHeight: pageHeight))

        for span in highlightSpans {
            let isSelection = span.kind == .note && span.colorIndex < 0
            let color: UIColor
            if isSelection {
                color = selectionColor
            } else if span.kind == .underline {
                color = textColor.withAlphaComponent(0.85)
            } else if palette.isEmpty {
                color = selectionColor
            } else {
                color = palette[((span.colorIndex % palette.count) + palette.count) % palette.count]
            }

            let rects = span.kind == .underline
                ? layout.underlineRects(for: span.range)
                : layout.rects(for: span.range, includeZeroLength: isSelection)

            context.setFillColor(color.cgColor)
            for rect in rects {
                if span.kind == .underline {
                    context.fill(CGRect(x: rect.minX, y: rect.minY + 3, width: rect.width, height: rect.height))
                } else {
                    context.fill(rect.insetBy(dx: 0, dy: -1))
                }
            }
        }

        CTFrameDraw(layout.frame, context)
        context.restoreGState()
    }
}