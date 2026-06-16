import SwiftUI

/// 菜单栏应用主体。注意:入口在 main.swift(以支持 --render 截图模式),故此处不加 @main。
struct CoinBarApp: App {
    @StateObject private var model = TickerModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
                .onAppear { model.start() }
        } label: {
            Text(model.barText)
        }
        .menuBarExtraStyle(.window)   // .window 让弹出内容是真正的面板(可放搜索框/列表)
    }
}
