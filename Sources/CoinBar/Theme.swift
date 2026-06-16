import SwiftUI

/// 一套可切换的视觉皮肤(配色 + 背景)。通过 Environment 注入,便于整体换肤与做风格预览。
struct Skin: Equatable {
    let id: String
    let displayName: String
    let dark: Bool
    let up: Color
    let down: Color
    let accent: Color
    let bg: AnyShapeStyle
    let rowHover: Color
    let hairline: Color

    func change(_ p: Double) -> Color { p >= 0 ? up : down }
    static func == (a: Skin, b: Skin) -> Bool { a.id == b.id }

    /// A. 清爽原生:浅色材质 + 克制配色,最贴近 macOS 系统观感。
    static let lightNative = Skin(
        id: "light", displayName: "清爽原生", dark: false,
        up: Color(red: 0.09, green: 0.78, blue: 0.52),
        down: Color(red: 0.92, green: 0.22, blue: 0.26),
        accent: Color(red: 0.95, green: 0.73, blue: 0.05),
        bg: AnyShapeStyle(.regularMaterial),
        rowHover: Color.primary.opacity(0.06),
        hairline: Color.primary.opacity(0.08))

    /// B. 深色终端:近黑底 + 霓虹涨跌色,数据密集、专业感。
    static let darkTerminal = Skin(
        id: "dark", displayName: "深色终端", dark: true,
        up: Color(red: 0.00, green: 0.90, blue: 0.62),
        down: Color(red: 1.00, green: 0.38, blue: 0.42),
        accent: Color(red: 0.40, green: 0.72, blue: 1.00),
        bg: AnyShapeStyle(Color(red: 0.055, green: 0.067, blue: 0.086)),
        rowHover: Color.white.opacity(0.07),
        hairline: Color.white.opacity(0.08))

    /// C. 币安金:黑金品牌感。
    static let binance = Skin(
        id: "binance", displayName: "币安金", dark: true,
        up: Color(red: 0.01, green: 0.75, blue: 0.46),
        down: Color(red: 0.96, green: 0.27, blue: 0.36),
        accent: Color(red: 0.95, green: 0.73, blue: 0.05),
        bg: AnyShapeStyle(Color(red: 0.078, green: 0.082, blue: 0.098)),
        rowHover: Color(red: 0.95, green: 0.73, blue: 0.05).opacity(0.10),
        hairline: Color.white.opacity(0.07))

    static let all = [lightNative, darkTerminal, binance]
    static func byId(_ id: String) -> Skin { all.first { $0.id == id } ?? lightNative }
}

enum Theme {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

private struct SkinKey: EnvironmentKey { static let defaultValue: Skin = .lightNative }
extension EnvironmentValues {
    var skin: Skin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}
