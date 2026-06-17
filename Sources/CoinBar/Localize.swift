import Foundation

/// 轻量本地化:全局当前语言 + `L(中文, English)`。
/// 不走 SwiftPM 资源/字符串目录(那套在手工打包的 .app + AppKit 单元格 + 截图模式里都很麻烦),
/// 改设置即时切换;由 TickerModel.lang 同步 Localize.lang。
enum Localize {
    /// "auto" | "zh" | "en"
    static var lang: String = "auto"
    static var isEnglish: Bool {
        switch lang {
        case "en": return true
        case "zh": return false
        default: return !(Locale.preferredLanguages.first?.hasPrefix("zh") ?? false)   // 跟随系统
        }
    }
}

/// 按当前语言返回中文或英文。
func L(_ zh: String, _ en: String) -> String { Localize.isEnglish ? en : zh }
