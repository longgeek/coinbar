import Foundation

/// 一个币的行情快照。
struct Ticker: Identifiable, Codable, Equatable {
    let symbol: String          // e.g. BTCUSDT
    var lastPrice: Double
    var changePct: Double       // 24h 涨跌幅 %
    var high: Double
    var low: Double
    var quoteVolume: Double      // 24h 成交额(USDT)

    var id: String { symbol }
    var base: String { Inst.base(symbol) }   // 去掉计价币后的基础符号,e.g. BTC(经 Inst 统一,容忍 .P 后缀)
}

/// 交易市场:现货 / U 本位永续合约。
enum Market { case spot, perp }

/// 「币种实例」标识:现货沿用裸符号(BTCUSDT),合约加 ".P" 后缀(BTCUSDT.P)。
/// 现货 id 与历史持久化完全兼容(老数据即现货),只有合约需要后缀区分。
/// 注意:dict 主键/自选/菜单栏/提醒一律存 id;调用币安 API 一律用 apiSymbol(纯符号)。
enum Inst {
    static let perpSuffix = ".P"
    static func isPerp(_ id: String) -> Bool { id.hasSuffix(perpSuffix) }
    static func market(_ id: String) -> Market { isPerp(id) ? .perp : .spot }
    /// 去掉市场后缀 → 币安 API 用的纯符号。
    static func apiSymbol(_ id: String) -> String { isPerp(id) ? String(id.dropLast(perpSuffix.count)) : id }
    /// 合约 id = 纯符号 + 后缀。
    static func perpID(_ symbol: String) -> String { symbol + perpSuffix }
    /// 按市场给纯符号生成 id(现货保持裸符号)。
    static func id(_ symbol: String, _ market: Market) -> String { market == .perp ? perpID(symbol) : symbol }
    /// 基础符号(去市场后缀 + 去计价币),e.g. BTCUSDT.P / BTCUSDT → BTC。
    static func base(_ id: String) -> String {
        let s = apiSymbol(id)
        for q in ["USDT", "FDUSD", "USDC", "TUSD", "BUSD", "USD"] where s.hasSuffix(q) && s.count > q.count {
            return String(s.dropLast(q.count))
        }
        return s
    }
}

/// 现货行情:走 data-api.binance.vision(无地区封锁、免密钥),与 binance.com 同价。
/// 合约资金费率 / 标记价信息。
struct Funding: Equatable {
    let rate: Double      // 当前资金费率(每结算周期,小数)
    let mark: Double
    let index: Double
    let nextTime: Double  // 下次结算(epoch 毫秒)
}

enum BinanceAPI {
    static let spotBase = "https://data-api.binance.vision"   // 现货:无地区封锁
    static let fapiBase = "https://fapi.binance.com"          // USDⓈ-M 合约
    static let spotWS = "wss://data-stream.binance.vision"    // 现货 WebSocket(无地区封锁)
    static let futWS = "wss://fstream.binance.com"            // 合约 WebSocket(部分地区可能不通,由 REST 兜底)

