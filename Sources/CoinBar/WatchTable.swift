import SwiftUI
import AppKit

/// 自选列表:纯 AppKit 的 NSTableView,行视图全部原生绘制 → 原生拖拽重排(悬浮行 + 蓝色插入线)。
/// 需配合可成为 key 的窗口(见 CoinPanel);在 MenuBarExtra 的非激活弹窗里拖拽不可用。
/// 价格/闪烁/K线由 updateNSView 主动刷新可见行。
struct WatchTable: NSViewRepresentable {
    @ObservedObject var model: TickerModel
    var skin: Skin
    var scheme: ColorScheme
    var onOpen: (String) -> Void

    static let dragType = NSPasteboard.PasteboardType("com.longgeek.coinbar.watch-symbol")

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.usesAutomaticRowHeights = false
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        if #available(macOS 11.0, *) { table.style = .plain }

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("coin"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)

        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.registerForDraggedTypes([WatchTable.dragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap
        table.target = context.coordinator
        table.action = #selector(Coordinator.rowClicked(_:))   // 单击打开详情(点按钮由按钮自己消费;拖拽时不触发)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let coord = context.coordinator
        coord.parent = self
        guard let table = nsView.documentView as? NSTableView else { return }
        let rows: [RowData] = model.watchlist.map { sym in
            let t = model.tickers[sym]
            return RowData(sym: sym,
                           base: t?.base ?? Ticker(symbol: sym, lastPrice: 0, changePct: 0, high: 0, low: 0, quoteVolume: 0).base,
                           isFut: model.futuresSyms.contains(sym),
                           pinned: model.isPinned(sym),
                           hasTicker: t != nil,
                           priceText: t.map { Fmt.price($0.lastPrice) } ?? "—",
                           priceRaw: t?.lastPrice ?? 0,
                           pct: model.displayChange(sym),
                           flashDir: model.flash[sym] ?? 0,
                           spark: model.spark[sym] ?? [])
        }
        let colors = RowColors(up: NSColor(skin.up), down: NSColor(skin.down), accent: NSColor(skin.accent))
        let structural = coord.rows.map { $0.sym } != rows.map { $0.sym } || coord.skinId != skin.id
        coord.rows = rows
        coord.colors = colors
        coord.skinId = skin.id
        if structural { table.reloadData() } else { coord.refreshVisible(table) }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: WatchTable
        var rows: [RowData] = []          // 纯值快照,供代理方法读取(避免访问 @MainActor 的 model)
        var colors = RowColors(up: .systemGreen, down: .systemRed, accent: .systemYellow)
        var skinId: String = ""

        init(_ parent: WatchTable) { self.parent = parent }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 50 }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < rows.count else { return nil }
            let id = NSUserInterfaceItemIdentifier("WatchCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? WatchCellView)
                ?? { let c = WatchCellView(); c.identifier = id; return c }()
            apply(rows[row], to: cell)
            return cell
        }

        private func apply(_ d: RowData, to cell: WatchCellView) {
            let sym = d.sym
            cell.configure(d, colors: colors,
                           onPin: { [weak self] in self?.run { $0.togglePin(sym) } },
                           onRemove: { [weak self] in self?.run { $0.toggleWatch(sym) } })
        }

        func refreshVisible(_ tableView: NSTableView) {
            let range = tableView.rows(in: tableView.visibleRect)
            guard range.location != NSNotFound, range.length > 0 else { return }
            for row in range.location..<(range.location + range.length) where row < rows.count {
                if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? WatchCellView {
                    apply(rows[row], to: cell)
                }
            }
        }

        private func run(_ body: @escaping @MainActor (TickerModel) -> Void) {
            MainActor.assumeIsolated { body(parent.model) }
        }

        // MARK: 拖拽重排
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < rows.count else { return nil }
            let item = NSPasteboardItem()
            item.setString(rows[row].sym, forType: WatchTable.dragType)
            return item
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                       proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
            tableView.setDropRow(row, dropOperation: .above)   // 行间插入 → 蓝色插入线
            return .move
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                       row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
            guard let s = info.draggingPasteboard.string(forType: WatchTable.dragType),
                  let from = rows.firstIndex(where: { $0.sym == s }) else { return false }
            run { $0.moveWatch(from: from, to: row) }
            return true
        }

