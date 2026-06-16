import SwiftUI
import AppKit

/// 菜单栏应用主体。注意:入口在 main.swift(以支持 --render 截图模式),故此处不加 @main。
struct CoinBarApp: App {
    @StateObject private var model = TickerModel()

    var body: some Scene {
        MenuBarExtra {
            RootView(model: model)
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
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let green = NSColor(srgbRed: 0.09, green: 0.78, blue: 0.52, alpha: 1)
        let red = NSColor(srgbRed: 0.92, green: 0.22, blue: 0.26, alpha: 1)
        let upC = model.redUp ? red : green, downC = model.redUp ? green : red

        let attr = NSMutableAttributedString()
        let segs = model.barSegments()
        if segs.isEmpty {
            attr.append(NSAttributedString(string: "CoinBar",
                attributes: [.font: font, .foregroundColor: NSColor(white: 0.65, alpha: 1)]))
        } else {
            for (i, seg) in segs.enumerated() {
                if i > 0 {
                    attr.append(NSAttributedString(string: "   ", attributes: [.font: font]))
                }
                let arrow = seg.dir >= 0 ? "▲" : "▼"
                attr.append(NSAttributedString(string: "\(seg.base) \(seg.price)\(arrow)",
                    attributes: [.font: font, .foregroundColor: seg.dir >= 0 ? upC : downC]))
            }
        }
        let sz = attr.size()
        let img = NSImage(size: NSSize(width: ceil(sz.width) + 2, height: ceil(sz.height) + 2))
        img.lockFocus()
        attr.draw(at: NSPoint(x: 1, y: 1))
        img.unlockFocus()
        img.isTemplate = false   // 非模板 → 保留绿/红颜色
        return img
    }
}

/// 注入皮肤:外观(自动/浅/深,覆盖系统)+ 涨跌色(绿涨红跌 / 红涨绿跌)。
private struct RootView: View {
    @ObservedObject var model: TickerModel
    @Environment(\.colorScheme) private var systemScheme
    var body: some View {
        let scheme = model.forcedScheme ?? systemScheme
        var skin = (scheme == .dark) ? Skin.binance : .lightNative
        if model.redUp { skin = skin.swappingUpDown() }
        return PopoverView()
            .environmentObject(model)
            .environment(\.skin, skin)
            .environment(\.colorScheme, scheme)
    }
}