    private static func getJSON(_ url: URL) async throws -> Any {
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    /// 现货:批量优先;若含无效交易对(整批 400)则并发逐个抓,跳过非现货的。
    static func fetchSpot(_ symbols: [String]) async -> [Ticker] {
        guard !symbols.isEmpty else { return [] }
        let arr = "[" + symbols.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let q = arr.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? arr
        if let url = URL(string: "\(spotBase)/api/v3/ticker/24hr?symbols=\(q)"),
           let raw = try? await getJSON(url) {
            let items = (raw as? [[String: Any]]) ?? ((raw as? [String: Any]).map { [$0] } ?? [])
            return items.compactMap(parse)
        }
        return await concurrent(symbols.map { "\(spotBase)/api/v3/ticker/24hr?symbol=\($0)" })
    }

    /// 合约(USDⓈ-M):并发逐个抓 24h 行情(合约接口不支持 symbols 批量过滤)。
    static func fetchFutures(_ symbols: [String]) async -> [Ticker] {
        guard !symbols.isEmpty else { return [] }
        return await concurrent(symbols.map { "\(fapiBase)/fapi/v1/ticker/24hr?symbol=\($0)" })
    }

    /// 近 24h 收盘价序列(48 根 30m K 线),用于迷你 K 线图。按市场取对应接口。
    static func fetchKlines(_ symbol: String, market: Market = .spot) async -> [Double] {
        await klines(market == .perp ? "\(fapiBase)/fapi/v1/klines" : "\(spotBase)/api/v3/klines", symbol)
    }

    private static func klines(_ base: String, _ symbol: String) async -> [Double] {
        guard let url = URL(string: "\(base)?symbol=\(symbol)&interval=30m&limit=48"),
              let raw = (try? await getJSON(url)) as? [[Any]] else { return [] }
        return raw.compactMap { Double(($0.count > 4 ? $0[4] : nil) as? String ?? "") }   // index 4 = close
    }

    /// 今日开盘价(UTC 00:00):取 1 根日线的开盘价(index 1)。按市场取对应接口(现货/合约日开不同)。
    static func fetchDailyOpen(_ symbol: String, market: Market = .spot) async -> Double? {
        let base = market == .perp ? "\(fapiBase)/fapi/v1/klines" : "\(spotBase)/api/v3/klines"
        guard let url = URL(string: "\(base)?symbol=\(symbol)&interval=1d&limit=1"),
              let raw = (try? await getJSON(url)) as? [[Any]],
              let first = raw.first, first.count > 1 else { return nil }
        return Double((first[1] as? String) ?? "")
    }

    /// 合约资金费率/标记价(premiumIndex)。
    static func fetchFunding(_ symbol: String) async -> Funding? {
        guard let url = URL(string: "\(fapiBase)/fapi/v1/premiumIndex?symbol=\(symbol)"),
              let d = (try? await getJSON(url)) as? [String: Any] else { return nil }
        func s(_ k: String) -> Double { Double((d[k] as? String) ?? "") ?? 0 }
        let next = (d["nextFundingTime"] as? Double) ?? ((d["nextFundingTime"] as? NSNumber)?.doubleValue ?? 0)
        return Funding(rate: s("lastFundingRate"), mark: s("markPrice"), index: s("indexPrice"), nextTime: next)
    }

    /// 并发抓多个单交易对 URL,跳过失败/无效(如 400)。
    private static func concurrent(_ urls: [String]) async -> [Ticker] {
        await withTaskGroup(of: Ticker?.self) { group in
            for u in urls {
                group.addTask {
                    guard let url = URL(string: u),
                          let raw = try? await getJSON(url),
                          let d = raw as? [String: Any] else { return nil }
                    return parse(d)
                }
            }
            var out: [Ticker] = []
            for await t in group where t != nil { out.append(t!) }
            return out
        }
    }

    /// 现货全量交易对(裸符号 id),用于搜索。失败返回空,由调用方按 last-good 容错 + 重试。
    static func fetchSpotSymbols() async -> [String] {
        await symbols("\(spotBase)/api/v3/ticker/price")
    }

    /// 合约(USDⓈ-M)全量交易对,已加 .P 后缀成实例 id,用于搜索。失败返回空,由调用方容错。
    /// 现货走 .vision(无封锁)、合约走 fapi:两边相互独立,任一边失败都不应丢掉另一类币。
    /// 不跨市场去重 → 双挂币(BTCUSDT)会同时给出现货 + 合约两个条目。
    static func fetchPerpSymbols() async -> [String] {
        (await symbols("\(fapiBase)/fapi/v1/ticker/price")).map { Inst.perpID($0) }
    }

    private static func symbols(_ u: String) async -> [String] {
        guard let url = URL(string: u),
              let raw = (try? await getJSON(url)) as? [[String: Any]] else { return [] }
        return raw.compactMap { $0["symbol"] as? String }
    }

    private static func parse(_ d: [String: Any]) -> Ticker? {
        guard let sym = d["symbol"] as? String else { return nil }
        func num(_ k: String) -> Double { Double((d[k] as? String) ?? "") ?? 0 }
        return Ticker(symbol: sym,
                      lastPrice: num("lastPrice"),
                      changePct: num("priceChangePercent"),
                      high: num("highPrice"),
                      low: num("lowPrice"),
                      quoteVolume: num("quoteVolume"))
    }
}

/// 数字格式化工具。
enum Fmt {
    static func price(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let a = abs(v)
        f.minimumFractionDigits = a >= 1 ? 2 : (a >= 0.01 ? 4 : 6)
        f.maximumFractionDigits = f.minimumFractionDigits
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }
    static func pct(_ v: Double) -> String {
        String(format: "%+.2f%%", v)
    }
    static func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1e9 { return String(format: "%.2fB", v / 1e9) }
        if a >= 1e6 { return String(format: "%.2fM", v / 1e6) }
        if a >= 1e3 { return String(format: "%.2fK", v / 1e3) }
        return String(format: "%.0f", v)
    }
    static func funding(_ r: Double) -> String { String(format: "%+.4f%%", r * 100) }
    static func fundingTime(_ ms: Double) -> String {
        guard ms > 0 else { return "—" }
        let date = Date(timeIntervalSince1970: ms / 1000)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let mins = max(0, Int(date.timeIntervalSinceNow / 60))
        let h = mins / 60, m = mins % 60
        let left = h > 0 ? L("(剩 \(h)h\(m)m)", "(\(h)h\(m)m left)") : L("(剩 \(m)m)", "(\(m)m left)")
        return mins == 0 ? f.string(from: date) : "\(f.string(from: date)) \(left)"
    }
}
