import Foundation

/// Binance 行情 WebSocket(combined `<sym>@ticker` 流)。现货走 data-stream.binance.vision、合约走 fstream.binance.com,
/// 两者 payload 字段集一致,故同一实现按 wsBase 复用。市场由「哪条流」决定(payload 的 s 字段两边都是裸符号),
/// 故 onTicker 回调由各自的流注入对应市场。实时推送价格;断线指数退避重连;失败只是降级,由 REST 轮询兜底。
@MainActor
final class PriceStream {
    private let wsBase: String
    private let onTicker: @MainActor (Ticker) -> Void
    private var task: URLSessionWebSocketTask?
    private var symbols: [String] = []
    private var active = false
    private var backoff: TimeInterval = 1

    // 半开检测(watchdog):连接「活着」却长时间不推数据(睡眠/唤醒、NAT 超时、服务端静默关闭不报错)
    // 时,receive 会永远空等、退避永不触发。记录最近收到消息的时刻,定时探活,陈旧则 ping 探针 / 硬超时强连。
    private var lastMessageAt = Date()
    private var watchdog: Timer?

    // 只解析需要的 6 个字段(裸符号 s、最新价 c、24h 涨跌幅 P、高 h、低 l、成交额 q)。
    // 用 Codable 避开 JSONSerialization 的 NSDictionary 桥接;非 @ticker 帧(如控制应答)解码失败即忽略。
    private struct Frame: Decodable {
        struct D: Decodable { let s, c, P, h, l, q: String }
        let data: D
    }
    private let decoder = JSONDecoder()

    init(wsBase: String, onTicker: @escaping @MainActor (Ticker) -> Void) {
        self.wsBase = wsBase
        self.onTicker = onTicker
    }

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
        watchdog?.invalidate()
        watchdog = nil
    }

    private func connect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        guard !symbols.isEmpty else {
            active = false
            watchdog?.invalidate(); watchdog = nil
            return
        }
        let streams = symbols.map { "\($0.lowercased())@ticker" }.joined(separator: "/")
        guard let url = URL(string: "\(wsBase)/stream?streams=\(streams)") else { return }
        active = true
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        receive(t)
        lastMessageAt = Date()
        startWatchdog()
    }

    /// 探活定时器:陈旧(>30s 无数据)先 ping 探针,失败或硬超时(>60s)直接重连。重连/停止时复位。
    private func startWatchdog() {
        watchdog?.invalidate()
        let w = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAlive() }
        }
        w.tolerance = 5
        watchdog = w
    }

    private func checkAlive() {
        guard active, let t = task else { return }
        let idle = Date().timeIntervalSince(lastMessageAt)
        if idle > 60 { connect(); return }   // 硬超时:即便 ping 不报错也强制重连
        guard idle > 30 else { return }
        t.sendPing { [weak self] err in
            guard err != nil else { return }
            Task { @MainActor in
                guard let self, self.active, self.task === t else { return }   // 旧连接的迟到失败不应杀掉新连接
                self.connect()
            }
        }
    }

    private func receive(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.active, self.task === t else { return }   // 忽略旧连接的回调
                switch result {
                case .success(let msg):
                    self.backoff = 1
                    self.lastMessageAt = Date()
                    switch msg {
                    case .string(let s): self.handle(Data(s.utf8))
                    case .data(let d): self.handle(d)   // 直接喂 Data,省去 Data→String→Data 往返
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

    private func handle(_ data: Data) {
        guard let frame = try? decoder.decode(Frame.self, from: data) else { return }
        let d = frame.data
        func num(_ s: String) -> Double { Double(s) ?? 0 }
        // @ticker: c=最新价, P=24h 涨跌幅%, h=高, l=低, q=成交额
        onTicker(Ticker(symbol: d.s, lastPrice: num(d.c), changePct: num(d.P),
                        high: num(d.h), low: num(d.l), quoteVolume: num(d.q)))
    }
}
