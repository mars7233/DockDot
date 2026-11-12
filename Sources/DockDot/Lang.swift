import Foundation

/// 界面语言：跟随系统 / 简体中文 / English。存在 UserDefaults 的 "language" 键。
/// 这个文件不能用 macOS 26 才有的 API：环境检测的提示框在旧系统上也要用它。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en
    var id: String { rawValue }
    /// 选项名用各自语言显示，方便看不懂当前语言的人切回去
    var title: String {
        switch self {
        case .system: L("跟随系统", "Follow System")
        case .zh: "简体中文"
        case .en: "English"
        }
    }
}

enum Lang {
    static var setting: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system
    }

    static var isChinese: Bool {
        switch setting {
        case .zh: return true
        case .en: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }
}

/// 按当前语言返回中文或英文
func L(_ zh: String, _ en: String) -> String {
    Lang.isChinese ? zh : en
}
