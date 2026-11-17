import XCTest
import SwiftData
@testable import StoicSpend

/// FR-32 分类纠错记忆 — 规则存储/命中/导入套用关键 case
final class CategoryRuleTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CategoryRuleStore.clear()
    }

    override func tearDown() {
        CategoryRuleStore.clear()
        super.tearDown()
    }

    func testAddAndMatch() {
        CategoryRuleStore.add(keyword: "肯德基", categoryKey: "cat.food")
        let hit = CategoryRuleStore.match(note: "肯德基 茶叶蛋")
        XCTAssertEqual(hit?.keyword, "肯德基")
        XCTAssertEqual(hit?.categoryKey, "cat.food")
        XCTAssertNil(CategoryRuleStore.match(note: " unrelated "))
        XCTAssertNil(CategoryRuleStore.match(note: ""))
    }

    func testLongestKeywordWins() {
        CategoryRuleStore.add(keyword: "盒马", categoryKey: "cat.food")
        CategoryRuleStore.add(keyword: "盒马鲜生", categoryKey: "cat.transport")
        let hit = CategoryRuleStore.match(note: "盒马鲜生 生鲜水果")
        XCTAssertEqual(hit?.keyword, "盒马鲜生", "多个命中取更长（更具体）关键词")
        XCTAssertEqual(hit?.categoryKey, "cat.transport")
    }

    func testSameKeywordOverwritesAndTruncates() {
        CategoryRuleStore.add(keyword: "瑞幸咖啡", categoryKey: "cat.food")
        CategoryRuleStore.add(keyword: "瑞幸咖啡", categoryKey: "cat.other")
        let items = CategoryRuleStore.load()
        XCTAssertEqual(items.count, 1, "同关键词覆盖旧规则")
        XCTAssertEqual(items[0].categoryKey, "cat.other")

        // 超长关键词截断到 12 字
        CategoryRuleStore.add(keyword: String(repeating: "盒", count: 15), categoryKey: "cat.food")
        XCTAssertEqual(CategoryRuleStore.load().last?.keyword, String(repeating: "盒", count: 12))
    }

    func testRemoveAndClear() {
        CategoryRuleStore.add(keyword: "滴滴", categoryKey: "cat.transport")
        let id = CategoryRuleStore.load()[0].id
        XCTAssertEqual(CategoryRuleStore.remove(id: id).count, 0)
        CategoryRuleStore.add(keyword: "滴滴", categoryKey: "cat.transport")
        CategoryRuleStore.clear()
        XCTAssertTrue(CategoryRuleStore.load().isEmpty)
    }

    func testParseCSVAppliesRules() {
        // 用户教过：盒马 → 餐饮
        CategoryRuleStore.add(keyword: "盒马", categoryKey: "cat.food")
        let csv = "交易时间,交易对方,商品,收/支,金额(元),交易单号\n"
            + "2026-11-12 10:00,盒马鲜生,生鲜水果,支出,56.20,T001\n"
            + "2026-11-13 10:00,瑞幸咖啡,拿铁,支出,29.00,T002\n"
        let result = BackupService.parseCSV(Data(csv.utf8))
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.records[0].category, .food, "命中规则：盒马鲜生 → 餐饮")
        XCTAssertTrue(result.records[0].ruleApplied)
        XCTAssertNil(result.records[1].category, "未命中规则走原映射（瑞幸无关键词）")
        XCTAssertFalse(result.records[1].ruleApplied)
        XCTAssertEqual(result.recordsRuleHits, 1)
    }

    func testParseCSVAppliesCustomCategoryRule() {
        // 自定义分类规则（"custom:<uuid>"）
        CategoryStore.add(name: "网络", emoji: "🌐")
        let custom = CategoryStore.load()[0]
        CategoryRuleStore.add(keyword: "宽带", categoryKey: CategoryStore.storageKey(for: custom.id))
        let csv = "交易时间,商品,收/支,金额(元)\n2026-11-14 09:00,宽带年费,支出,360.00\n"
        let result = BackupService.parseCSV(Data(csv.utf8))
        XCTAssertEqual(result.records.count, 1)
        XCTAssertNil(result.records[0].category)
        XCTAssertEqual(result.records[0].ruleCategoryKey, CategoryStore.storageKey(for: custom.id))

        // 落库后 customCategoryID 生效
        let container = try! ModelContainer(for: Expense.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        try! BackupService.insertCSVRecords(result.records, in: context)
        let all = try! context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].customCategoryID, custom.id)
        XCTAssertEqual(all[0].categoryGroupKey, CategoryStore.storageKey(for: custom.id))
        CategoryStore.remove(id: custom.id)
    }
}
