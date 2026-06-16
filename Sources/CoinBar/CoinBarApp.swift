import SwiftUI

/// 菜单栏应用主体。注意:入口在 main.swift(以支持 --render 截图模式),故此处不加 @main。
struct CoinBarApp: App {
    @StateObject private var model = TickerModel()

    var body: some Scene {
        MenuBarExtra {
            AutoSkinned { PopoverView() }
                .environmentObject(model)
        } label: {
            BarLabel(model: model)
        }
        .menuBarExtraStyle(.window)   // .window 让弹出内容是真正的面板(可放搜索框/列表)
    }
}

/// 菜单栏标签:等宽数字(避免跳动)+ 24h 方向箭头(绿涨红跌)。
struct BarLabel: View {
    @ObservedObject var model: TickerModel
    var body: some View {
        let d = model.barDir
        let arrow = d == 0 ? "" : (d > 0 ? "  ▲" : "  ▼")
        let color = d >= 0 ? Color(hex: 0x16C784) : Color(hex: 0xEA3943)
        return Text(model.barText).monospacedDigit()
            + Text(arrow).foregroundColor(color)
    }
}

/// 跟随系统浅/深色自动选皮肤:浅=清爽原生,深=币安金。
private struct AutoSkinned<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content
    var body: some View {
        content.environment(\.skin, colorScheme == .dark ? .binance : .lightNative)
    }
}
