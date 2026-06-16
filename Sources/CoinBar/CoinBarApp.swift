import SwiftUI
import AppKit

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

/// 菜单栏标签。macOS 会把文字标签强制单色,所以渲染成「非模板彩色图片」:
/// 等宽数字(不抖)+ 按 24h 涨跌整体着色(绿/红,深浅菜单栏都清晰)。
struct BarLabel: View {
    @ObservedObject var model: TickerModel
    var body: some View {
        Image(nsImage: barImage)
    }

    private var barImage: NSImage {
        let d = model.barDir
        let arrow = d == 0 ? "" : (d > 0 ? "  ▲" : "  ▼")
        let text = model.barText + arrow
        let color: NSColor = d == 0 ? NSColor(white: 0.65, alpha: 1)
            : (d > 0 ? NSColor(srgbRed: 0.09, green: 0.78, blue: 0.52, alpha: 1)
                     : NSColor(srgbRed: 0.92, green: 0.22, blue: 0.26, alpha: 1))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        let img = NSImage(size: NSSize(width: ceil(sz.width) + 2, height: ceil(sz.height) + 2))
        img.lockFocus()
        s.draw(at: NSPoint(x: 1, y: 1))
        img.unlockFocus()
        img.isTemplate = false   // 关键:非模板 → 保留绿/红颜色
        return img
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
