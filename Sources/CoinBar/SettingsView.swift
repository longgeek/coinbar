import SwiftUI

/// 设置面板:刷新间隔 / 涨跌颜色 / 涨跌幅基准 / 外观 / 菜单栏显示 / 语言 / 开机自启动 / 更新。改动即时保存生效。
/// preview=true 时用静态控件替代 Picker/Toggle,供 ImageRenderer 截图。
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
                row(L("刷新间隔", "Refresh")) { refreshControl }
                row(L("涨跌颜色", "Colors")) { colorControl }
                row(L("涨跌幅基准", "Change basis")) { changeBasisControl }
                row(L("外观", "Appearance")) { appearanceControl }
                row(L("菜单栏显示", "Menu bar")) { barStyleControl }
                row(L("语言", "Language")) { langControl }
                settingRow(L("开机自启动", "Launch at login")) { launchControl }
                settingRow(L("软件更新", "Updates")) {
                    Button(L("检查更新", "Check Updates")) { model.onCheckForUpdates?() }
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
        .onChange(of: model.barStyle) { _ in model.saveSettings() }
        .onChange(of: model.changeBasis) { _ in model.saveSettings(); Task { await model.refreshDayOpens() } }
        .onChange(of: model.lang) { _ in model.saveSettings() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { show = false } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }.buttonStyle(IconButtonStyle()).help(L("返回", "Back"))
            Text(L("设置", "Settings")).font(Theme.rounded(15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var footer: some View {
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        return HStack {
            Text("CoinBar v\(ver) by Longgeek").font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Text(L("数据来自 Binance", "Data from Binance")).font(.system(size: 11)).foregroundStyle(.tertiary)
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
            segment([L("绿涨红跌", "Green up"), L("红涨绿跌", "Red up")], selected: model.redUp ? 1 : 0)
        } else {
            Picker("", selection: $model.redUp) {
                Text(L("绿涨红跌", "Green up")).tag(false); Text(L("红涨绿跌", "Red up")).tag(true)
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
    @ViewBuilder private var changeBasisControl: some View {
        if preview {
            segment(["24h", L("今日", "Today")], selected: model.changeBasis == "today" ? 1 : 0)
        } else {
            Picker("", selection: $model.changeBasis) {
                Text("24h").tag("24h"); Text(L("今日", "Today")).tag("today")
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
    @ViewBuilder private var barStyleControl: some View {
        if preview {
            segment([L("价格", "Price"), L("涨跌幅", "Change"), L("两者", "Both")],
                    selected: ["price", "change", "both"].firstIndex(of: model.barStyle) ?? 0)
        } else {
            Picker("", selection: $model.barStyle) {
                Text(L("价格", "Price")).tag("price"); Text(L("涨跌幅", "Change")).tag("change"); Text(L("两者", "Both")).tag("both")
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
    @ViewBuilder private var appearanceControl: some View {
        if preview {
            segment([L("跟随系统", "System"), L("浅色", "Light"), L("深色", "Dark")],
                    selected: ["auto", "light", "dark"].firstIndex(of: model.appearance) ?? 0)
        } else {
            Picker("", selection: $model.appearance) {
                Text(L("跟随系统", "System")).tag("auto"); Text(L("浅色", "Light")).tag("light"); Text(L("深色", "Dark")).tag("dark")
            }.pickerStyle(.segmented).labelsHidden()
        }
    }
    @ViewBuilder private var langControl: some View {
        if preview {
            segment([L("系统", "Auto"), "中文", "English"], selected: ["auto", "zh", "en"].firstIndex(of: model.lang) ?? 0)
        } else {
            Picker("", selection: $model.lang) {
                Text(L("系统", "Auto")).tag("auto"); Text("中文").tag("zh"); Text("English").tag("en")
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

    /// 标题在上、控件在下(分段控件用)。
    private func row<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(Theme.rounded(13, weight: .medium)).foregroundStyle(.secondary)
            control()
        }
    }

    /// 标题在左、控件在右(开关、按钮用)。
    private func settingRow<C: View>(_ title: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack {
            Text(title).font(Theme.rounded(13, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            control()
        }
    }
}
