import XCTest
@testable import StoicSpend

/// V1.1 迭代（FR-13~FR-18）关键逻辑单测
final class QuickAddV11Tests: XCTestCase {

    // MARK: - FR-18 算式求值

    func testEvaluateAddChain() {
        XCTAssertEqual(QuickAddView.evaluate("12+8"), 20)
        XCTAssertEqual(QuickAddView.evaluate("10"), 10)
        XCTAssertEqual(QuickAddView.evaluate(""), 0)
    }

    func testEvaluateAA() {
        XCTAssertEqual(QuickAddView.evaluate("12+8÷2"), 16)
        XCTAssertEqual(QuickAddView.evaluate("5÷2"), 2.5)
    }

    func testEvaluateDecimals() {
        XCTAssertEqual(QuickAddView.evaluate("1.5+2.5"), 4, accuracy: 0.0001)
        XCTAssertEqual(QuickAddView.evaluate("0.1+0.2"), 0.3, accuracy: 0.0001)
    }

    func testEvaluateGarbage() {
        XCTAssertEqual(QuickAddView.evaluate("++"), 0)
        XCTAssertEqual(QuickAddView.evaluate("abc"), 0)
    }

    // MARK: - FR-14 自然语言解析

    func testParseCategoryKeywords() {
        XCTAssertEqual(NaturalExpenseParser.parseCategory(from: "早上咖啡"), .food)
        XCTAssertEqual(NaturalExpenseParser.parseCategory(from: "机票"), .travel)       // travel 优先于 transport
        XCTAssertEqual(NaturalExpenseParser.parseCategory(from: "打车去公司"), .transport)
        XCTAssertEqual(NaturalExpenseParser.parseCategory(from: "手机壳"), .gadget)
        XCTAssertEqual(NaturalExpenseParser.parseCategory(from: "房租"), .housing)
    }

    func testParseCategoryUnknown() {
        XCTAssertNil(NaturalExpenseParser.parseCategory(from: "神秘物品"))
        XCTAssertNil(NaturalExpenseParser.parseCategory(from: ""))
    }

    func testParseAmount() {
        XCTAssertEqual(NaturalExpenseParser.parseAmount(from: "记一笔 35 咖啡"), 35)
        XCTAssertEqual(NaturalExpenseParser.parseAmount(from: "咖啡 12.5"), 12.5)
        XCTAssertNil(NaturalExpenseParser.parseAmount(from: "没写金额"))
    }

    // MARK: - FR-17 常用组合存储

    func testRecentComboRecordAndDedup() {
        RecentComboStore.clear()
        RecentComboStore.record(nature: .chosen, category: .food)
        RecentComboStore.record(nature: .impulse, category: .beauty)
        RecentComboStore.record(nature: .chosen, category: .food)   // 重复 → 移到最前
        var combos = RecentComboStore.load()
        XCTAssertEqual(combos.count, 2)
        XCTAssertEqual(combos.first?.categoryRaw, ExpenseCategory.food.rawValue)
        XCTAssertEqual(combos.first?.natureRaw, ExpenseNature.chosen.rawValue)
    }

    func testRecentComboMaxThree() {
        RecentComboStore.clear()
        RecentComboStore.record(nature: .chosen, category: .food)
        RecentComboStore.record(nature: .chosen, category: .beauty)
        RecentComboStore.record(nature: .necessity, category: .transport)
        RecentComboStore.record(nature: .impulse, category: .gadget)   // 第 4 个 → 挤掉最旧
        let combos = RecentComboStore.load()
        XCTAssertEqual(combos.count, 3)
        XCTAssertFalse(combos.contains { $0.categoryRaw == ExpenseCategory.food.rawValue })
        XCTAssertEqual(combos.first?.categoryRaw, ExpenseCategory.gadget.rawValue)
    }

    func testRecentComboLabel() {
        let combo = RecentCombo(natureRaw: ExpenseNature.chosen.rawValue, categoryRaw: ExpenseCategory.food.rawValue)
        // chip 标签只含 emoji + 分类名（性质点按仍套用但不展示，防止换行）
        XCTAssertTrue(combo.label.contains("🍜"))
        XCTAssertTrue(combo.label.contains("饮食"))
        XCTAssertFalse(combo.label.contains("主动"))
    }
}
