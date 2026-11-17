import XCTest
@testable import StoicSpend

/// FR-30 微信/支付宝账单导入 — 表头探测 / 列映射 / 金额清洗 / 退款 / 去重关键 case
final class BillImportTests: XCTestCase {

    // MARK: 样本构造

    /// 微信账单：16 行说明文字 + 表头 + 数据（收入/退款/不计收支/引号金额/重复单号）
    private func weChatCSV() -> Data {
        var lines: [String] = []
        lines.append("微信支付账单明细,")
        for i in 1...15 { lines.append("说明行\(i)，仅供核对，,,,,") }
        lines.append("交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注")
        lines.append("\"2026-11-01 08:30:00\",\"商户消费\",\"肯德基\",\"茶叶蛋\",\"支出\",\"¥6.50\",\"零钱\",\"支付成功\",\"4201WX0001\",\"M001\",\"\"")
        lines.append("\"2026-11-02 12:00:00\",\"微信红包\",\"张三\",\"红包\",\"收入\",\"¥88.00\",\"零钱\",\"已存入零钱\",\"4201WX0002\",\"M002\",\"\"")
        lines.append("\"2026-11-03 09:00:00\",\"商户消费\",\"瑞幸咖啡\",\"拿铁\",\"支出\",\"¥1,299.00\",\"招商银行卡(1234)\",\"已全额退款\",\"4201WX0003\",\"M003\",\"\"")
        lines.append("\"2026-11-04 18:00:00\",\"转账\",\"李四\",\"转账\",\"不计收支\",\"¥200.00\",\"零钱\",\"已收钱\",\"4201WX0004\",\"M004\",\"\"")
        lines.append("\"2026-11-05 19:00:00\",\"商户消费\",\"美团\",\"外卖\",\"支出\",\"¥35.80\",\"零钱\",\"支付成功\",\"4201WX0001\",\"M005\",\"\"")
        return lines.joined(separator: "\n").data(using: .utf8)!
    }

    /// 支付宝账单：GBK 编码 + 全角括号表头 + 尾随负号金额
    private func aliPayCSV() -> Data {
        let text = [
            "支付宝交易记录明细查询,,",
            "账号:xxx@alipay.com,起始日期:2026-11-01,终止日期:2026-11-30,,",
            "----------------------------------------,",
            "交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,商品名称,金额（元）,收/支,交易状态,备注",
            "2026110622001,A1001,2026-11-06 10:00:00,2026-11-06 10:00:01,2026-11-06 10:00:01,上海市,交易收款,\"盒马鲜生\",\"生鲜水果\",56.20,收入,交易成功,",
            "2026110622002,A1002,2026-11-07 11:00:00,2026-11-07 11:00:01,2026-11-07 11:00:01,上海市,交易付款,\"滴滴出行\",\"快车\",-23.45,支出,交易成功,",
        ].joined(separator: "\n")
        // 转 GB18030（支付宝旧版导出编码）
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return text.data(using: encoding)!
    }

    private func expense(date: Date, amount: Double, note: String, refId: String? = nil, flow: FlowType = .expense) -> Expense {
        let e = Expense(amount: amount, date: date, note: note)
        e.refId = refId
        e.flowType = flow
        return e
    }

    // MARK: 关键 case

    func testWeChatHeaderDetectionAndMapping() {
        let result = BackupService.parseCSV(weChatCSV())
        XCTAssertEqual(result.headerRow, 17)               // 16 行说明后第 17 行是表头
        XCTAssertEqual(result.records.count, 4)            // 最后一行是重复单号，应去重
        XCTAssertEqual(result.duplicateRows, 1)
        XCTAssertEqual(result.skippedRows, 0)

        let first = result.records[0]
        XCTAssertEqual(first.flowType, .expense)
        XCTAssertEqual(first.amount, 6.50, accuracy: 0.001)
        XCTAssertEqual(first.refId, "4201WX0001")
        XCTAssertTrue(first.note.contains("茶叶蛋"))

        let income = result.records[1]
        XCTAssertEqual(income.flowType, .income)           // 收入落库不统计
        XCTAssertEqual(result.incomeCount, 1)

        let refund = result.records[2]
        XCTAssertEqual(refund.flowType, .refund)           // 已全额退款 → 退款
        XCTAssertEqual(refund.amount, 1299.00, accuracy: 0.001)   // 千分位 + ¥ 清洗
        XCTAssertEqual(result.refundCount, 1)

        let transfer = result.records[3]
        XCTAssertEqual(transfer.flowType, .transfer)       // 不计收支 → 转账
        XCTAssertEqual(result.transferCount, 1)
    }

