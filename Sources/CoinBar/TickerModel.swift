import SwiftUI
import Combine
import ServiceManagement

/// 价格提醒:到达目标价触发(above=true 涨破 ≥price;false 跌破 ≤price)。一次性,触发后移除。
struct PriceAlert: Codable, Equatable, Identifiable {
    let sym: String
    let price: Double
    let above: Bool
    var id: String { "\(sym)|\(price)|\(above)" }
}

/// 应用状态:自选、行情、搜索、菜单栏文案。
@MainActor
final class TickerModel: ObservableObject {
    @Published var watchlist: [String]   // 自选交易对(全大写,e.g. BTCUSDT)
    @Published var tickers: [String: Ticker] = [:]
    @Published var query: String = ""
    @Published var allSymbols: [String] = []     // 搜索用的全量符号
    @Published var lastUpdated: Date?
    @Published var barCoins: [String]             // 菜单栏显示的币(可多个;空=显示首个自选)

    // 设置项(设置面板里可调)
    @Published var refreshSec: Int                // 刷新间隔(秒)
    @Published var redUp: Bool                    // true=红涨绿跌(A股) / false=绿涨红跌
    @Published var appearance: String             // auto | light | dark
    @Published var barStyle: String               // 菜单栏显示:price | change | both
    @Published var changeBasis: String            // 涨跌幅基准:24h | today
    @Published var lang: String { didSet { Localize.lang = lang } }   // 语言:auto | zh | en
    @Published var launchAtLogin: Bool             // 开机自启动(SMAppService)
    var onCheckForUpdates: (() -> Void)?           // 由 AppDelegate 注入(Sparkle 检查更新)

    private var prevPrice: [String: Double] = [:] // 变价闪烁基线
    @Published var flash: [String: Int] = [:]     // +1/-1/0
    @Published var spark: [String: [Double]] = [:] // 迷你 K 线收盘价序列(近 24h)
    @Published var dayOpen: [String: Double] = [:]  // 今日(UTC 00:00)开盘价,用于「今日」涨跌
    @Published var funding: [String: Funding] = [:] // 合约资金费率/标记价(详情页)
    @Published var futuresSyms: Set<String> = []    // 以合约数据展示的币
    @Published var alerts: [PriceAlert] = []         // 价格提醒(到价系统通知)
    private var timer: Timer?
    private var sparkTimer: Timer?

    init(watchlist: [String] = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"], autostart: Bool = true) {
        self.watchlist = UserDefaults.standard.stringArray(forKey: "watchlist") ?? watchlist
        self.barCoins = UserDefaults.standard.stringArray(forKey: "barCoins") ?? []
        if let d = UserDefaults.standard.data(forKey: "alerts"),
           let a = try? JSONDecoder().decode([PriceAlert].self, from: d) { self.alerts = a }
        self.refreshSec = UserDefaults.standard.object(forKey: "refreshSec") as? Int ?? 3
        self.redUp = UserDefaults.standard.bool(forKey: "redUp")
        self.appearance = UserDefaults.standard.string(forKey: "appearance") ?? "auto"
        self.barStyle = UserDefaults.standard.string(forKey: "barStyle") ?? "price"
        self.changeBasis = UserDefaults.standard.string(forKey: "changeBasis") ?? "24h"
        self.lang = UserDefaults.standard.string(forKey: "lang") ?? "auto"
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        if autostart {
            Localize.lang = self.lang   // 仅正常启动时同步;截图模式由 --lang 决定
            start()                     // 启动即抓数据(不必等用户点开面板)
        }
    }

