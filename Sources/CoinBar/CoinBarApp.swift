import SwiftUI
import AppKit
import Combine

/// 自管理的菜单栏应用外壳:NSStatusItem(彩色标签) + 自定义可成为 key 的 NSPanel。
///
/// 为什么不用 MenuBarExtra:它的 .window 弹窗是非激活临时面板,无法成为 key window,
/// 而 NSTableView 的拖拽重排需要窗口能成为 key 才能追踪鼠标 —— 故弹窗里怎么都拖不动。
/// 自己管理一个 canBecomeKey=true 的 NSPanel 即可让原生拖拽正常工作(Yahoo 财经同理,用的是真窗口)。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = TickerModel()
    private var statusItem: NSStatusItem!
    private var panel: CoinPanel?
    private var hosting: NSHostingView<RootContent>?
    private var labelObserver: AnyCancellable?
    private var lastClose: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        updateLabel()
        // 行情/设置变化时刷新菜单栏标签(receive(on:) 确保读到变更后的值)。
        labelObserver = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.updateLabel() } }
    }

    // MARK: 菜单栏彩色标签(非模板 NSImage,保留绿/红)
    @MainActor private func updateLabel() {
        guard let button = statusItem?.button else { return }
        let img = Self.barImage(model: model)
        img.isTemplate = false
        button.image = img
    }

    @MainActor private static func barImage(model: TickerModel) -> NSImage {
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
                if i > 0 { attr.append(NSAttributedString(string: "   ", attributes: [.font: font])) }
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
        return img
    }

    // MARK: 面板开关
    @objc private func togglePanel() {
        if let last = lastClose, Date().timeIntervalSince(last) < 0.2 { return }  // 防 resignKey 关闭后立刻重开
        if let p = panel, p.isVisible { closePanel() } else { openPanel() }
    }

    private func openPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        applyAppearance(to: panel)
        sizeAndPosition(panel)
        panel.makeKeyAndOrderFront(nil)   // 成为 key(非激活面板,不抢占其它 app 焦点),拖拽与输入均可用
    }

    private func closePanel() {
        lastClose = Date()
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { closePanel() }   // 点面板外即关闭

    private func makePanel() -> CoinPanel {
        let host = NSHostingView(rootView: RootContent(model: model))
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        hosting = host
        let panel = CoinPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = host
        return panel
    }

    private func applyAppearance(to panel: CoinPanel) {
        switch model.appearance {
        case "light": panel.appearance = NSAppearance(named: .aqua)
        case "dark": panel.appearance = NSAppearance(named: .darkAqua)
        default: panel.appearance = nil   // 跟随系统
        }
    }

    private func sizeAndPosition(_ panel: CoinPanel) {
        guard let host = hosting else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let w = size.width > 0 ? size.width : 360
        let h = size.height > 0 ? size.height : 420
        panel.setContentSize(NSSize(width: w, height: h))
        guard let btnWin = statusItem.button?.window else { panel.center(); return }
        let frame = btnWin.frame
        let screen = btnWin.screen ?? NSScreen.main
        let vis = screen?.visibleFrame ?? frame
        let x = min(max(frame.midX - w / 2, vis.minX + 8), vis.maxX - w - 8)
        let y = frame.minY - h - 4
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// 可成为 key 的无边框面板 —— 关键点:让内部 NSTableView 的拖拽能被追踪。
final class CoinPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// 注入皮肤的根内容(外观自动/浅/深 + 涨跌色)。等价于原 MenuBarExtra 的 RootView。
struct RootContent: View {
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
            .fixedSize()   // 让 NSHostingView 能按内容算出 fittingSize
    }
}
