import Foundation
import SwiftData

/// 币种服务 — 单当前币种模式 + 内置固定汇率表（可用户覆盖）
///
/// 设计原则（简洁有效）：
/// - App 全局一个 currentCurrency，所有 Expense.amount 都是此币种
/// - 切换币种时遍历所有 Expense，按汇率转换 amount
/// - 汇率表内置 9 唯一币种对 USD（13 语言映射），用户可在设置覆盖
/// - 格式化用 NumberFormatter + currencyCode，系统自动处理符号/小数位/分组
final class CurrencyService {
    static let shared = CurrencyService()

    /// 支持的 9 个唯一币种（13 语言对应的地区主流币种）
    /// 币种名显示用 Locale.localizedString(forCurrencyCode:)，无需手动翻译
    static let supportedCurrencies: [String] = [
        "USD", "EUR", "CNY", "TWD", "JPY", "KRW", "BRL", "VND", "TRY"
    ]

    /// 语言 → 默认币种映射（首次启动按 locale 自动选择）
    private static let languageCurrencyMap: [String: String] = [
        "en": "USD",
        "zh-Hans": "CNY",
        "zh-Hant": "TWD",
        "ja": "JPY",
        "ko": "KRW",
        "de": "EUR", "es": "EUR", "it": "EUR", "fr": "EUR", "nl": "EUR",
        "pt-BR": "BRL",
        "vi": "VND",
        "tr": "TRY"
    ]

    private init() {}

    // MARK: - 当前币种（从 AppSettings 读取，默认按 locale）

    /// 从 ModelContext 读取当前币种；无设置时按 locale 推断
    func currentCurrency(in context: ModelContext) -> String {
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = (try? context.fetch(descriptor))?.first,
           !settings.currentCurrency.isEmpty {
            return settings.currentCurrency
        }
        return Self.defaultCurrencyForCurrentLocale()
    }

    /// 按 locale 推断默认币种（无匹配则 USD）
    static func defaultCurrencyForCurrentLocale() -> String {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.region?.identifier
        // 优先按 region 精确匹配（如 zh-Hans-CN → CNY, zh-Hant-TW → TWD, zh-Hant-HK → HKD 退回 TWD）
        if let region {
            switch (lang, region) {
            case ("zh", "CN"), ("zh", "SG"): return "CNY"
            case ("zh", "TW"): return "TWD"
            case ("zh", "HK"), ("zh", "MO"): return "TWD"  // HKD 未列入支持表，退回 TWD
            default: break
            }
        }
        // 按 languageCode 兜底
        return languageCurrencyMap[lang] ?? "USD"
    }

    // MARK: - 格式化（系统 NumberFormatter 自动处理符号/小数位/分组）

    /// 格式化金额为当前币种字符串
    func format(_ amount: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale.current
        // 负数用括号或减号，避免 AI prompt 中出现奇怪符号
        formatter.maximumFractionDigits = decimalPlaces(for: currency)
        formatter.minimumFractionDigits = decimalPlaces(for: currency)
        return formatter.string(from: NSNumber(value: amount)) ?? ""
    }

    /// 币种符号（如 $ ¥ €）— 用于输入框前缀
    func symbol(for currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale.current
        // 取 "§" 替换数字后的符号部分
        let formatted = formatter.string(from: NSNumber(value: 0)) ?? ""
        // 去掉数字和空格，保留符号
        return formatted.unicodeScalars.filter { scalar in
            !CharacterSet.decimalDigits.contains(scalar)
                && scalar != " "
                && scalar != ","
                && scalar != "."
        }.map { String($0) }.joined()
    }

    /// 小数位数（JPY/KRW/VND 为 0，其他为 2）
    func decimalPlaces(for currency: String) -> Int {
        switch currency {
        case "JPY", "KRW", "VND": return 0
        default: return 2
        }
    }

    /// 币种本地化名称（系统 API，无需手动翻译 13 语言）
    func localizedName(for currency: String) -> String {
        Locale.current.localizedString(forCurrencyCode: currency) ?? currency
    }

    // MARK: - 汇率

    /// 内置汇率表（从 ExchangeRates.json 加载，对 USD）
    private lazy var builtinRates: [String: Double] = {
        guard let url = Bundle.main.url(forResource: "ExchangeRates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode(ExchangeRatesFile.self, from: data) else {
            return ["USD": 1.0]
        }
        return json.rates
    }()

    /// 内置汇率更新日期
    var ratesUpdated: String? {
        guard let url = Bundle.main.url(forResource: "ExchangeRates", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode(ExchangeRatesFile.self, from: data) else {
            return nil
        }
        return json.updated
    }

    /// 获取某币种对 USD 的汇率（用户覆盖优先）
    func rateToUSD(_ currency: String, customRates: [String: Double]) -> Double {
        if let custom = customRates[currency] { return custom }
        return builtinRates[currency] ?? 1.0
    }

    /// 交叉汇率：from → to
    /// rate(from, to) = rateToUSD(to) / rateToUSD(from)
    func exchangeRate(from: String, to: String, customRates: [String: Double]) -> Double {
        let fromUSD = rateToUSD(from, customRates: customRates)
        let toUSD = rateToUSD(to, customRates: customRates)
        guard fromUSD > 0 else { return 1.0 }
        return toUSD / fromUSD
    }

    /// 转换金额
    func convert(_ amount: Double, from: String, to: String, customRates: [String: Double]) -> Double {
        let rate = exchangeRate(from: from, to: to, customRates: customRates)
        return amount * rate
    }

    // MARK: - 切换币种（批量转换所有 Expense）

    /// 切换当前币种并转换所有历史记录
    /// - 旧币种 → 新币种，按汇率乘以 amount
    /// - 更新 AppSettings.currentCurrency
    @MainActor
    func switchCurrency(to newCurrency: String, in context: ModelContext) {
        let descriptor = FetchDescriptor<AppSettings>()
        let settings = (try? context.fetch(descriptor))?.first
        let oldCurrency = settings?.currentCurrency ?? Self.defaultCurrencyForCurrentLocale()
        let customRates = settings?.customRates ?? [:]

        guard oldCurrency != newCurrency else { return }

        // 转换所有 Expense
        let expenseDescriptor = FetchDescriptor<Expense>()
        if let expenses = try? context.fetch(expenseDescriptor) {
            let rate = exchangeRate(from: oldCurrency, to: newCurrency, customRates: customRates)
            for expense in expenses {
                expense.amount *= rate
            }
        }

        // 更新设置
        if let settings {
            settings.currentCurrency = newCurrency
        } else {
            let new = AppSettings()
            new.currentCurrency = newCurrency
            context.insert(new)
        }
        try? context.save()
    }
}

// MARK: - ExchangeRates.json 解析结构

private struct ExchangeRatesFile: Codable {
    let base: String
    let updated: String
    let rates: [String: Double]
}
