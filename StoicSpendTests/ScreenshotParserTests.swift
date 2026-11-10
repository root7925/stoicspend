import XCTest
@testable import StoicSpend

/// FR-25 — 截图金额/商户解析 + App Group 待处理捕获队列
final class ScreenshotParserTests: XCTestCase {

    // MARK: 金额解析

    func testAmountFromKeywordLine() {
        XCTAssertEqual(ScreenshotParser.parseAmount(from: ["微信支付", "实付金额¥1,280.00"]), 1280.0)
        XCTAssertEqual(ScreenshotParser.parseAmount(from: ["实付款 35.5"]), 35.5)
    }

    func testAmountFromCurrencyPrefix() {
        XCTAssertEqual(ScreenshotParser.parseAmount(from: ["支付成功", "¥23.80"]), 23.8)
        XCTAssertEqual(ScreenshotParser.parseAmount(from: ["￥12"]), 12)
    }

    func testAmountFallbackTakesLastNumber() {
        XCTAssertEqual(ScreenshotParser.parseAmount(from: ["订单 2026", "38"]), 38)
    }

    func testAmountMissingReturnsNil() {
        XCTAssertNil(ScreenshotParser.parseAmount(from: ["支付成功"]))
        XCTAssertNil(ScreenshotParser.parseAmount(from: []))
    }

    // MARK: 商户名猜测

    func testMerchantSkipsBoilerplateAndNumbers() {
        XCTAssertEqual(ScreenshotParser.guessMerchant(from: ["微信支付", "星巴克咖啡", "实付 ¥35"]), "星巴克咖啡")
        XCTAssertNil(ScreenshotParser.guessMerchant(from: ["微信支付", "支付成功"]))
        XCTAssertNil(ScreenshotParser.guessMerchant(from: ["瑞幸咖啡 门店 1001"]))
    }

    // MARK: App Group 队列（先进先出，读即清空）

    @MainActor
    func testPendingCaptureStoreRoundtrip() {
        PendingCaptureStore.clear()
        let cap = PendingCapture(id: UUID(), amount: 35.5, merchant: "星巴克咖啡", createdAt: .now)
        PendingCaptureStore.append(cap)

        let loaded = PendingCaptureStore.load()
        XCTAssertEqual(loaded, cap)
        // 读即清空：第二次读取为空
        XCTAssertNil(PendingCaptureStore.load())
    }

    @MainActor
    func testPendingCaptureStoreAppendFailureKeepsAmountNil() {
        PendingCaptureStore.clear()
        let cap = PendingCapture(id: UUID(), amount: nil, merchant: nil, createdAt: .now)
        PendingCaptureStore.append(cap)
        XCTAssertEqual(PendingCaptureStore.load()?.amount, nil)
        PendingCaptureStore.clear()
    }
}
