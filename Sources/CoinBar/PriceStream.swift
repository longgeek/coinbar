import Foundation

/// Binance 现货行情 WebSocket(combined `<sym>@ticker` 流,data-stream.binance.vision 无地区封锁、免密钥)。
/// 实时推送价格;断线指数退避重连。WS 不可用时由 TickerModel 的 REST 轮询兜底,故失败只是降级、不报错。
@MainActor
final class PriceStream {
    private let onTicker: @MainActor (Ticker) -> Void
    private var task: URLSessionWebSocketTask?
    private var symbols: [String] = []
    private var active = false
    private var backoff: TimeInterval = 1

    init(onTicker: @escaping @MainActor (Ticker) -> Void) { self.onTicker = onTicker }

    /// 订阅这批交易对(集合变化时重连)。
    func update(symbols: [String]) {
        guard symbols != self.symbols else { return }
        self.symbols = symbols
        connect()
    }

    func stop() {
        active = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func connect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        guard !symbols.isEmpty else { active = false; return }
        let streams = symbols.map { "\($0.lowercased())@ticker" }.joined(separator: "/")
        guard let url = URL(string: "wss://data-stream.binance.vision/stream?streams=\(streams)") else { return }
        active = true
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t)
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.active, self.task === t else { return }   // 忽略旧连接的回调
                switch result {
                case .success(let msg):
                    self.backoff = 1
                    switch msg {
                    case .string(let s): self.handle(s)
                    case .data(let d): if let s = String(data: d, encoding: .utf8) { self.handle(s) }
                    @unknown default: break
                    }
                    self.receive(t)
                case .failure:
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard active else { return }
        let delay = backoff
        backoff = min(backoff * 2, 30)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if self?.active == true { self?.connect() }
        }
    }

    private func handle(_ s: String) {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = obj["data"] as? [String: Any],
              let sym = d["s"] as? String else { return }
        func num(_ k: String) -> Double { Double((d[k] as? String) ?? "") ?? 0 }
        // @ticker: c=最新价, P=24h 涨跌幅%, h=高, l=低, q=成交额
        onTicker(Ticker(symbol: sym, lastPrice: num("c"), changePct: num("P"),
                        high: num("h"), low: num("l"), quoteVolume: num("q")))
    }
}
