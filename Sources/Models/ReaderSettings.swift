import Foundation
import UIKit

enum ThemeID: String, Codable, CaseIterable, Sendable {
    case light, sepia, dark, black

    var title: String {
        switch self {
        case .light: return "Paper"
        case .sepia: return "Sepia"
        case .dark: return "Night"
        case .black: return "OLED"
        }
    }
}

enum FontFamilyID: String, Codable, CaseIterable, Sendable {
    case serif, sans, charter

    var title: String {
        switch self {
        case .serif: return "Serif"
        case .sans: return "Sans"
        case .charter: return "Charter"
        }
    }
}

struct ReaderSettings: Codable, Hashable, Sendable {
    var theme: ThemeID = .light
    var fontFamily: FontFamilyID = .serif
    /// Index into `ReaderSettings.fontSizes`.
    var fontStep: Int = 2
    var marginStep: Int = 1
    var extraLineSpacing: Double = 4
    var justified: Bool = true
    var hyphenation: Bool = true
    var pageTurnAnimation: PageTurnStyle = .slide
    /// 0.35...1.0 dimming overlay strength.
    var brightness: Double = 1.0

    static let fontSizes: [CGFloat] = [15, 17, 19, 21, 23, 26, 29]

    static let `default` = ReaderSettings()

    var fontSize: CGFloat {
        let index = min(max(fontStep, 0), ReaderSettings.fontSizes.count - 1)
        return ReaderSettings.fontSizes[index]
    }

    var fontSizeLabel: String {
        switch fontStep {
        case ...0: return "A-"
        case 1: return "A"
        case 2: return "A+"
        case 3: return "A++"
        default: return "A+++"
        }
    }

    var insets: UIEdgeInsets {
        let horizontal: CGFloat = [22, 34, 48][min(max(marginStep, 0), 2)]
        let vertical: CGFloat = [28, 40, 56][min(max(marginStep, 0), 2)]
        return UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    var marginLabel: String {
        switch marginStep {
        case ...0: return "Narrow"
        case 1: return "Normal"
        default: return "Wide"
        }
    }
}

enum PageTurnStyle: String, Codable, CaseIterable, Sendable {
    case slide
    case none
}