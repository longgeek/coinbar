import SwiftUI

/// 单个币的详情页:大号价格、24h 走势、24h 高低/成交额,合约则含资金费率/标记价。
struct DetailView: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    @Environment(\.openURL) private var openURL
    let sym: String
    var dismiss: () -> Void
    var preview: Bool = false   // 截图模式:用静态框替代 TextField
    @State private var alertText = ""

    var body: some View {
        let t = model.tickers[sym]
        let isFut = Inst.isPerp(sym)
        let base = t?.base ?? Inst.base(sym)

        VStack(spacing: 0) {
            header(base: base, isFut: isFut)
            Divider().overlay(skin.hairline)

            VStack(alignment: .leading, spacing: 12) {
                if let t {
                    let chg = model.displayChange(sym)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(Fmt.price(t.lastPrice))
                            .font(Theme.mono(26, weight: .semibold))
                            .foregroundStyle(skin.change(chg))
                        ChangePill(pct: chg)
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
                    statRow(L("24h 最高", "24h High"), Fmt.price(t.high))
                    statRow(L("24h 最低", "24h Low"), Fmt.price(t.low))
                    statRow(L("24h 成交额", "24h Volume"), Fmt.compact(t.quoteVolume) + " USDT")
                }
                if isFut, let f = model.funding[sym] {
                    Rectangle().fill(skin.hairline).frame(height: 1).padding(.vertical, 5)
                    statRow(L("资金费率", "Funding"), Fmt.funding(f.rate))
                    statRow(L("下次结算", "Next funding"), Fmt.fundingTime(f.nextTime))
                    statRow(L("标记价", "Mark"), Fmt.price(f.mark))
                    statRow(L("指数价", "Index"), Fmt.price(f.index))
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider().overlay(skin.hairline)

            alertsSection
            Divider().overlay(skin.hairline)

            Button {
                let path = isFut ? "futures/\(Inst.apiSymbol(sym))" : "trade/\(base)_USDT?type=spot"
                if let url = URL(string: "https://www.binance.com/\(L("zh-CN", "en"))/\(path)") { openURL(url) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                    Text(L("在 Binance 打开", "Open in Binance"))
                }
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.plain).foregroundStyle(skin.accent)
        }
        .onAppear { if isFut { Task { await model.loadFunding(sym) } } }
    }

    /// 价格提醒:已设的提醒(可删)+ 添加目标价。到价发系统通知。
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("价格提醒", "Price Alerts"))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(model.alerts(for: sym)) { a in
                HStack(spacing: 6) {
                    Image(systemName: a.above ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(a.above ? skin.up : skin.down)
                    Text(Fmt.price(a.price)).font(Theme.mono(12, weight: .medium))
                    Spacer()
                    Button { model.removeAlert(a) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                if preview {
                    Text(L("目标价", "Target price")).font(Theme.mono(12)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).stroke(skin.hairline))
                } else {
                    TextField(L("目标价", "Target price"), text: $alertText)
                        .textFieldStyle(.roundedBorder).font(Theme.mono(12))
                        .onSubmit(addAlert)
                }
                Button(L("添加", "Add"), action: addAlert)
                    .buttonStyle(.plain).foregroundStyle(skin.accent).font(.system(size: 12, weight: .medium))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func addAlert() {
        if let p = Double(alertText.trimmingCharacters(in: .whitespaces)), p > 0 {
            model.addAlert(sym, price: p); alertText = ""
        }
    }

    private func header(base: String, isFut: Bool) -> some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }.buttonStyle(IconButtonStyle()).help(L("返回", "Back"))
            Text(base).font(Theme.rounded(16, weight: .bold))
            Text(isFut ? L("合约", "Perp") : L("现货", "Spot"))
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(skin.accent.opacity(0.18)))
                .foregroundStyle(skin.accent)
            Spacer()
            Text(Inst.apiSymbol(sym)).font(.system(size: 11)).foregroundStyle(.tertiary)
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
