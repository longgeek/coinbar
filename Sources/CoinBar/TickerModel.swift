import SwiftUI
import Combine

/// 应用状态:自选、行情、搜索、菜单栏文案。
@MainActor
final class TickerModel: ObservableObject {
    @Published var watchlist: [String]   // 自选交易对(全大写,e.g. BTCUSDT)
    @Published var tickers: [String: Ticker] = [:]
    @Published var query: String = ""
    @Published var allSymbols: [String] = []     // 搜索用的全量符号
    @Published var lastUpdated: Date?
    @Published var barPinned: String?             // 菜单栏显示哪个币(nil=第一个)

    private var prevPrice: [String: Double] = [:] // 变价闪烁基线
    @Published var flash: [String: Int] = [:]     // +1/-1/0
    private var timer: Timer?

    init(watchlist: [String] = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"], autostart: Bool = true) {
        self.watchlist = UserDefaults.standard.stringArray(forKey: "watchlist") ?? watchlist
        self.barPinned = UserDefaults.standard.string(forKey: "barPinned")
        if autostart { start() }   // 启动即抓数据(不必等用户点开面板)
    }

    func start() {
        Task { await refresh() }
        Task { allSymbols = await BinanceAPI.fetchAllSymbols() }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        let syms = watchlist
        guard !syms.isEmpty else { tickers = [:]; return }
        var map = tickers                                  // 保留上次,避免瞬时缺失闪烁
        let spot = await BinanceAPI.fetchSpot(syms)
        for t in spot { map[t.symbol] = t }
        // 现货拿不到的(纯合约币)→ 走合约接口
        let spotSet = Set(spot.map { $0.symbol })
        let missing = syms.filter { !spotSet.contains($0) }
        if !missing.isEmpty {
            for t in await BinanceAPI.fetchFutures(missing) { map[t.symbol] = t }
        }
        for sym in syms {                                  // 变价方向(脉冲/闪烁)
            if let t = map[sym] {
                let dir = prevPrice[sym].map { t.lastPrice > $0 ? 1 : (t.lastPrice < $0 ? -1 : 0) } ?? 0
                flash[sym] = dir
                prevPrice[sym] = t.lastPrice
            }
        }
        tickers = map.filter { syms.contains($0.key) }     // 清理已移除的
        lastUpdated = Date()
    }

    // 菜单栏文案
    var barText: String {
        let sym = barPinned ?? watchlist.first
        guard let sym, let t = tickers[sym] else { return "CoinBar" }
        return "\(t.base) \(Fmt.price(t.lastPrice))"
    }

    /// 菜单栏方向(按 24h 涨跌,始终有值 → 箭头宽度稳定不抖):+1 涨 / -1 跌 / 0 无数据。
    var barDir: Int {
        let sym = barPinned ?? watchlist.first
        guard let sym, let t = tickers[sym] else { return 0 }
        return t.changePct >= 0 ? 1 : -1
    }

    // 当前应展示的列表(空搜索=自选;有搜索=过滤全量符号)
    var displayed: [String] {
        if query.isEmpty { return watchlist }
        let q = query.uppercased()
        return allSymbols.filter { $0.contains(q) }
            .sorted { a, b in
                func rank(_ s: String) -> (Int, Int, Int) {
                    (s.hasPrefix(q) ? 0 : 1, s.hasSuffix("USDT") ? 0 : 1, s.count)
                }
                return rank(a) < rank(b)
            }
            .prefix(40).map { $0 }
    }

    func isWatched(_ sym: String) -> Bool { watchlist.contains(sym) }

    func toggleWatch(_ sym: String) {
        if let i = watchlist.firstIndex(of: sym) {
            watchlist.remove(at: i)
            if barPinned == sym { barPinned = nil }
        } else {
            watchlist.append(sym)
            Task { await refresh() }
        }
        persist()
    }

    func setBarPinned(_ sym: String) {
        barPinned = (barPinned == sym) ? nil : sym
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(watchlist, forKey: "watchlist")
        UserDefaults.standard.set(barPinned, forKey: "barPinned")
    }

    /// 截图预览用的假数据。
    static func mock() -> TickerModel {
        let m = TickerModel(watchlist: ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"], autostart: false)
        m.tickers = [
            "BTCUSDT": Ticker(symbol: "BTCUSDT", lastPrice: 66430.12, changePct: 1.32, high: 67255, low: 65469, quoteVolume: 10_900_000_000),
            "ETHUSDT": Ticker(symbol: "ETHUSDT", lastPrice: 1762.40, changePct: 3.45, high: 1849, low: 1712, quoteVolume: 4_800_000_000),
            "SOLUSDT": Ticker(symbol: "SOLUSDT", lastPrice: 73.68, changePct: -2.11, high: 76, low: 70.8, quoteVolume: 2_060_000_000),
            "BNBUSDT": Ticker(symbol: "BNBUSDT", lastPrice: 612.91, changePct: -0.63, high: 620, low: 605, quoteVolume: 837_000_000),
        ]
        m.flash = ["BTCUSDT": 1, "ETHUSDT": 1, "SOLUSDT": -1, "BNBUSDT": 0]
        m.barPinned = "BTCUSDT"
        m.lastUpdated = Date()
        return m
    }
}
