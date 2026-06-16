# CoinBar

A clean, native macOS menu bar app for live crypto prices — built with SwiftUI.

> 一个好看的 macOS 菜单栏加密货币行情应用。实时价格、变价闪烁、搜索添加自选、现货 + 合约(开发中)。数据来自 Binance 公共行情接口,免密钥。

## Features

- **Live ticker in the menu bar** — your pinned coin's price, updated in real time.
- **Polished popover** — a real search box (type to filter), checkbox-style watchlist, no clunky system dialogs.
- **Spot prices now; futures (funding rate, mark price) coming.**
- **Flash on change** — prices tint green/red as they move.
- Data via `data-api.binance.vision` (Binance official market-data host, no API key, no geo-block).

## Screenshot

<!-- TODO: add screenshots/popover.png -->

## Build from source

Requires macOS 13+ and the Swift toolchain (Xcode or Command Line Tools).

```sh
git clone https://github.com/longgeek/coinbar.git
cd coinbar
./build.sh           # -> build/CoinBar.app
open build/CoinBar.app
```

To launch at login: System Settings → General → Login Items → add `CoinBar.app`.

## Install a release

Download `CoinBar.app` from [Releases](https://github.com/longgeek/coinbar/releases). Because the app is not yet notarized, on first launch macOS Gatekeeper may block it — right-click the app → **Open** → **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/CoinBar.app
```

## Status

v0.1 — early. Roadmap: futures + funding rate, refresh-interval control, design polish, app icon, notarized releases.

## License

MIT © 2026 longgeek
