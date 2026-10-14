import UIKit

/// Colours for one of the four reading themes.
struct ReaderTheme: Equatable {
    var background: UIColor
    var text: UIColor
    var secondary: UIColor
    var isDark: Bool
    var highlightPalette: [UIColor]

    func highlightColor(_ index: Int) -> UIColor {
        guard !highlightPalette.isEmpty else { return .systemYellow }
        return highlightPalette[((index % highlightPalette.count) + highlightPalette.count) % highlightPalette.count]
    }

    static let light = ReaderTheme(
        background: UIColor(white: 0.99, alpha: 1),
        text: UIColor(white: 0.10, alpha: 1),
        secondary: UIColor(white: 0.45, alpha: 1),
        isDark: false,
        highlightPalette: [
            UIColor(red: 1.00, green: 0.87, blue: 0.30, alpha: 0.55),
            UIColor(red: 0.62, green: 0.90, blue: 0.66, alpha: 0.55),
            UIColor(red: 0.55, green: 0.78, blue: 1.00, alpha: 0.55),
            UIColor(red: 1.00, green: 0.66, blue: 0.66, alpha: 0.55),
            UIColor(red: 0.82, green: 0.70, blue: 1.00, alpha: 0.55),
        ]
    )

    static let sepia = ReaderTheme(
        background: UIColor(red: 0.96, green: 0.91, blue: 0.80, alpha: 1),
        text: UIColor(red: 0.22, green: 0.17, blue: 0.11, alpha: 1),
        secondary: UIColor(red: 0.48, green: 0.40, blue: 0.30, alpha: 1),
        isDark: false,
        highlightPalette: [
            UIColor(red: 0.98, green: 0.83, blue: 0.30, alpha: 0.60),
            UIColor(red: 0.62, green: 0.86, blue: 0.58, alpha: 0.60),
            UIColor(red: 0.55, green: 0.75, blue: 0.96, alpha: 0.60),
            UIColor(red: 0.98, green: 0.62, blue: 0.55, alpha: 0.60),
            UIColor(red: 0.80, green: 0.66, blue: 0.98, alpha: 0.60),
        ]
    )

    static let dark = ReaderTheme(
        background: UIColor(white: 0.13, alpha: 1),
        text: UIColor(white: 0.86, alpha: 1),
        secondary: UIColor(white: 0.55, alpha: 1),
        isDark: true,
        highlightPalette: [
            UIColor(red: 0.98, green: 0.80, blue: 0.25, alpha: 0.42),
            UIColor(red: 0.45, green: 0.82, blue: 0.52, alpha: 0.42),
            UIColor(red: 0.36, green: 0.66, blue: 0.98, alpha: 0.42),
            UIColor(red: 0.98, green: 0.47, blue: 0.45, alpha: 0.42),
            UIColor(red: 0.68, green: 0.52, blue: 0.98, alpha: 0.42),
        ]
    )

    static let black = ReaderTheme(
        background: UIColor.black,
        text: UIColor(white: 0.80, alpha: 1),
        secondary: UIColor(white: 0.48, alpha: 1),
        isDark: true,
        highlightPalette: [
            UIColor(red: 0.95, green: 0.75, blue: 0.22, alpha: 0.38),
            UIColor(red: 0.40, green: 0.78, blue: 0.48, alpha: 0.38),
            UIColor(red: 0.32, green: 0.62, blue: 0.95, alpha: 0.38),
            UIColor(red: 0.95, green: 0.42, blue: 0.40, alpha: 0.38),
            UIColor(red: 0.64, green: 0.48, blue: 0.95, alpha: 0.38),
        ]
    )

    static func theme(_ id: ThemeID) -> ReaderTheme {
        switch id {
        case .light: return .light
        case .sepia: return .sepia
        case .dark: return .dark
        case .black: return .black
        }
    }
}