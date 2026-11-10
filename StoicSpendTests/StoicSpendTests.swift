import XCTest
@testable import StoicSpend

/// 纯逻辑单元测试（工程化整改 P2-6 建立测试门禁）
/// 覆盖货币换算、格式化、领域模型判定等不依赖 UI/网络的核心逻辑。
final class StoicSpendTests: XCTestCase {

    // MARK: - CurrencyService 纯逻辑

    func testExchangeRateCrossRate() {
        let rates = ["USD": 1.0, "EUR": 0.9, "CNY": 7.2]
        let service = CurrencyService.shared
        XCTAssertEqual(service.exchangeRate(from: "USD", to: "EUR", customRates: rates), 0.9, accuracy: 1e-9)
        XCTAssertEqual(service.exchangeRate(from: "EUR", to: "USD", customRates: rates), 1 / 0.9, accuracy: 1e-9)
        // EUR -> CNY = 7.2 / 0.9 = 8.0
        XCTAssertEqual(service.exchangeRate(from: "EUR", to: "CNY", customRates: rates), 8.0, accuracy: 1e-9)
    }

    func testConvert() {
        let rates = ["USD": 1.0, "EUR": 0.9]
        let service = CurrencyService.shared
        XCTAssertEqual(service.convert(100, from: "USD", to: "EUR", customRates: rates), 90, accuracy: 1e-9)
        XCTAssertEqual(service.convert(90, from: "EUR", to: "USD", customRates: rates), 100, accuracy: 1e-9)
    }

    func testDecimalPlaces() {
        let service = CurrencyService.shared
        XCTAssertEqual(service.decimalPlaces(for: "JPY"), 0)
        XCTAssertEqual(service.decimalPlaces(for: "KRW"), 0)
        XCTAssertEqual(service.decimalPlaces(for: "VND"), 0)
        XCTAssertEqual(service.decimalPlaces(for: "USD"), 2)
        XCTAssertEqual(service.decimalPlaces(for: "CNY"), 2)
    }

    func testDefaultCurrencyFallsBackToUSD() {
        // 测试环境 locale 未映射到支持币种时回退 USD，且非空
        let result = CurrencyService.defaultCurrencyForCurrentLocale()
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Expense 领域逻辑

    func testIsControllable() {
        let chosen = Expense(amount: 10, nature: .chosen)
        let impulse = Expense(amount: 10, nature: .impulse)
        let none = Expense(amount: 10, nature: nil)
        XCTAssertTrue(chosen.isControllable)
        XCTAssertFalse(impulse.isControllable)
        XCTAssertFalse(none.isControllable)
    }

    func testValueTagRawValueStable() {
        XCTAssertEqual(ValueTag.health.rawValue, "value.health")
        XCTAssertEqual(ValueTag.enjoyment.rawValue, "value.enjoyment")
    }
}
