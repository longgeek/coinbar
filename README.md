# CoinBar

一个简洁、原生的 macOS 菜单栏加密货币行情应用,用 SwiftUI 编写。

实时价格、变价闪烁、搜索添加自选、现货 + 合约(含资金费率)。数据来自 Binance 公共行情接口,免密钥、无地区封锁。

## 功能

- **菜单栏实时行情** — 把一个或多个币钉在菜单栏,价格实时更新,按 24h 涨跌着绿/红色,等宽数字不抖动,带 ▲▼ 方向箭头。
- **精致弹出面板** — 真正的搜索框(输入即过滤全量交易对)、星标自选列表,告别系统弹窗。
- **迷你 K 线** — 每行一条近 24h 收盘价走势,按净涨跌着色。
- **变价闪烁** — 价格变动时整行脉冲 + 数字着绿/红色。
- **单币详情** — 大号价格、24h 走势、最高/最低/成交额;合约还显示资金费率、下次结算、标记价、指数价,并可一键跳转 Binance。
- **现货 + 合约** — 现货走 `data-api.binance.vision`(无地区封锁、免密钥),USDⓈ-M 合约走 `fapi.binance.com`。
- **设置** — 刷新间隔(1/2/3/5/10s)、涨跌配色(绿涨红跌 / 红涨绿跌)、外观(跟随系统 / 浅色 / 深色)、开机自启动。

## 截图

<p align="center">
  <img src="screenshots/popover-light.png" width="340" alt="GitHub Light">
  <img src="screenshots/popover-dark.png" width="340" alt="GitHub Dark Dimmed">
</p>

> 界面图由应用自渲染生成(无需点开菜单栏):
> `./build/CoinBar.app/Contents/MacOS/CoinBar --render-popover out.png --skin light|binance`
> (另有 `--render-detail`、`--render-settings`、`--render-icon`。)

## 从源码构建

需要 macOS 13+ 与 Swift 工具链(Xcode 或命令行工具)。

```sh
git clone https://github.com/longgeek/coinbar.git
cd coinbar
./build.sh           # 产物 -> build/CoinBar.app
open build/CoinBar.app
```

开机自启动:打开 CoinBar 设置面板里的「开机自启动」开关即可(也可在 系统设置 → 通用 → 登录项 手动添加)。

## 安装发布版

从 [Releases](https://github.com/longgeek/coinbar/releases) 下载 `CoinBar.app`。由于尚未公证,首次启动可能被 macOS Gatekeeper 拦截——右键点应用 → **打开** → **打开**,或执行:

```sh
xattr -dr com.apple.quarantine /Applications/CoinBar.app
```

## 状态

v0.1 — 早期版本。已实现:菜单栏多币、搜索自选、迷你 K 线、单币详情、现货 + 合约(含资金费率)、设置面板(刷新间隔/涨跌配色/外观)、应用图标。

后续计划:正式签名 + 公证的发布版(当前仅 ad-hoc 签名)、设计打磨。

## 许可

MIT © 2026 longgeek
