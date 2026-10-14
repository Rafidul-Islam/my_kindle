import Foundation
import CoreGraphics

struct PageRunKey: Hashable, Sendable {
    var page: Int
    var run: Int
}

/// Heuristics that decide whether a page can be reflowed, and which lines are
/// running headers/footers that should not appear in the reflowed text.
enum LayoutAnalysis {

    static func medianLineHeight(_ lines: [LineBox]) -> Double {
        let heights = lines.map(\.rect.height).sorted()
        guard !heights.isEmpty else { return 0 }
        return heights[heights.count / 2]
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return nil }
        if sorted.count % 2 == 1 { return sorted[sorted.count / 2] }
        return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }

    /// A page is multi-column when a meaningful share of its lines sit fully to the left
    /// of a vertical gap and a meaningful share sit fully to the right of it.
    static func isMultiColumn(_ lines: [LineBox]) -> Bool {
        guard let pageWidth = lines.first?.pageWidth, pageWidth > 1 else { return false }

        // Full-width lines (titles, rules, spanning headings) would confuse a gap test.
        let candidates = lines.filter { $0.rect.width <= pageWidth * 0.75 }
        guard candidates.count >= 12 else { return false }

        let threshold = Double(candidates.count) * 0.35
        for step in 1...14 {
            let gapFraction = 0.15 + Double(step) * 0.05
            let gapX = CGFloat(gapFraction) * pageWidth
            let left = candidates.filter { $0.rect.maxX <= gapX }.count
            let right = candidates.filter { $0.rect.minX >= gapX }.count
            if Double(left) > threshold, Double(right) > threshold {
                return true
            }
        }
        return false
    }

    /// Identifies running headers and footers: text that repeats in the top or bottom
    /// band on a large share of pages, plus standalone page numbers.
    static func headerFooterRuns(pages: [ExtractedPage], bandFraction: Double = 0.08, minimumPages: Int = 3) -> Set<PageRunKey> {
        guard pages.count >= minimumPages else { return [] }

        var occurrences: [String: [PageRunKey]] = [:]
        var bandRunCount = 0

        for page in pages {
            for (runIndex, run) in page.runs.enumerated() {
                guard run.rect.count == 4 else { continue }
                let yTop = run.rect[1]
                let height = run.rect[3]
                let inBand = yTop <= bandFraction || (yTop + height) >= (1.0 - bandFraction)
                guard inBand else { continue }
                bandRunCount += 1
                let key = normalised(run.text)
                occurrences[key, default: []].append(PageRunKey(page: page.index, run: runIndex))
            }
        }

        let minimumOccurrences = max(minimumPages, Int((Double(pages.count) * 0.5).rounded(.up)))
        var drop = Set<PageRunKey>()
        for (_, keys) in occurrences {
            if keys.count >= minimumOccurrences {
                drop.formUnion(keys)
            }
        }
        // Always drop bare page numbers sitting in the margin band.
        for page in pages {
            for (runIndex, run) in page.runs.enumerated() {
                guard run.rect.count == 4 else { continue }
                let yTop = run.rect[1]
                let height = run.rect[3]
                let inBand = yTop <= bandFraction || (yTop + height) >= (1.0 - bandFraction)
                if inBand, isPageNumber(run.text) {
                    drop.insert(PageRunKey(page: page.index, run: runIndex))
                }
            }
        }
        _ = bandRunCount
        return drop
    }

    private static func normalised(_ text: String) -> String {
        var scalars = String()
        for scalar in text.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.unicodeScalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func isPageNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 8 else { return false }
        var sawDigit = false
        for character in trimmed {
            if character.isNumber {
                sawDigit = true
            } else if !" ivxlcdmIVXLCDM".contains(character) {
                return false
            }
        }
        return sawDigit
    }
}