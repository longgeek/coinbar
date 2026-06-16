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
    static func == (a: Skin, b: Skin) -> Bool { a.id == b.id && a.up == b.up }

    /// 互换涨跌色(红涨绿跌,A股习惯)。
    func swappingUpDown() -> Skin {
        Skin(id: id + "-r", displayName: displayName, dark: dark,
             up: down, down: up, accent: accent, bg: bg, rowHover: rowHover, hairline: hairline)
    }

    /// A. GitHub Light:纯白底 + GitHub 配色。浅色模式用它。
    static let lightNative = Skin(
        id: "light", displayName: "GitHub 浅色", dark: false,
        up: Color(hex: 0x1A7F37),
        down: Color(hex: 0xCF222E),
        accent: Color(hex: 0x0969DA),
        bg: AnyShapeStyle(Color.white),
        rowHover: Color.black.opacity(0.05),
        hairline: Color.black.opacity(0.10))

    /// B. 深色终端:近黑底 + 霓虹涨跌色,数据密集、专业感。
    static let darkTerminal = Skin(
        id: "dark", displayName: "深色终端", dark: true,
        up: Color(red: 0.00, green: 0.90, blue: 0.62),
        down: Color(red: 1.00, green: 0.38, blue: 0.42),
        accent: Color(red: 0.40, green: 0.72, blue: 1.00),
        bg: AnyShapeStyle(Color(red: 0.055, green: 0.067, blue: 0.086)),
        rowHover: Color.white.opacity(0.07),
        hairline: Color.white.opacity(0.08))

    /// C. GitHub Dark Dimmed:柔和深色(#22272E)+ GitHub 配色。深色模式用它。
    static let binance = Skin(
        id: "binance", displayName: "GitHub Dimmed", dark: true,
        up: Color(hex: 0x57AB5A),
        down: Color(hex: 0xE5534B),
        accent: Color(hex: 0x539BF5),
        bg: AnyShapeStyle(Color(hex: 0x22272E)),
        rowHover: Color.white.opacity(0.06),
        hairline: Color.white.opacity(0.09))

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
