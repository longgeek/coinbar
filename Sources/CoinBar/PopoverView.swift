import SwiftUI

/// 菜单栏点击后弹出的主面板:搜索框 + 币列表 + 底栏。
struct PopoverView: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    @FocusState private var searchFocused: Bool
    var preview: Bool = false   // 截图模式:用静态控件替代 TextField,便于离屏渲染

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(skin.hairline)
            list
            Divider().overlay(skin.hairline)
            footer
        }
        .frame(width: 330)
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
                        WatchRow(sym: sym).environmentObject(model)
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

/// 自选行:置顶星 + 符号 + 价格(变价着色)+ 涨跌幅胶囊。
struct WatchRow: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    let sym: String
    @State private var hover = false
    @State private var pulse: Double = 0
    @State private var pulseUp = true

    var body: some View {
        let t = model.tickers[sym]
        let pinned = model.barPinned == sym
        HStack(spacing: 10) {
            Button { model.setBarPinned(sym) } label: {
                Image(systemName: pinned ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(pinned ? skin.accent : Color.secondary.opacity(0.5))
            }.buttonStyle(.plain).help(pinned ? "已在菜单栏显示" : "显示到菜单栏")

            VStack(alignment: .leading, spacing: 1) {
                Text(t?.base ?? sym).font(Theme.rounded(14, weight: .semibold))
                Text(sym).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
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
            if hover {
                Button { model.toggleWatch(sym) } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(skin.down.opacity(0.85))
                }.buttonStyle(.plain).help("移除")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill((pulseUp ? skin.up : skin.down).opacity(0.40 * pulse)))
        .background(RoundedRectangle(cornerRadius: 8).fill(hover ? skin.rowHover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
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
