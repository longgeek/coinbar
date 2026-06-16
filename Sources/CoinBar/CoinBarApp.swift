import SwiftUI

/// 菜单栏应用主体。注意:入口在 main.swift(以支持 --render 截图模式),故此处不加 @main。
struct CoinBarApp: App {
    @StateObject private var model = TickerModel()

    var body: some Scene {
        MenuBarExtra {
            AutoSkinned { PopoverView() }
                .environmentObject(model)
        } label: {
            Text(model.barText)
        }
        .menuBarExtraStyle(.window)   // .window 让弹出内容是真正的面板(可放搜索框/列表)
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