        @objc func rowClicked(_ sender: NSTableView) {
            let r = sender.clickedRow
            guard r >= 0, r < rows.count else { return }
            let sym = rows[r].sym
            MainActor.assumeIsolated { parent.onOpen(sym) }
        }
    }
}

/// 行数据快照(纯值类型)。
struct RowData {
    let sym, base: String
    let isFut, pinned, hasTicker: Bool
    let priceText: String
    let priceRaw, pct: Double
    let flashDir: Int
    let spark: [Double]
}

/// 皮肤色 → NSColor(涨/跌/强调)。其余用系统语义色。
struct RowColors {
    let up, down, accent: NSColor
}

/// 单行原生视图:置顶/移除按钮 + 符号/现货合约标记 + 迷你K线 + 价格/涨跌胶囊。整行可拖拽重排(由 NSTableView 驱动)。
final class WatchCellView: NSTableCellView {
    private let pinButton = NSButton()
    private let removeButton = NSButton()
    private let baseLabel = NSTextField(labelWithString: "")
    private let symbolLabel = NSTextField(labelWithString: "")
    private let badge = TagView(corner: 4)
    private let priceLabel = NSTextField(labelWithString: "")
    private let pill = TagView(corner: 8)
    private let spark = SparkView()
    var onPin, onRemove: (() -> Void)?
    private var lastPrice: Double?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        build()
    }
    required init?(coder: NSCoder) { fatalError("no coder") }

    private func build() {
        for b in [pinButton, removeButton] {
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.imagePosition = .imageOnly
            b.setButtonType(.momentaryChange)
            b.focusRingType = .none
        }
        pinButton.target = self; pinButton.action = #selector(pinTapped)
        removeButton.target = self; removeButton.action = #selector(removeTapped)

        baseLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        symbolLabel.font = .systemFont(ofSize: 10)
        symbolLabel.textColor = .tertiaryLabelColor
        priceLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        badge.font = .systemFont(ofSize: 9, weight: .semibold)
        pill.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)

        let symbolRow = NSStackView(views: [badge, symbolLabel])
        symbolRow.orientation = .horizontal; symbolRow.spacing = 4; symbolRow.alignment = .centerY
        let nameStack = NSStackView(views: [baseLabel, symbolRow])
        nameStack.orientation = .vertical; nameStack.alignment = .leading; nameStack.spacing = 2
        let priceStack = NSStackView(views: [priceLabel, pill])
        priceStack.orientation = .vertical; priceStack.alignment = .trailing; priceStack.spacing = 2

        for v in [pinButton, removeButton, nameStack, spark, priceStack] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        nameStack.setContentHuggingPriority(.required, for: .horizontal)
        priceStack.setContentHuggingPriority(.required, for: .horizontal)
        nameStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        priceStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        spark.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spark.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            pinButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            pinButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 18),
            pinButton.heightAnchor.constraint(equalToConstant: 18),
            removeButton.leadingAnchor.constraint(equalTo: pinButton.trailingAnchor, constant: 8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 18),
            removeButton.heightAnchor.constraint(equalToConstant: 18),
            nameStack.leadingAnchor.constraint(equalTo: removeButton.trailingAnchor, constant: 10),
            nameStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            spark.leadingAnchor.constraint(equalTo: nameStack.trailingAnchor, constant: 8),
            spark.trailingAnchor.constraint(equalTo: priceStack.leadingAnchor, constant: -8),
            spark.centerYAnchor.constraint(equalTo: centerYAnchor),
            spark.heightAnchor.constraint(equalToConstant: 26),
            priceStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            priceStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func pinTapped() { onPin?() }
    @objc private func removeTapped() { onRemove?() }

    func configure(_ d: RowData, colors c: RowColors, onPin: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.onPin = onPin; self.onRemove = onRemove

        pinButton.image = Self.symbol(d.pinned ? "pin.fill" : "pin", size: 12)
        // 未置顶用动态的 tertiaryLabelColor —— 自动按外观解析成浅/深灰;
        // 不能用 secondaryLabelColor.withAlphaComponent(),那会按当时外观定格成静态色,暗色下发黑。
        pinButton.contentTintColor = d.pinned ? c.accent : .tertiaryLabelColor
        pinButton.toolTip = d.pinned ? "已固定到菜单栏" : "固定到菜单栏"
        removeButton.image = Self.symbol("minus.circle.fill", size: 12)
        removeButton.contentTintColor = c.down.withAlphaComponent(0.75)
        removeButton.toolTip = "移除自选"

        baseLabel.stringValue = d.base
        symbolLabel.stringValue = d.sym
        badge.set(text: d.isFut ? "合约" : "现货", tint: d.isFut ? c.accent : .secondaryLabelColor)

        priceLabel.stringValue = d.priceText
        priceLabel.textColor = d.flashDir > 0 ? c.up : (d.flashDir < 0 ? c.down : .labelColor)
        pill.set(text: String(format: "%+.2f%%", d.pct), tint: d.pct >= 0 ? c.up : c.down)

        spark.isHidden = d.spark.count < 2
        spark.data = d.spark
        spark.color = (d.spark.last ?? 0) >= (d.spark.first ?? 0) ? c.up : c.down
        spark.needsDisplay = true

        if let last = lastPrice, last != d.priceRaw {       // 变价脉冲
            pulse(color: d.priceRaw > last ? c.up : c.down)
        }
        lastPrice = d.hasTicker ? d.priceRaw : nil
    }

    private func pulse(color: NSColor) {
        let anim = CABasicAnimation(keyPath: "backgroundColor")
        anim.fromValue = color.withAlphaComponent(0.40).cgColor
        anim.toValue = NSColor.clear.cgColor
        anim.duration = 0.8
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.add(anim, forKey: "pulse")
    }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }
}

