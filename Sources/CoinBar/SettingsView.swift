import SwiftUI

/// 设置面板:刷新间隔 / 涨跌颜色 / 外观 / 开机自启动。改动即时保存生效。
/// preview=true 时用静态控件替代 Picker/Toggle,供 ImageRenderer 截图(它渲染不出原生分段控件)。
struct SettingsView: View {
    @EnvironmentObject var model: TickerModel
    @Environment(\.skin) private var skin
    @Binding var show: Bool
    var preview: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(skin.hairline)
            VStack(alignment: .leading, spacing: 18) {
                row("刷新间隔") { refreshControl }
                row("涨跌颜色") { colorControl }
                row("外观") { appearanceControl }
                HStack {
                    Text("开机自启动").font(Theme.rounded(13, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    launchControl
                }
                HStack {
                    Text("软件更新").font(Theme.rounded(13, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button("检查更新") { model.onCheckForUpdates?() }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(skin.accent)
                }
            }
            .padding(14)
            .tint(skin.accent)   // 分段控件/开关选中色与外部按钮统一
            Divider().overlay(skin.hairline)
            footer
        }
        .onChange(of: model.refreshSec) { _ in model.restartTimer(); model.saveSettings() }
        .onChange(of: model.redUp) { _ in model.saveSettings() }
        .onChange(of: model.appearance) { _ in model.saveSettings() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { show = false } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }.buttonStyle(.plain)
            Text("设置").font(Theme.rounded(15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var footer: some View {
        HStack {
            Text("CoinBar v0.1 by Longgeek").font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Text("数据来自 Binance").font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    @ViewBuilder private var refreshControl: some View {
        if preview {
            segment(["1s", "2s", "3s", "5s", "10s"], selected: [1, 2, 3, 5, 10].firstIndex(of: model.refreshSec) ?? 2)
        } else {
            Picker("", selection: $model.refreshSec) {
                Text("1s").tag(1); Text("2s").tag(2); Text("3s").tag(3)
                Text("5s").tag(5); Text("10s").tag(10)
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
    @ViewBuilder private var colorControl: some View {
        if preview {
            segment(["绿涨红跌", "红涨绿跌"], selected: model.redUp ? 1 : 0)
        } else {
            Picker("", selection: $model.redUp) {
                Text("绿涨红跌").tag(false); Text("红涨绿跌").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
    @ViewBuilder private var appearanceControl: some View {
        if preview {
            segment(["跟随系统", "浅色", "深色"], selected: ["auto", "light", "dark"].firstIndex(of: model.appearance) ?? 0)
        } else {
            Picker("", selection: $model.appearance) {
                Text("跟随系统").tag("auto"); Text("浅色").tag("light"); Text("深色").tag("dark")
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
    @ViewBuilder private var launchControl: some View {
        if preview {
            Capsule().fill(skin.accent).frame(width: 36, height: 22)
                .overlay(Circle().fill(.white).padding(2.5), alignment: .trailing)
        } else {
            Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                .labelsHidden().toggleStyle(.switch)
        }
    }

    /// 截图用的静态分段控件外观(ImageRenderer 渲染不出原生 segmented Picker)。
    private func segment(_ options: [String], selected: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                Text(opt)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity).padding(.vertical, 5)
                    .foregroundStyle(i == selected ? Color.white : Color.primary)
                    .background(i == selected ? skin.accent : Color.clear)
            }
        }
        .background(Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Theme.rounded(13, weight: .medium)).foregroundStyle(.secondary)
            control()
        }
    }
}
