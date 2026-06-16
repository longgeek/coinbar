import SwiftUI

/// 设置面板:刷新间隔 / 涨跌颜色 / 外观。改动即时保存生效。
struct SettingsView: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    @Binding var show: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 顶部:返回 + 标题
            HStack(spacing: 8) {
                Button { show = false } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                }.buttonStyle(.plain)
                Text("设置").font(Theme.rounded(15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            Divider().overlay(skin.hairline)

            VStack(alignment: .leading, spacing: 18) {
                row("刷新间隔") {
                    Picker("", selection: $model.refreshSec) {
                        Text("1s").tag(1); Text("2s").tag(2); Text("3s").tag(3)
                        Text("5s").tag(5); Text("10s").tag(10)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                row("涨跌颜色") {
                    Picker("", selection: $model.redUp) {
                        Text("绿涨红跌").tag(false)
                        Text("红涨绿跌").tag(true)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                row("外观") {
                    Picker("", selection: $model.appearance) {
                        Text("跟随系统").tag("auto")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }.pickerStyle(.segmented).labelsHidden()
                }
                HStack {
                    Text("开机自启动").font(Theme.rounded(13, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.launchAtLogin },
                                             set: { model.setLaunchAtLogin($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
            }
            .padding(14)
            .tint(skin.accent)   // 分段控件/开关选中色与外部按钮统一(用皮肤 accent)

            Divider().overlay(skin.hairline)
            HStack {
                Text("CoinBar v0.1 by Longgeek").font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
                Text("数据来自 Binance").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .onChange(of: model.refreshSec) { _ in model.restartTimer(); model.saveSettings() }
        .onChange(of: model.redUp) { _ in model.saveSettings() }
        .onChange(of: model.appearance) { _ in model.saveSettings() }
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Theme.rounded(13, weight: .medium)).foregroundStyle(.secondary)
            control()
        }
    }
}