/// 小圆角标签(现货/合约标记、涨跌幅胶囊)。
final class TagView: NSView {
    private let label = NSTextField(labelWithString: "")
    var font: NSFont = .systemFont(ofSize: 9, weight: .semibold) { didSet { label.font = font } }

    init(corner: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = corner
        label.font = font
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }
    required init?(coder: NSCoder) { fatalError("no coder") }

    func set(text: String, tint: NSColor) {
        label.stringValue = text
        label.textColor = tint
        layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
    }
}

/// 迷你 K 线:折线 + 渐变面积(非翻转坐标,高值在上)。
final class SparkView: NSView {
    var data: [Double] = []
    var color: NSColor = .systemGreen

    override func draw(_ dirtyRect: NSRect) {
        guard data.count >= 2 else { return }
        let w = bounds.width, h = bounds.height
        let lo = data.min() ?? 0, hi = data.max() ?? 1
        let span = hi - lo
        func pt(_ i: Int) -> NSPoint {
            let x = w * CGFloat(i) / CGFloat(max(data.count - 1, 1))
            let frac = span > 0 ? CGFloat((data[i] - lo) / span) : 0.5
            return NSPoint(x: x, y: h * frac)               // 高值 → 顶部
        }
        let area = NSBezierPath()
        area.move(to: NSPoint(x: 0, y: 0))
        for i in data.indices { area.line(to: pt(i)) }
        area.line(to: NSPoint(x: w, y: 0))
        area.close()
        NSGradient(colors: [color.withAlphaComponent(0.28), color.withAlphaComponent(0.0)])?
            .draw(in: area, angle: 90)                       // 顶部较浓 → 底部透明
        let line = NSBezierPath()
        line.move(to: pt(0))
        for i in 1..<data.count { line.line(to: pt(i)) }
        line.lineWidth = 1.5
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        color.setStroke()
        line.stroke()
    }
}
