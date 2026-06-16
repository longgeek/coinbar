import SwiftUI
import UniformTypeIdentifiers

/// 菜单栏点击后弹出的主面板:搜索框 + 币列表 + 底栏。
struct PopoverView: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    @FocusState private var searchFocused: Bool
    @State private var showSettings = false
    @State private var detailSym: String?
    @State private var dragWatch: String?   // 拖拽排序中的交易对(跨行共享)
    var preview: Bool = false   // 截图模式:用静态控件替代 TextField,便于离屏渲染

    var body: some View {
        Group {
            if let dsym = detailSym {
                DetailView(sym: dsym, dismiss: { detailSym = nil })
            } else if showSettings {
                SettingsView(show: $showSettings)
            } else {
                VStack(spacing: 0) {
                    header
                    Divider().overlay(skin.hairline)
                    list
                    Divider().overlay(skin.hairline)
                    footer
                }
            }
        }
        .frame(width: 360)
        .background(skin.bg)
    }

    // MARK: 顶部搜索
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            if preview {
                Text("搜索币种,如 doge / pepe…")
                    .font(Theme.rounded(14)).foregroundStyle(.tertiary)
                Spacer()
            } else {
                TextField("搜索币种,如 doge / pepe…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(Theme.rounded(14))
                    .focused($searchFocused)
            }
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: 列表
    private var list: some View {
        Group {
            if preview {
                listContent            // 截图模式:无 ScrollView(ImageRenderer 不渲染其内容)
            } else {
                ScrollView { listContent }.frame(height: listHeight)   // .window 下必须给确定高度,否则塌缩
            }
        }
    }

    // 列表高度:按行数估算,封顶 380 后滚动;空态给固定高度。
    private var listHeight: CGFloat {
        let n = model.query.isEmpty ? model.watchlist.count : model.displayed.count
        if n == 0 { return 140 }
        return min(CGFloat(n) * 52 + 12, 380)
    }

    private var listContent: some View {
        VStack(spacing: 2) {
            if model.query.isEmpty {
                if model.watchlist.isEmpty {
                    empty
                } else {
                    ForEach(model.watchlist, id: \.self) { sym in
                        WatchRow(sym: sym, onOpen: { detailSym = $0 }, dragging: $dragWatch, preview: preview).environmentObject(model)
                    }
                }
            } else {
                ForEach(model.displayed, id: \.self) { sym in
                    SearchRow(sym: sym).environmentObject(model)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(.tertiary)
            Text("自选为空").font(Theme.rounded(13)).foregroundStyle(.secondary)
            Text("上方搜索添加币种").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    // MARK: 底栏
    private var footer: some View {
        HStack(spacing: 10) {
            Circle().fill(skin.up).frame(width: 6, height: 6)
                .opacity(model.lastUpdated == nil ? 0 : 1)
            Text(updatedText).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }.buttonStyle(.plain).help("立即刷新")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
            }.buttonStyle(.plain).help("设置")
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }.buttonStyle(.plain).help("退出 CoinBar")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var updatedText: String {
        guard let d = model.lastUpdated else { return "连接中…" }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return "更新于 \(f.string(from: d))"
    }
}

/// 自选行:左侧操作(拖拽手柄 + 置顶 + 移除)+ 符号/现货合约标记 + 迷你 K 线 + 价格。
struct WatchRow: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    let sym: String
    var onOpen: (String) -> Void = { _ in }
    @Binding var dragging: String?
    var preview: Bool = false   // 截图模式:跳过拖拽,避免 ImageRenderer 画出占位符
    @State private var hover = false
    @State private var pulse: Double = 0
    @State private var pulseUp = true

    var body: some View {
        let t = model.tickers[sym]
        let pinned = model.isPinned(sym)
        let isFut = model.futuresSyms.contains(sym)
        HStack(spacing: 8) {
            // 左侧操作:拖拽手柄(拖拽源)/ 置顶 / 移除
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .help("拖拽排序")
                .applyIf(!preview) { v in
                    v.onDrag({
                        dragging = sym
                        return NSItemProvider(object: sym as NSString)
                    }, preview: {
                        Text(t?.base ?? sym)
                            .font(Theme.rounded(13, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(skin.rowHover))
                    })
                }
            Button { model.togglePin(sym) } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundStyle(pinned ? skin.accent : Color.secondary.opacity(0.45))
            }.buttonStyle(.plain).help(pinned ? "已固定到菜单栏" : "固定到菜单栏")
            Button { model.toggleWatch(sym) } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(skin.down.opacity(0.7))
            }.buttonStyle(.plain).help("移除自选")

            // 符号 + 现货/合约标记(标记放第二行,不占主行宽度,给 K 线让地方)
            VStack(alignment: .leading, spacing: 2) {
                Text(t?.base ?? sym).font(Theme.rounded(14, weight: .semibold))
                HStack(spacing: 4) {
                    Text(isFut ? "合约" : "现货")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isFut ? skin.accent : Color.secondary)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill((isFut ? skin.accent : Color.secondary).opacity(0.15)))
                    Text(sym).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }

            // 迷你 K 线:弹性宽度,填满中间空白
            if let s = model.spark[sym], s.count >= 2 {
                Sparkline(data: s, color: (s.last! >= s.first!) ? skin.up : skin.down)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .padding(.horizontal, 6)
            } else {
                Spacer(minLength: 8)
            }

            if let t {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.price(t.lastPrice))
                        .font(Theme.mono(13, weight: .medium))
                        .foregroundStyle(flashColor(model.flash[sym] ?? 0))
                    ChangePill(pct: t.changePct)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill((pulseUp ? skin.up : skin.down).opacity(0.40 * pulse)))
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? skin.rowHover : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(skin.accent.opacity(dragging == sym ? 0.6 : 0), lineWidth: 1.5))
        .opacity(dragging == sym ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { onOpen(sym) }
        .applyIf(!preview) { v in
            v.onDrop(of: [.text], delegate: WatchReorderDelegate(target: sym, model: model, dragging: $dragging))
        }
        .onChange(of: t?.lastPrice) { _ in
            let d = model.flash[sym] ?? 0
            guard d != 0 else { return }
            pulseUp = d > 0
            pulse = 1                                   // 先点亮(这一帧)
            DispatchQueue.main.async {                  // 下一帧再动画淡出,避免被合并掉
                withAnimation(.easeOut(duration: 0.8)) { pulse = 0 }
            }
        }
    }

    private func flashColor(_ d: Int) -> Color {
        d > 0 ? skin.up : (d < 0 ? skin.down : .primary)
    }
}

