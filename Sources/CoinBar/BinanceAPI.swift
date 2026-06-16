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
    var base: String {           // 去掉计价币后的基础符号,e.g. BTC
        for q in ["USDT", "FDUSD", "USDC", "TUSD", "BUSD", "USD"] where symbol.hasSuffix(q) && symbol.count > q.count {
            return String(symbol.dropLast(q.count))
        }
        return symbol
    }
}

/// 现货行情:走 data-api.binance.vision(无地区封锁、免密钥),与 binance.com 同价。
enum BinanceAPI {
    static let spotBase = "https://data-api.binance.vision"   // 现货:无地区封锁
    static let fapiBase = "https://fapi.binance.com"          // USDⓈ-M 合约

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

    /// 近 24h 收盘价序列(48 根 30m K 线),用于迷你 K 线图。现货失败则回退合约。
    static func fetchKlines(_ symbol: String) async -> [Double] {
        let spot = await klines("\(spotBase)/api/v3/klines", symbol)
        return spot.isEmpty ? await klines("\(fapiBase)/fapi/v1/klines", symbol) : spot
    }

    private static func klines(_ base: String, _ symbol: String) async -> [Double] {
        guard let url = URL(string: "\(base)?symbol=\(symbol)&interval=30m&limit=48"),
              let raw = (try? await getJSON(url)) as? [[Any]] else { return [] }
        return raw.compactMap { Double(($0.count > 4 ? $0[4] : nil) as? String ?? "") }   // index 4 = close
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

    /// 全量符号(现货 ∪ 合约),用于搜索过滤。
    static func fetchAllSymbols() async -> [String] {
        async let s = symbols("\(spotBase)/api/v3/ticker/price")
        async let f = symbols("\(fapiBase)/fapi/v1/ticker/price")
        return Array(Set(await s + (await f))).sorted()
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
}
