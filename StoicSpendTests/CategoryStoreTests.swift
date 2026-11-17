import XCTest
@testable import StoicSpend

/// FR-29 自定义分类 — 存储/上限/删除/key 往返
@MainActor
final class CategoryStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: CategoryStore.storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: CategoryStore.storageKey)
        super.tearDown()
    }

    func testAddAndRoundtrip() {
        CategoryStore.add(name: "手办", emoji: "🎮")
        let items = CategoryStore.load()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "手办")
        XCTAssertEqual(items[0].emoji, "🎮")
        // key 往返
        let key = CategoryStore.storageKey(for: items[0].id)
        XCTAssertEqual(CategoryStore.uuid(fromKey: key), items[0].id)
    }

    func testNameTruncatedToTwentyChars() {
        CategoryStore.add(name: String(repeating: "网", count: 25), emoji: "🌐")
        XCTAssertEqual(CategoryStore.load().first?.name, String(repeating: "网", count: 20))
        // 短名不受影响，如「通信费」
        CategoryStore.add(name: " 通信费 ", emoji: "📞")
        XCTAssertEqual(CategoryStore.load().last?.name, "通信费")
    }

    func testMaxCountSix() {
        for i in 0..<9 {
            CategoryStore.add(name: "类\(i)", emoji: "📦")
        }
        XCTAssertEqual(CategoryStore.load().count, CategoryStore.maxCount)
    }

    func testRemoveAndExpenseGroupKey() {
        CategoryStore.add(name: "猫粮", emoji: "🐱")
        let cat = CategoryStore.load()[0]

        let e = Expense(amount: 12)
        e.customCategoryID = cat.id
        XCTAssertEqual(e.categoryGroupKey, "custom:\(cat.id.uuidString)")
        XCTAssertTrue(e.isCustomCategory)
        XCTAssertEqual(e.categoryEmoji, "🐱")
        XCTAssertEqual(e.categoryDisplayName, "猫粮")

        // 删除类别 → 显示回落内置
        CategoryStore.remove(id: cat.id)
        XCTAssertEqual(e.categoryEmoji, e.category.emoji)
        XCTAssertFalse(e.isCustomCategory)
    }

    func testBuiltinKeyUnaffected() {
        let e = Expense(amount: 5, category: .transport)
        XCTAssertNil(e.customCategoryID)
        XCTAssertEqual(e.categoryGroupKey, ExpenseCategory.transport.rawValue)
        XCTAssertEqual(e.categoryEmoji, "🚕")
    }
}
