import XCTest
@testable import StoicSpend

/// V1.2（FR-19~FR-23）关键逻辑单测
final class SubscriptionServiceTests: XCTestCase {

    private func makeExpense(amount: Double, note: String, daysAgo: Double) -> Expense {
        Expense(
            amount: amount,
            date: Date.now.addingTimeInterval(-daysAgo * 86400),
            note: note
        )
    }

    // MARK: - FR-19 识别规则

    func testDetectMonthly() {
        let expenses = [
            makeExpense(amount: 25, note: "视频会员", daysAgo: 60),
            makeExpense(amount: 25, note: "视频会员", daysAgo: 30),
            makeExpense(amount: 25, note: "视频会员", daysAgo: 1),
        ]
        let subs = SubscriptionService.detect(expenses)
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs[0].period, .monthly)
        XCTAssertEqual(subs[0].amount, 25)
        XCTAssertEqual(subs[0].dates.count, 3)
    }

    func testDetectWeekly() {
        let expenses = [
            makeExpense(amount: 12, note: "健身房", daysAgo: 14),
            makeExpense(amount: 12, note: "健身房", daysAgo: 7),
            makeExpense(amount: 12, note: "健身房", daysAgo: 0.5),
        ]
        let subs = SubscriptionService.detect(expenses)
        XCTAssertEqual(subs.count, 1)
        XCTAssertEqual(subs[0].period, .weekly)
        XCTAssertEqual(subs[0].monthlyAmount, 12 * 52.0 / 12.0, accuracy: 0.01)
    }

    func testNotSubscriptionWhenAmountsDiffer() {
        let expenses = [
            makeExpense(amount: 25, note: "外卖", daysAgo: 30),
            makeExpense(amount: 40, note: "外卖", daysAgo: 1),
        ]
        XCTAssertTrue(SubscriptionService.detect(expenses).isEmpty)
    }

    func testNotSubscriptionWhenSingleEntry() {
        let expenses = [makeExpense(amount: 25, note: "会员", daysAgo: 30)]
        XCTAssertTrue(SubscriptionService.detect(expenses).isEmpty)
    }

    func testNotSubscriptionWhenGapIrregular() {
        let expenses = [
            makeExpense(amount: 25, note: "随手买", daysAgo: 100),
            makeExpense(amount: 25, note: "随手买", daysAgo: 1),
        ]
        XCTAssertTrue(SubscriptionService.detect(expenses).isEmpty)
    }

    func testEmptyNoteExcluded() {
        let expenses = [
            makeExpense(amount: 25, note: "", daysAgo: 30),
            makeExpense(amount: 25, note: "", daysAgo: 1),
        ]
        XCTAssertTrue(SubscriptionService.detect(expenses).isEmpty)
    }

    // MARK: - R-6 守住金额

    func testGuardAmountIncludesCancelledSubs() {
        SubscriptionService.unmarkCancelled("视频会员|25.0|monthly")
        let expenses = [
            makeExpense(amount: 25, note: "视频会员", daysAgo: 60),
            makeExpense(amount: 25, note: "视频会员", daysAgo: 30),
            makeExpense(amount: 25, note: "视频会员", daysAgo: 1),
        ]
        // 取消前：只有粉碎累计（测试环境通常为 0）
        let before = SubscriptionService.guardAmount(from: expenses)
        SubscriptionService.markCancelled("视频会员|25.0|monthly", monthlyAmount: 25)
        let after = SubscriptionService.guardAmount(from: expenses)
        XCTAssertEqual(after - before, 25, accuracy: 0.01)
        SubscriptionService.unmarkCancelled("视频会员|25.0|monthly")
    }

    // MARK: - FR-20 时间剃刀

    @MainActor
    func testRazorStoreAddRemove() {
        let before = RazorStore.load().count
        let items = RazorStore.add(name: "新耳机")
        XCTAssertEqual(items.count, before + 1)
        XCTAssertEqual(items.first?.name, "新耳机")
        XCTAssertFalse(items.first!.expired)

        let afterRemove = RazorStore.remove(id: items[0].id)
        XCTAssertEqual(afterRemove.count, before)
    }

    @MainActor
    func testRazorItemExpired() {
        let item = RazorItem(id: UUID(), name: "x", createdAt: Date.now.addingTimeInterval(-73 * 3600))
        XCTAssertTrue(item.expired)
    }
}