    func testAliPayGBKAndFullWidthHeader() {
        let result = BackupService.parseCSV(aliPayCSV())
        XCTAssertEqual(result.headerRow, 4)
        XCTAssertEqual(result.records.count, 2)

        let income = result.records[0]
        XCTAssertEqual(income.flowType, .income)
        XCTAssertEqual(income.amount, 56.20, accuracy: 0.001)
        XCTAssertTrue(income.note.contains("盒马") || income.note.contains("生鲜"))  // GBK 解码无乱码

        let expenseRow = result.records[1]
        XCTAssertEqual(expenseRow.amount, 23.45, accuracy: 0.001)  // 尾随负号清洗取绝对值
        XCTAssertEqual(expenseRow.flowType, .expense)
    }

    func testLegacyHeaderStillWorks() {
        // 旧格式（随手记/自导出）：第 0 行表头，无收/支列
        let text = "日期,金额,备注,分类\n2026-11-08 10:00,12.50,午饭,餐饮"
        let result = BackupService.parseCSV(text.data(using: .utf8)!)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records[0].amount, 12.50, accuracy: 0.001)
        XCTAssertEqual(result.records[0].flowType, .expense)
        XCTAssertEqual(result.records[0].category, .food)
    }

    func testSameFileTwiceNoNewRecords() {
        let data = weChatCSV()
        let first = BackupService.parseCSV(data)
        XCTAssertEqual(first.records.count, 4)

        // 模拟已落库：同一文件再导一次 → 全部判重，0 新增
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let existing = first.records.map { r in
            expense(date: r.date, amount: r.amount, note: r.note, refId: r.refId, flow: r.flowType)
        }
        let second = BackupService.parseCSV(data, existing: existing)
        XCTAssertTrue(second.records.isEmpty)
        XCTAssertEqual(second.duplicateRows, 5)   // 5 行数据全部判重（含重复单号那行）
    }

    func testDedupByKeyWhenNoRefId() {
        let d = "日期,金额,备注\n2026-11-09 09:00,10.00,早餐"
        let row = "2026-11-09 09:00,10.00,早餐"
        let existing = [expense(date: Date(timeIntervalSince1970: 1_768_000_000), amount: 10, note: "早餐")]
        // 直接对比：历史记录同「日期+金额+备注」→ 判重（无单号路径）
        let result = BackupService.parseCSV((d + "\n" + row).data(using: .utf8)!)
        XCTAssertEqual(result.records.count, 1)
        // 用同日期同额同备注的已有账目再导 → 重复
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.locale = Locale(identifier: "en_US_POSIX")
        let stored = expense(date: df.date(from: "2026-11-09 09:00")!, amount: 10, note: "早餐")
        let again = BackupService.parseCSV((d + "\n" + row).data(using: .utf8)!, existing: [stored])
        XCTAssertTrue(again.records.isEmpty)
        XCTAssertEqual(again.duplicateRows, 2)   // 两行相同，均判重
        _ = existing  // 仅供构造参考
    }

    func testUnparsableRowsCounted() {
        let text = "交易时间,金额(元),商品\nnot-a-date,10.00,缺失日期\n2026-11-10 08:00,not-number,缺失金额\n,,,\n2026-11-11 09:00,20.00,正常"
        let result = BackupService.parseCSV(text.data(using: .utf8)!)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.skippedRows, 2)   // 空行不计入
    }
}
