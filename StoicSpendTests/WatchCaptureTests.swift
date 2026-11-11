import XCTest
@testable import StoicSpend

/// FR-24 Watch 快记 — 载荷编解码与校验
final class WatchCaptureTests: XCTestCase {

    private func makeCapture(amount: Double = 30) -> WatchCapture {
        WatchCapture(
            amount: amount,
            natureRaw: ExpenseNature.chosen.rawValue,
            categoryRaw: ExpenseCategory.food.rawValue,
            date: Date(timeIntervalSince1970: 1_760_000_000)
        )
    }

    // 编码 → 消息字典 → 解码，字段一一还原
    func testRoundTripThroughMessageDictionary() throws {
        let capture = makeCapture()
        let data = try XCTUnwrap(capture.encodedData)
        let decoded = WatchCapture.decode(from: [WatchSyncKeys.messageKey: data])

        XCTAssertEqual(decoded, capture)
        XCTAssertEqual(decoded?.amount, 30)
        XCTAssertEqual(decoded?.nature, .chosen)
        XCTAssertEqual(decoded?.category, .food)
        XCTAssertEqual(decoded?.date.timeIntervalSince1970, 1_760_000_000)
    }

    // transferUserInfo 路径同样按消息字典解码
    func testDecodeFromUserInfoPayload() throws {
        let capture = makeCapture(amount: 12.5)
        let data = try XCTUnwrap(capture.encodedData)
        let decoded = WatchCapture.decode(from: [WatchSyncKeys.messageKey: data])

        XCTAssertEqual(decoded?.amount, 12.5)
        XCTAssertEqual(decoded?.nature, .chosen)
    }

    // 金额 0 / 负数无效，不落库
    func testInvalidAmountRejected() {
        XCTAssertFalse(makeCapture(amount: 0).isValid)
        XCTAssertFalse(makeCapture(amount: -8).isValid)
        XCTAssertTrue(makeCapture(amount: 0.5).isValid)
    }

    // nature/category rawValue 双向映射（持久化稳定性）
    func testEnumRawValuesMapBack() {
        for nature in [ExpenseNature.chosen, .impulse, .necessity] {
            XCTAssertEqual(ExpenseNature(rawValue: nature.rawValue), nature)
        }
        for category in ExpenseCategory.allCases {
            XCTAssertEqual(ExpenseCategory(rawValue: category.rawValue), category)
        }
        XCTAssertEqual(ExpenseCategory.allCases.count, 9)
    }

    // 缺键 / 坏数据 → 返回 nil，接收端静默丢弃
    func testDecodeRejectsMalformedPayloads() throws {
        XCTAssertNil(WatchCapture.decode(from: [:]))
        XCTAssertNil(WatchCapture.decode(from: [WatchSyncKeys.messageKey: "not data".data(using: .utf8)!]))
        let badData = try XCTUnwrap("{}".data(using: .utf8))
        XCTAssertNil(WatchCapture.decode(from: [WatchSyncKeys.messageKey: badData]))
    }
}