    func start() {
        Task { await refresh() }
        Task { allSymbols = await BinanceAPI.fetchAllSymbols() }
        Task { await refreshSparks() }
        Task { await refreshDayOpens() }
        restartTimer()
        sparkTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { await self?.refreshSparks() }
            Task { await self?.refreshDayOpens() }
        }
    }

    /// 按当前 refreshSec 重建价格定时器(改间隔时调用)。
    func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(max(1, refreshSec)), repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// 外观覆盖:nil=跟随系统。
    var forcedScheme: ColorScheme? {
        switch appearance { case "light": return .light; case "dark": return .dark; default: return nil }
    }

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(refreshSec, forKey: "refreshSec")
        d.set(redUp, forKey: "redUp")
        d.set(appearance, forKey: "appearance")
        d.set(barStyle, forKey: "barStyle")
        d.set(changeBasis, forKey: "changeBasis")
        d.set(lang, forKey: "lang")
    }

    /// 开机自启动(macOS 13+ SMAppService);失败则回退到真实状态。
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("CoinBar 开机自启动设置失败: \(error)")
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func refreshSparks() async {
        for sym in watchlist {
            let c = await BinanceAPI.fetchKlines(sym)
            if !c.isEmpty { spark[sym] = c }
        }
    }

    /// 「今日」涨跌所需的日线开盘价(仅在该口径下抓)。
    func refreshDayOpens() async {
        guard changeBasis == "today" else { return }
        for sym in watchlist {
            if let o = await BinanceAPI.fetchDailyOpen(sym) { dayOpen[sym] = o }
        }
    }

    /// 按当前口径算涨跌幅(%):24h 用 Binance 滚动值;今日用 (现价-今开)/今开。
    func displayChange(_ sym: String) -> Double {
        guard let t = tickers[sym] else { return 0 }
        if changeBasis == "today", let o = dayOpen[sym], o > 0 {
            return (t.lastPrice - o) / o * 100
        }
        return t.changePct
    }

    /// 加载某合约币的资金费率/标记价(详情页打开时调用)。
    func loadFunding(_ sym: String) async {
        if let f = await BinanceAPI.fetchFunding(sym) { funding[sym] = f }
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
            let fut = await BinanceAPI.fetchFutures(missing)
            for t in fut { map[t.symbol] = t }
            futuresSyms = Set(fut.map { $0.symbol })   // 这些币以合约数据展示
        } else {
            futuresSyms = []
        }
        for sym in syms {                                  // 变价方向(脉冲/闪烁)
            if let t = map[sym] {
                let dir = prevPrice[sym].map { t.lastPrice > $0 ? 1 : (t.lastPrice < $0 ? -1 : 0) } ?? 0
                flash[sym] = dir
                prevPrice[sym] = t.lastPrice
            }
        }
        tickers = map.filter { syms.contains($0.key) }     // 清理已移除的
        checkAlerts()
        lastUpdated = Date()
    }

    // 菜单栏文案
    /// 菜单栏要显示的若干币:(基础符号, 价格文本, 方向 +1/-1)。空=显示首个自选。
    func barSegments() -> [(base: String, price: String, pct: String, dir: Int)] {
        // 钉住的币按「自选列表顺序」展示 → 拖动列表排序会同步到菜单栏。
        let coins = barCoins.isEmpty ? Array(watchlist.prefix(1)) : watchlist.filter { barCoins.contains($0) }
        return coins.compactMap { sym in
            guard let t = tickers[sym] else { return nil }
            let chg = displayChange(sym)
            return (t.base, Fmt.price(t.lastPrice), Fmt.pct(chg), chg >= 0 ? 1 : -1)
        }
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
            barCoins.removeAll { $0 == sym }
        } else {
            watchlist.append(sym)
            Task { await refresh() }
            Task { let c = await BinanceAPI.fetchKlines(sym); if !c.isEmpty { spark[sym] = c } }
            Task { if let o = await BinanceAPI.fetchDailyOpen(sym) { dayOpen[sym] = o } }
        }
        persist()
    }

    func isPinned(_ sym: String) -> Bool { barCoins.contains(sym) }

    func togglePin(_ sym: String) {
        if let i = barCoins.firstIndex(of: sym) { barCoins.remove(at: i) } else { barCoins.append(sym) }
        persist()
    }

    /// 拖拽重排自选(NSTableView:from=源行,to=目标插入行,插到该行之前)。
    func moveWatch(from: Int, to: Int) {
        guard from >= 0, from < watchlist.count, from != to else { return }
        let sym = watchlist.remove(at: from)
        let dest = to > from ? to - 1 : to
        watchlist.insert(sym, at: min(max(dest, 0), watchlist.count))
        persist()
    }

    // MARK: 价格提醒
    /// 加提醒:目标价 ≥ 现价 → 涨破触发;< 现价 → 跌破触发。
    func addAlert(_ sym: String, price: Double) {
        guard price > 0 else { return }
        let above = price >= (tickers[sym]?.lastPrice ?? price)
        let a = PriceAlert(sym: sym, price: price, above: above)
        guard !alerts.contains(a) else { return }
        alerts.append(a)
        persistAlerts()
        Notifier.requestAuth()
    }

    func removeAlert(_ a: PriceAlert) {
        alerts.removeAll { $0 == a }
        persistAlerts()
    }

    func alerts(for sym: String) -> [PriceAlert] {
        alerts.filter { $0.sym == sym }.sorted { $0.price > $1.price }
    }

    private func persistAlerts() {
        UserDefaults.standard.set(try? JSONEncoder().encode(alerts), forKey: "alerts")
    }

    /// 每次刷新检查:命中的提醒发系统通知并移除(一次性)。
    private func checkAlerts() {
        guard !alerts.isEmpty else { return }
        let fired = alerts.filter { a in
            guard let t = tickers[a.sym] else { return false }
            return a.above ? t.lastPrice >= a.price : t.lastPrice <= a.price
        }
        guard !fired.isEmpty else { return }
        for a in fired {
            let base = tickers[a.sym]?.base ?? a.sym
            let now = Fmt.price(tickers[a.sym]?.lastPrice ?? a.price)
            Notifier.fire(
                title: "\(base) \(a.above ? L("涨破", "rose above") : L("跌破", "fell below")) \(Fmt.price(a.price))",
                body: L("当前 \(now)", "Now \(now)"))
        }
        alerts.removeAll { fired.contains($0) }
        persistAlerts()
    }

    private func persist() {
        UserDefaults.standard.set(watchlist, forKey: "watchlist")
        UserDefaults.standard.set(barCoins, forKey: "barCoins")
    }

    /// 截图预览用的假数据。
    static func mock() -> TickerModel {
        let m = TickerModel(watchlist: ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"], autostart: false)
        m.watchlist = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"]   // 截图用纯假数据,忽略已持久化的自选
        m.tickers = [
            "BTCUSDT": Ticker(symbol: "BTCUSDT", lastPrice: 66430.12, changePct: 1.32, high: 67255, low: 65469, quoteVolume: 10_900_000_000),
            "ETHUSDT": Ticker(symbol: "ETHUSDT", lastPrice: 1762.40, changePct: 3.45, high: 1849, low: 1712, quoteVolume: 4_800_000_000),
            "SOLUSDT": Ticker(symbol: "SOLUSDT", lastPrice: 73.68, changePct: -2.11, high: 76, low: 70.8, quoteVolume: 2_060_000_000),
            "BNBUSDT": Ticker(symbol: "BNBUSDT", lastPrice: 612.91, changePct: -0.63, high: 620, low: 605, quoteVolume: 837_000_000),
        ]
        m.flash = ["BTCUSDT": 1, "ETHUSDT": 1, "SOLUSDT": -1, "BNBUSDT": 0]
        m.spark = [
            "BTCUSDT": [64200, 64500, 64100, 64800, 65200, 65000, 65600, 66100, 65900, 66430],
            "ETHUSDT": [1700, 1712, 1695, 1722, 1735, 1750, 1742, 1758, 1762],
            "SOLUSDT": [76.4, 75.5, 75.8, 74.9, 74.0, 73.5, 73.9, 73.2, 73.68],
            "BNBUSDT": [616, 615, 617, 614.5, 613.2, 612.5, 613.1, 612.91],
        ]
        m.futuresSyms = ["SOLUSDT"]
        m.funding = ["SOLUSDT": Funding(rate: -0.00008, mark: 73.66, index: 73.70,
                                        nextTime: Date().addingTimeInterval(2400).timeIntervalSince1970 * 1000)]
        m.barCoins = ["BTCUSDT"]
        m.alerts = [PriceAlert(sym: "SOLUSDT", price: 80, above: true),
                    PriceAlert(sym: "SOLUSDT", price: 70, above: false)]
        m.lastUpdated = Date()
        return m
    }
}
