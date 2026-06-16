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
    static let spotBase = "https://data-api.binance.vision"

    /// 批量拉取若干交易对的 24h 行情。
    static func fetchSpot(_ symbols: [String]) async throws -> [Ticker] {
        guard !symbols.isEmpty else { return [] }
        let arr = "[" + symbols.map { "\"\($0)\"" }.joined(separator: ",") + "]"
        let q = arr.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? arr
        let url = URL(string: "\(spotBase)/api/v3/ticker/24hr?symbols=\(q)")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let raw = try JSONSerialization.jsonObject(with: data)
        let items = (raw as? [[String: Any]]) ?? ((raw as? [String: Any]).map { [$0] } ?? [])
        return items.compactMap { parse($0) }
    }

    /// 全部现货交易对符号(用于搜索过滤),拉一次缓存即可。
    static func fetchAllSymbols() async throws -> [String] {
        let url = URL(string: "\(spotBase)/api/v3/ticker/price")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
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
