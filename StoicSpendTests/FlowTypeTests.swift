import XCTest
@testable import StoicSpend

/// FR-31 资金流类型 — 统计口径关键 case
final class FlowTypeTests: XCTestCase {

    func testDefaultIsExpense() {
        // 旧数据/新建记录默认消费（SwiftData 轻量迁移回落）
        XCTAssertEqual(Expense(amount: 1).flowType, .expense)
        XCTAssertTrue(Expense(amount: 1).isStatistical)
    }

    func testRefundOffsetsNegatively() {
        let refund = Expense(amount: 25)
        refund.flowType = .refund
        XCTAssertTrue(refund.isStatistical)
        XCTAssertEqual(refund.statAmount, -25)
    }

    func testIncomeAndTransferNeverCount() {
        let income = Expense(amount: 5000)
        income.flowType = .income
        let transfer = Expense(amount: 300)
        transfer.flowType = .transfer
        XCTAssertFalse(income.isStatistical)
        XCTAssertFalse(transfer.isStatistical)
        XCTAssertEqual(income.statAmount, 0)
        XCTAssertEqual(transfer.statAmount, 0)
        XCTAssertNotNil(income.flowTag)
        XCTAssertNotNil(transfer.flowTag)
        XCTAssertNil(Expense(amount: 1).flowTag)   // 消费不打标签
    }

    func testBackupRoundtripFlowTypeAndRefId() throws {
        let e = Expense(amount: 88, note: "会员退款")
        e.flowType = .refund
        e.refId = "4201WX123"

        let backup = BackupService.expenseBackupForTesting(e)
        XCTAssertEqual(backup.flowType, "flow.refund")
        XCTAssertEqual(backup.refId, "4201WX123")

        // 旧备份（无 flowType 字段）回落消费
        let json = try JSONEncoder().encode(backup)
        let obj = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        var legacy = obj
        legacy.removeValue(forKey: "flowType")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(BackupService.ExpenseBackup.self, from: legacyData)
        XCTAssertNil(decoded.flowType)
    }
}
