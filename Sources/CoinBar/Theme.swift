import SwiftUI

/// 全局视觉规范:配色、字体、间距。集中在这里便于统一调整外观。
enum Theme {
    // 涨跌色(参考主流行情站,既鲜明又不刺眼)
    static let up   = Color(red: 0.09, green: 0.78, blue: 0.52)   // #16C784
    static let down = Color(red: 0.92, green: 0.22, blue: 0.26)   // #EA3943
    static let accent = Color(red: 0.95, green: 0.73, blue: 0.05) // #F0B90B 币安金,点缀用

    static func changeColor(_ pct: Double) -> Color { pct >= 0 ? up : down }

    // 等宽数字字体(价格/百分比对齐)
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