/// 自选行拖拽重排:拖到某行上方,即把被拖项移到该行之前。
private struct WatchReorderDelegate: DropDelegate {
    let target: String
    let model: TickerModel
    @Binding var dragging: String?

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func dropEntered(info: DropInfo) {
        guard let from = dragging, from != target else { return }
        MainActor.assumeIsolated {
            withAnimation(.easeInOut(duration: 0.18)) { model.moveWatch(from, to: target) }
        }
    }
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

extension View {
    /// 条件化套用修饰符。用于截图模式跳过拖拽,避免 ImageRenderer 渲染出占位符。
    @ViewBuilder func applyIf<V: View>(_ condition: Bool, _ transform: (Self) -> V) -> some View {
        if condition { transform(self) } else { self }
    }
}

/// 搜索结果行:符号 + 添加/已添加。
struct SearchRow: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    let sym: String
    @State private var hover = false

    var body: some View {
        let added = model.isWatched(sym)
        let base = Ticker(symbol: sym, lastPrice: 0, changePct: 0, high: 0, low: 0, quoteVolume: 0).base
        HStack(spacing: 10) {
            Text(base).font(Theme.rounded(14, weight: .semibold))
            Text(sym).font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button { model.toggleWatch(sym) } label: {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(added ? skin.up : skin.accent)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? skin.rowHover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

/// 涨跌幅胶囊。
struct ChangePill: View {
    @Environment(\.skin) private var skin
    let pct: Double
    var body: some View {
        Text(Fmt.pct(pct))
            .font(Theme.mono(10, weight: .semibold))
            .foregroundStyle(skin.change(pct))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(skin.change(pct).opacity(0.18)))
    }
}

/// 迷你 K 线:近 24h 收盘价折线 + 渐变面积,按净涨跌着色。
struct Sparkline: View {
    let data: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let lo = data.min() ?? 0, hi = data.max() ?? 1
            let span = hi - lo
            let pts: [CGPoint] = data.enumerated().map { i, v in
                CGPoint(x: w * CGFloat(i) / CGFloat(max(data.count - 1, 1)),
                        y: span > 0 ? h - h * CGFloat((v - lo) / span) : h / 2)
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: w, y: h)); p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                Path { p in
                    p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
