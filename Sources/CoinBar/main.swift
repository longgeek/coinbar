import SwiftUI

// 入口:支持 --render-popover <path> 截图模式(便于设计迭代),否则正常启动菜单栏应用。
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render-popover"), i + 1 < args.count {
    MainActor.assumeIsolated {
        Screenshot.renderPopover(to: args[i + 1])
    }
} else {
    CoinBarApp.main()
}
