import XCTest
import SwiftData
@testable import StoicSpend

/// FR-10 数据管线关键测试 — CSV 导出/导入、JSON 备份/恢复、快照/撤销
final class BackupServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: Schema([
                Expense.self, BudgetModel.self, AppSettings.self,
                WeeklyReview.self, AlreadyHaveItem.self, DailyQuote.self,
            ]),
            configurations: [config]
        )
        context = ModelContext(container)
        BackupService.clearSnapshot()
    }

    override func tearDownWithError() throws {
        BackupService.clearSnapshot()
        container = nil
        context = nil
    }

    private func makeExpense(amount: Double, note: String = "", nature: ExpenseNature? = nil,
                             category: ExpenseCategory = .food, emotion: ExpenseEmotion? = nil,
                             review: ReviewResult? = nil) -> Expense {
        let e = Expense(amount: amount, note: note, nature: nature, category: category, emotion: emotion)
        e.review = review
        return e
    }

    // MARK: - CSV 导出

    func testMakeCSVContainsBOMHeaderAndRows() throws {
        let e1 = makeExpense(amount: 32.5, note: "午餐", nature: .chosen, category: .food, emotion: .calm, review: .affirm)
        let e2 = makeExpense(amount: 88, note: "含,逗号\"引号", nature: .impulse, category: .gadget)
        let data = BackupService.makeCSV(expenses: [e1, e2])

        // BOM
        XCTAssertEqual([UInt8](data.prefix(3)), [0xEF, 0xBB, 0xBF], "CSV 必须带 UTF-8 BOM")
        let text = String(decoding: data.dropFirst(3), as: UTF8.self)
        XCTAssertTrue(text.contains("日期,金额,性质,分类,情绪,备注,回顾结果"))
        XCTAssertTrue(text.contains("32.50"))
        XCTAssertTrue(text.contains("主动选择"))
        XCTAssertTrue(text.contains("会再做同样选择"))
        // 引号/逗号转义
        XCTAssertTrue(text.contains("\"含,逗号\"\"引号\""))
        // 冲动 → gold 语义仍输出"冲动"
        XCTAssertTrue(text.contains("冲动"))
    }

    // MARK: - CSV 导入解析

    func testParseCSVWithSuishoujiHeadersAndIncomeSkip() throws {
        let csv = "交易时间,金额(元),类型,一级分类,备注\n"
            + "2026-11-08 12:30,25.50,支出,餐饮,火锅\n"
            + "2026-11-07 19:00,88.00,支出,数码,机械键盘\n"
            + "2026-11-06 10:00,999.00,收入,其他,工资\n"
        let result = BackupService.parseCSV(Data(csv.utf8))
        XCTAssertEqual(result.records.count, 2, "收入行应被跳过")
        XCTAssertEqual(result.skippedRows, 1)
        XCTAssertEqual(result.records[0].amount, 25.5, accuracy: 1e-9)
        XCTAssertEqual(result.records[0].note, "火锅")
        XCTAssertEqual(result.records[0].category, .food, "餐饮应映射到九分法 cat.food")
        XCTAssertEqual(result.records[1].category, .gadget, "数码应映射到九分法 cat.gadget")
        XCTAssertFalse(result.sampleNotes.isEmpty, "应生成预览样例")
    }

    func testParseCSVSupportsGB18030Encoding() throws {
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let text = "日期,金额,类型,备注\n2026-11-08 12:30,12.00,支出,地铁通勤\n"
        let data = text.data(using: gb18030)
        XCTAssertNotNil(data)
        let result = BackupService.parseCSV(data!)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records[0].note, "地铁通勤")
    }

    func testParseCSVWithBrokenContentReturnsEmpty() throws {
        let result = BackupService.parseCSV(Data("乱七八糟没有表头".utf8))
        XCTAssertTrue(result.records.isEmpty, "损坏文件应返回空记录而不抛出")
    }

    func testInsertCSVRecordsAppends() throws {
        let csv = "日期,金额,备注\n2026-11-08 12:30,10.00,咖啡\n2026-11-08 13:00,20.00,午餐\n"
        let result = BackupService.parseCSV(Data(csv.utf8))
        let count = try BackupService.insertCSVRecords(result.records, in: context)
        XCTAssertEqual(count, 2)
        let descriptor = FetchDescriptor<Expense>()
        XCTAssertEqual(try context.fetchCount(descriptor), 2)
    }

    // MARK: - JSON 备份/恢复

    func testJSONBackupRoundtripPreservesAllFields() throws {
        let e = makeExpense(amount: 45.0, note: "给妈妈买护膝", nature: .chosen,
                            category: .family, emotion: .satisfied, review: .reconsider)
        e.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try BackupService.makeBackupJSON(expenses: [e], budget: nil, settings: nil)
        let backup = try BackupService.parseBackup(data)
        XCTAssertEqual(backup.schemaVersion, BackupService.schemaVersion)
        XCTAssertEqual(backup.expenses.count, 1)
        let item = backup.expenses[0]
        XCTAssertEqual(item.amount, 45.0, accuracy: 1e-9)
        XCTAssertEqual(item.note, "给妈妈买护膝")
        XCTAssertEqual(item.nature, "chosen")
        XCTAssertEqual(item.category, "cat.family")
        XCTAssertEqual(item.emotion, "emo.satisfied")
        XCTAssertEqual(item.review, "reconsider")
    }

    func testRestoreReplacesAllExpenses() throws {
        // 先存 2 条旧数据
        context.insert(makeExpense(amount: 1))
        context.insert(makeExpense(amount: 2))
        try context.save()

        let original = makeExpense(amount: 99, note: "恢复来源", nature: .necessity, category: .transport)
        let data = try BackupService.makeBackupJSON(expenses: [original], budget: nil, settings: nil)
        let backup = try BackupService.parseBackup(data)
        let restored = try BackupService.restore(backup, in: context)

        XCTAssertEqual(restored, 1)
        let all = try context.fetch(FetchDescriptor<Expense>())
        XCTAssertEqual(all.count, 1, "恢复应覆盖旧数据（replace 语义）")
        XCTAssertEqual(all[0].amount, 99, accuracy: 1e-9)
        XCTAssertEqual(all[0].note, "恢复来源")
        XCTAssertEqual(all[0].category, .transport)
    }

    // MARK: - 快照/撤销

    func testSnapshotAndUndoRestoresPreviousState() throws {
        // 导入前 3 条
        let before = (1...3).map { makeExpense(amount: Double($0)) }
        before.forEach { context.insert($0) }
        try context.save()

        BackupService.makeSnapshot(expenses: before)
        XCTAssertTrue(BackupService.hasSnapshot)

        // 模拟导入 +2 条
        context.insert(makeExpense(amount: 10))
        context.insert(makeExpense(amount: 20))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 5)

        // 撤销 → 回到 3 条
        let restored = try BackupService.undoImport(in: context)
        XCTAssertEqual(restored, 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Expense>()), 3)
        XCTAssertFalse(BackupService.hasSnapshot, "撤销后快照应清空")
    }
}
