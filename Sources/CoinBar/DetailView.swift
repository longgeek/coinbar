import SwiftUI

/// 单个币的详情页:大号价格、24h 走势、24h 高低/成交额,合约则含资金费率/标记价。
struct DetailView: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    @Environment(\.openURL) private var openURL
    let sym: String
    var dismiss: () -> Void

    var body: some View {
        let t = model.tickers[sym]
        let isFut = model.futuresSyms.contains(sym)
        let base = t?.base ?? sym

        VStack(spacing: 0) {
            header(base: base, isFut: isFut)
            Divider().overlay(skin.hairline)

            VStack(alignment: .leading, spacing: 12) {
                if let t {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.price(t.lastPrice))
                            .font(Theme.mono(26, weight: .semibold))
                            .foregroundStyle(skin.change(t.changePct))
                        ChangePill(pct: t.changePct)
                        Spacer()
                    }
                }
                if let s = model.spark[sym], s.count >= 2 {
                    Sparkline(data: s, color: (s.last! >= s.first!) ? skin.up : skin.down)
                        .frame(height: 60)
                }
            }
            .padding(14)
            Divider().overlay(skin.hairline)

            VStack(spacing: 0) {
                if let t {
                    statRow("24h 最高", Fmt.price(t.high))
                    statRow("24h 最低", Fmt.price(t.low))
                    statRow("24h 成交额", Fmt.compact(t.quoteVolume) + " USDT")
                }
                if isFut, let f = model.funding[sym] {
                    Rectangle().fill(skin.hairline).frame(height: 1).padding(.vertical, 5)
                    statRow("资金费率", Fmt.funding(f.rate))
                    statRow("下次结算", Fmt.fundingTime(f.nextTime))
                    statRow("标记价", Fmt.price(f.mark))
                    statRow("指数价", Fmt.price(f.index))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().overlay(skin.hairline)

            Button {
                let path = isFut ? "futures/\(sym)" : "trade/\(base)_USDT?type=spot"
                if let url = URL(string: "https://www.binance.com/zh-CN/\(path)") { openURL(url) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text("在 Binance 打开")
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.plain).foregroundStyle(skin.accent)
        }
        .onAppear { if isFut { Task { await model.loadFunding(sym) } } }
    }

    private func header(base: String, isFut: Bool) -> some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }.buttonStyle(.plain)
            Text(base).font(Theme.rounded(16, weight: .bold))
            Text(isFut ? "合约" : "现货")
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(skin.accent.opacity(0.18)))
                .foregroundStyle(skin.accent)
            Spacer()
            Text(sym).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(Theme.mono(12, weight: .medium))
        }
        .padding(.vertical, 5)
    }
}
