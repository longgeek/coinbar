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
    @Published var watchlist: [String]   // 自选实例 id(现货=裸符号 BTCUSDT;合约=BTCUSDT.P)
    @Published var tickers: [String: Ticker] = [:]   // 按 id 存
    @Published var query: String = "" { didSet { scheduleSearchFetch() } }
    @Published var allSymbols: [String] = [] { didSet { migrateWatchlistMarkets(); if !query.isEmpty { scheduleSearchFetch() } } }   // 搜索用全量实例 id(晚到时补迁移 + 补拉价)
    @Published var searchTickers: [String: Ticker] = [:]   // 搜索结果行情(按 id 存,按需拉取)
    @Published var lastUpdated: Date?
    @Published var barCoins: [String]             // 菜单栏显示的币 id(可多个;空=显示首个自选)

    // 设置项(设置面板里可调)
    @Published var refreshSec: Int                // 刷新间隔(秒)
    @Published var redUp: Bool                    // true=红涨绿跌(A股) / false=绿涨红跌
    @Published var appearance: String             // auto | light | dark
    @Published var barStyle: String               // 菜单栏显示:price | change | both
    @Published var barMono: Bool                  // 菜单栏单色(模板渲染,失焦/外接屏 dim 更自然)
    @Published var changeBasis: String            // 涨跌幅基准:24h | today
    @Published var lang: String { didSet { Localize.lang = lang } }   // 语言:auto | zh | en
    @Published var launchAtLogin: Bool             // 开机自启动(SMAppService)
    var onCheckForUpdates: (() -> Void)?           // 由 AppDelegate 注入(Sparkle 检查更新)

    private var prevPrice: [String: Double] = [:] // 变价闪烁基线
    @Published var flash: [String: Int] = [:]     // +1/-1/0
    @Published var spark: [String: [Double]] = [:] // 迷你 K 线收盘价序列(近 24h)
    @Published var dayOpen: [String: Double] = [:]  // 今日(本地时区 0 点)开盘价,用于「今日」涨跌
    @Published var funding: [String: Funding] = [:] // 合约资金费率/标记价(详情页)
    @Published var alerts: [PriceAlert] = []         // 价格提醒(到价系统通知)
    private var timer: Timer?
    private var sparkTimer: Timer?
    private var spotStream: PriceStream?            // 现货实时推送
    private var futStream: PriceStream?             // 合约实时推送
    private var searchTask: Task<Void, Never>?   // 搜索行情拉取(防抖 + 可取消)
    private var symbolTask: Task<Void, Never>?   // 全量符号加载(分市场容错重试 + 定时刷新)
    private var lastSpotSyms: [String] = []      // 最近一次成功的现货符号(last-good 容错)
    private var lastPerpSyms: [String] = []      // 最近一次成功的合约符号(last-good 容错)

    init(watchlist: [String] = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "BNBUSDT"], autostart: Bool = true) {
        self.watchlist = UserDefaults.standard.stringArray(forKey: "watchlist") ?? watchlist
        self.barCoins = UserDefaults.standard.stringArray(forKey: "barCoins") ?? []
        if let d = UserDefaults.standard.data(forKey: "alerts"),
           let a = try? JSONDecoder().decode([PriceAlert].self, from: d) { self.alerts = a }
        self.refreshSec = UserDefaults.standard.object(forKey: "refreshSec") as? Int ?? 3
        self.redUp = UserDefaults.standard.bool(forKey: "redUp")
        self.appearance = UserDefaults.standard.string(forKey: "appearance") ?? "auto"
        self.barStyle = UserDefaults.standard.string(forKey: "barStyle") ?? "price"
        self.barMono = UserDefaults.standard.bool(forKey: "barMono")
        self.changeBasis = UserDefaults.standard.string(forKey: "changeBasis") ?? "24h"
        self.lang = UserDefaults.standard.string(forKey: "lang") ?? "auto"
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        if autostart {
            Localize.lang = self.lang   // 仅正常启动时同步;截图模式由 --lang 决定
            start()                     // 启动即抓数据(不必等用户点开面板)
        }
    }

    func start() {
        // 现货 + 合约两条 WebSocket(REST 仍跑作兜底;市场由各自的流注入)。
        spotStream = PriceStream(wsBase: BinanceAPI.spotWS) { [weak self] t in self?.ingest(t, market: .spot) }
        futStream = PriceStream(wsBase: BinanceAPI.futWS) { [weak self] t in self?.ingest(t, market: .perp) }
        updateStreams()                  // 先按现有自选订阅
        Task { await refresh() }         // 自选价格立即拉,不等 allSymbols
        Task { await refreshSparks() }
        Task { await refreshDayOpens() }
        symbolTask = Task { await loadSymbolsLoop() }   // 全量符号(搜索 + 历史自选迁移):现货/合约分别容错重试,拉全后定时刷新
        restartTimer()
        sparkTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { await self?.refreshSparks() }
            Task { await self?.refreshDayOpens() }
        }
    }

    /// 全量符号加载循环:现货 / 合约分别拉取,各自缓存「最近一次成功」结果(last-good)。
    /// - 任一边本次失败 → 沿用 last-good,绝不因此丢掉另一类币;两边都未拉全时退避重试(5s→60s)。
    /// - 两边都拉全后转入每 30 分钟刷新:自动收录新上市的币,并自愈一次性失败。
    /// 修复:旧逻辑只在「整体为空」时重试,合约接口在启动时一次性失败(spot 成功)会被当成成功,
    /// 导致纯合约币(如 LABUSDT)整局搜不到,直到重启。
    private func loadSymbolsLoop() async {
        var retry: UInt64 = 5_000_000_000               // 未拉全时的重试间隔,逐步退避到 60s
        while !Task.isCancelled {
            async let s = BinanceAPI.fetchSpotSymbols()
            async let f = BinanceAPI.fetchPerpSymbols()
            let spot = await s, perp = await f
            if !spot.isEmpty { lastSpotSyms = spot }
            if !perp.isEmpty { lastPerpSyms = perp }

            let merged = (lastSpotSyms + lastPerpSyms).sorted()
            if merged != allSymbols {
                let before = watchlist
                allSymbols = merged                     // didSet → migrateWatchlistMarkets()
                if watchlist != before {                // 迁移改了自选(含纯合约币)→ 重订阅 + 重拉
                    updateStreams()
                    await refresh()
                    await refreshSparks()
                    await refreshDayOpens()
                }
            }

            let complete = !lastSpotSyms.isEmpty && !lastPerpSyms.isEmpty
            let wait: UInt64
            if complete {
                wait = 1_800_000_000_000                // 拉全:每 30 分钟刷新,收录新上市 + 自愈
                retry = 5_000_000_000                   // 复位退避,下次掉线仍从 5s 起
            } else {
                wait = retry
                retry = min(retry * 2, 60_000_000_000)
            }
            try? await Task.sleep(nanoseconds: wait)
        }
    }

    /// 按市场把自选拆给两条流订阅(传纯符号)。
    private func updateStreams() {
        spotStream?.update(symbols: watchlist.filter { !Inst.isPerp($0) }.map { Inst.apiSymbol($0) })
        futStream?.update(symbols: watchlist.filter { Inst.isPerp($0) }.map { Inst.apiSymbol($0) })
    }

    /// 历史自选里若有纯合约币(老版按裸符号存),按 allSymbols 把它迁移成 .P id,使其继续按合约取价/标记。
    private func migrateWatchlistMarkets() {
        guard !allSymbols.isEmpty else { return }
        let spotSet = Set(allSymbols.lazy.filter { !Inst.isPerp($0) })
        let perpSet = Set(allSymbols.lazy.filter { Inst.isPerp($0) })
        func fix(_ id: String) -> String {
            guard !Inst.isPerp(id), !spotSet.contains(id), perpSet.contains(Inst.perpID(id)) else { return id }
            return Inst.perpID(id)
        }
        let newWatch = watchlist.map(fix), newBar = barCoins.map(fix)
        let newAlerts = alerts.map { a -> PriceAlert in
            let nid = fix(a.sym); return nid == a.sym ? a : PriceAlert(sym: nid, price: a.price, above: a.above)
        }
        guard newWatch != watchlist || newBar != barCoins || newAlerts != alerts else { return }
        watchlist = newWatch; barCoins = newBar; alerts = newAlerts
        persist(); persistAlerts()
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
        d.set(barMono, forKey: "barMono")
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
            let c = await BinanceAPI.fetchKlines(Inst.apiSymbol(sym), market: Inst.market(sym))
            if !c.isEmpty { spark[sym] = c }
        }
    }

    /// 「今日」涨跌所需的日线开盘价(仅在该口径下抓)。
    func refreshDayOpens() async {
        guard changeBasis == "today" else { return }
        for sym in watchlist {
            if let o = await BinanceAPI.fetchDailyOpen(Inst.apiSymbol(sym), market: Inst.market(sym)) { dayOpen[sym] = o }
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
        if let f = await BinanceAPI.fetchFunding(Inst.apiSymbol(sym)) { funding[sym] = f }
    }

    func refresh() async {
        let ids = watchlist
        guard !ids.isEmpty else { tickers = [:]; return }
        var map = tickers                                  // 保留上次,避免瞬时缺失闪烁
        let spotIDs = ids.filter { !Inst.isPerp($0) }
        let perpIDs = ids.filter { Inst.isPerp($0) }
        if !spotIDs.isEmpty {
            let spot = await BinanceAPI.fetchSpot(spotIDs.map { Inst.apiSymbol($0) })
            for t in spot { map[t.symbol] = t }            // 现货 id == 纯符号
        }
        if !perpIDs.isEmpty {
            let fut = await BinanceAPI.fetchFutures(perpIDs.map { Inst.apiSymbol($0) })
            for t in fut { map[Inst.perpID(t.symbol)] = t } // 合约回存到 .P id
        }
        for sym in ids {                                   // 变价方向(脉冲/闪烁)
            if let t = map[sym] {
                let dir = prevPrice[sym].map { t.lastPrice > $0 ? 1 : (t.lastPrice < $0 ? -1 : 0) } ?? 0
                flash[sym] = dir
                prevPrice[sym] = t.lastPrice
            }
        }
        tickers = map.filter { ids.contains($0.key) }      // 清理已移除的
        checkAlerts()
        lastUpdated = Date()
    }

    /// 单条行情入库(WebSocket 推送与 REST 共用):按所属市场算出 id,更新价格、变价方向、检查提醒。
    func ingest(_ t: Ticker, market: Market) {
        let id = Inst.id(t.symbol, market)
        guard watchlist.contains(id) else { return }
        let dir = prevPrice[id].map { t.lastPrice > $0 ? 1 : (t.lastPrice < $0 ? -1 : 0) } ?? 0
        flash[id] = dir
        prevPrice[id] = t.lastPrice
        tickers[id] = t
        checkAlerts()
        lastUpdated = Date()
    }

    // 菜单栏文案
    /// 菜单栏要显示的若干币:(基础符号, 价格文本, 方向 +1/-1)。空=显示首个自选。
    func barSegments() -> [(base: String, price: String, pct: String, dir: Int, isPerp: Bool)] {
        // 钉住的币按「自选列表顺序」展示 → 拖动列表排序会同步到菜单栏。
        let coins = barCoins.isEmpty ? Array(watchlist.prefix(1)) : watchlist.filter { barCoins.contains($0) }
        return coins.compactMap { sym in
            guard let t = tickers[sym] else { return nil }
            let chg = displayChange(sym)
            return (t.base, Fmt.price(t.lastPrice), Fmt.pct(chg), chg >= 0 ? 1 : -1, Inst.isPerp(sym))
        }
    }

    // 当前应展示的列表(空搜索=自选;有搜索=过滤全量实例 id)。排序基于纯符号,避免 .P 后缀打乱次序;
    // 双挂币按 现货→合约 排列。
    var displayed: [String] {
        if query.isEmpty { return watchlist }
        let q = query.uppercased()
        return allSymbols.filter { Inst.apiSymbol($0).contains(q) }
            .sorted { a, b in
                func rank(_ id: String) -> (Int, Int, Int, Int) {
                    let s = Inst.apiSymbol(id)
                    return (s.hasPrefix(q) ? 0 : 1, s.hasSuffix("USDT") ? 0 : 1, s.count, Inst.isPerp(id) ? 1 : 0)
                }
                return rank(a) < rank(b)
            }
            .prefix(40).map { $0 }
    }

    /// 搜索结果行情:自选币用实时(WS)行情,其余用按需拉取的快照(均按 id 存)。
    func searchTicker(_ sym: String) -> Ticker? { tickers[sym] ?? searchTickers[sym] }

    /// 搜索词变化时:防抖后按市场分批拉取当前结果的行情(现货批量 + 合约),按 id 存,供搜索行显示价格/涨跌幅。
    private func scheduleSearchFetch() {
        searchTask?.cancel()
        let q = query
        guard !q.isEmpty else { searchTickers = [:]; return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)   // 防抖:连打字时只在停顿后拉一次
            guard !Task.isCancelled, let self, self.query == q else { return }
            let ids = self.displayed                          // 已封顶 40
            guard !ids.isEmpty else { return }
            var map: [String: Ticker] = [:]
            for s in ids { if let old = self.searchTickers[s] { map[s] = old } }   // 旧价打底,避免精炼搜索词时闪烁
            let spotSyms = ids.filter { !Inst.isPerp($0) }.map { Inst.apiSymbol($0) }
            let perpSyms = ids.filter { Inst.isPerp($0) }.map { Inst.apiSymbol($0) }
            if !spotSyms.isEmpty {
                let spot = await BinanceAPI.fetchSpot(spotSyms)
                guard !Task.isCancelled, self.query == q else { return }
                for t in spot { map[t.symbol] = t }
            }
            if !perpSyms.isEmpty {
                let fut = await BinanceAPI.fetchFutures(perpSyms)
                guard !Task.isCancelled, self.query == q else { return }
                for t in fut { map[Inst.perpID(t.symbol)] = t }
            }
            self.searchTickers = map
        }
    }

    func isWatched(_ sym: String) -> Bool { watchlist.contains(sym) }

    func toggleWatch(_ sym: String) {
        if let i = watchlist.firstIndex(of: sym) {
            watchlist.remove(at: i)
            barCoins.removeAll { $0 == sym }
        } else {
            watchlist.append(sym)
            let api = Inst.apiSymbol(sym), mkt = Inst.market(sym)
            Task { await refresh() }
            Task { let c = await BinanceAPI.fetchKlines(api, market: mkt); if !c.isEmpty { spark[sym] = c } }
            Task { if let o = await BinanceAPI.fetchDailyOpen(api, market: mkt) { dayOpen[sym] = o } }
        }
        persist()
        updateStreams()   // WS 重新订阅(两条流按市场分)
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
        // SOLUSDT(现货)+ SOLUSDT.P(合约)同时在列,演示双挂币两行并存。
        m.watchlist = ["BTCUSDT", "ETHUSDT", "SOLUSDT", "SOLUSDT.P", "BNBUSDT"]   // 截图用纯假数据,忽略已持久化的自选
        m.tickers = [
            "BTCUSDT": Ticker(symbol: "BTCUSDT", lastPrice: 66430.12, changePct: 1.32, high: 67255, low: 65469, quoteVolume: 10_900_000_000),
            "ETHUSDT": Ticker(symbol: "ETHUSDT", lastPrice: 1762.40, changePct: 3.45, high: 1849, low: 1712, quoteVolume: 4_800_000_000),
            "SOLUSDT": Ticker(symbol: "SOLUSDT", lastPrice: 73.68, changePct: -2.11, high: 76, low: 70.8, quoteVolume: 2_060_000_000),
            "SOLUSDT.P": Ticker(symbol: "SOLUSDT", lastPrice: 73.66, changePct: -2.05, high: 76.1, low: 70.7, quoteVolume: 5_400_000_000),
            "BNBUSDT": Ticker(symbol: "BNBUSDT", lastPrice: 612.91, changePct: -0.63, high: 620, low: 605, quoteVolume: 837_000_000),
        ]
        m.flash = ["BTCUSDT": 1, "ETHUSDT": 1, "SOLUSDT": -1, "SOLUSDT.P": -1, "BNBUSDT": 0]
        m.spark = [
            "BTCUSDT": [64200, 64500, 64100, 64800, 65200, 65000, 65600, 66100, 65900, 66430],
            "ETHUSDT": [1700, 1712, 1695, 1722, 1735, 1750, 1742, 1758, 1762],
            "SOLUSDT": [76.4, 75.5, 75.8, 74.9, 74.0, 73.5, 73.9, 73.2, 73.68],
            "SOLUSDT.P": [76.3, 75.4, 75.7, 74.8, 73.9, 73.4, 73.8, 73.1, 73.66],
            "BNBUSDT": [616, 615, 617, 614.5, 613.2, 612.5, 613.1, 612.91],
        ]
        m.funding = ["SOLUSDT.P": Funding(rate: -0.00008, mark: 73.66, index: 73.70,
                                          nextTime: Date().addingTimeInterval(2400).timeIntervalSince1970 * 1000)]
        m.barCoins = ["BTCUSDT"]
        m.alerts = [PriceAlert(sym: "SOLUSDT.P", price: 80, above: true),
                    PriceAlert(sym: "SOLUSDT.P", price: 70, above: false)]
        m.lastUpdated = Date()
        return m
    }
}
