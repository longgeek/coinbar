import SwiftUI
import AppKit

// 入口:支持 --render-popover <path> 截图模式(便于设计迭代),否则正常启动菜单栏应用。
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-icon"), i + 1 < args.count {
    MainActor.assumeIsolated { Screenshot.renderIcon(to: args[i + 1]) }
} else if let i = args.firstIndex(of: "--render-settings"), i + 1 < args.count {
    var skin = Skin.lightNative
    if let j = args.firstIndex(of: "--skin"), j + 1 < args.count { skin = Skin.byId(args[j + 1]) }
    MainActor.assumeIsolated { Screenshot.renderSettings(to: args[i + 1], skin: skin) }
} else if let i = args.firstIndex(of: "--render-detail"), i + 1 < args.count {
    var skin = Skin.lightNative, sym = "SOLUSDT"
    if let j = args.firstIndex(of: "--skin"), j + 1 < args.count { skin = Skin.byId(args[j + 1]) }
    if let j = args.firstIndex(of: "--sym"), j + 1 < args.count { sym = args[j + 1] }
    MainActor.assumeIsolated { Screenshot.renderDetail(to: args[i + 1], sym: sym, skin: skin) }
} else if let i = args.firstIndex(of: "--render-popover"), i + 1 < args.count {
    var skin = Skin.lightNative
    if let j = args.firstIndex(of: "--skin"), j + 1 < args.count {
        skin = Skin.byId(args[j + 1])
    }
    MainActor.assumeIsolated {
        Screenshot.renderPopover(to: args[i + 1], skin: skin)
    }
} else {
    // 自管理 NSStatusItem + NSPanel(见 AppDelegate),而非 MenuBarExtra —— 为了让拖拽可用。
    MainActor.assumeIsolated {
        let delegate = AppDelegate()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.setActivationPolicy(.accessory)   // 等价 LSUIElement:无 Dock 图标
        NSApplication.shared.run()
    }
}
