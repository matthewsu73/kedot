import SwiftUI

// Stable raw values keep saved preferences compatible between releases.
enum WidgetTheme: String, CaseIterable, Identifiable {
    case mint, ocean, iris, rose, sunset, cream
    var id: String { rawValue }
    var name: String {
        switch self {
        case .mint: return "薄荷青"
        case .ocean: return "海盐蓝"
        case .iris: return "鸢尾紫"
        case .rose: return "莓果粉"
        case .sunset: return "落日橙"
        case .cream: return "奶油白"
        }
    }
    var accent: Color {
        switch self {
        case .mint: return Color(hex: 0x72EBC8)
        case .ocean: return Color(hex: 0x79BFFF)
        case .iris: return Color(hex: 0xBCA3FF)
        case .rose: return Color(hex: 0xFFA4C4)
        case .sunset: return Color(hex: 0xFFBC80)
        case .cream: return Color(hex: 0x94613B)
        }
    }
    var background: Color {
        switch self {
        case .mint: return Color(hex: 0x101D20)
        case .ocean: return Color(hex: 0x111D2B)
        case .iris: return Color(hex: 0x20192E)
        case .rose: return Color(hex: 0x291B26)
        case .sunset: return Color(hex: 0x29201A)
        case .cream: return Color(hex: 0xF9F4E9)
        }
    }
    var foreground: Color { self == .cream ? Color(hex: 0x352E26) : Color(hex: 0xF3F6F8) }
    var muted: Color { foreground.opacity(self == .cream ? 0.70 : 0.60) }
    var faint: Color { foreground.opacity(self == .cream ? 0.62 : 0.50) }
    var border: Color { foreground.opacity(self == .cream ? 0.12 : 0.10) }
    var card: Color { self == .cream ? Color.white.opacity(0.66) : Color.white.opacity(0.045) }
    var colorScheme: ColorScheme { self == .cream ? .light : .dark }
}
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255)
    }
}
enum WidgetPreferences {
    static let defaults: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["BILI_TRACKER_PREFERENCES_SUITE"], let value = UserDefaults(suiteName: suite) { return value }
        return .standard
    }()
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var name: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
}
struct ThemePalette {
    let theme: WidgetTheme
    let dark: Bool
    var accent: Color {
        if dark { return theme == .cream ? Color(hex: 0xE8C99E) : theme.accent }
        let values: [WidgetTheme: UInt32] = [.mint:0x16765E,.ocean:0x2267A2,.iris:0x7050AC,.rose:0xAB416A,.sunset:0x9A561E,.cream:0x94613B]
        return Color(hex:values[theme]!)
    }
    var background: Color {
        if dark { return theme == .cream ? Color(hex:0x27231E) : theme.background }
        let values: [WidgetTheme: UInt32] = [.mint:0xF0F8F3,.ocean:0xF0F5FB,.iris:0xF5F1FB,.rose:0xFCF1F5,.sunset:0xFCF4EC,.cream:0xF9F4E9]
        return Color(hex:values[theme]!)
    }
    var foreground: Color { dark ? Color(hex:0xF3F6F8) : Color(hex:0x28332E) }
    var muted: Color { foreground.opacity(dark ? 0.65 : 0.73) }
    var faint: Color { foreground.opacity(dark ? 0.53 : 0.63) }
    var border: Color { foreground.opacity(0.12) }
    var card: Color { dark ? Color.white.opacity(0.045) : Color.white.opacity(0.70) }
    var colorScheme: ColorScheme { dark ? .dark : .light }
}
