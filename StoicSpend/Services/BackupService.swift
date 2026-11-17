import Foundation
import SwiftData

/// FR-10 数据备份与导入
/// - JSON 全量备份：含全部字段 + schemaVersion，可完整恢复
/// - CSV 导入：仅追加，表头映射兼容随手记/鲨鱼记账等主流记账 App
/// - 导入前自动快照，导入后可一键撤销
enum BackupService {

    /// 与 ModelContainerSetup.AppSchemaV2 对应
    static let schemaVersion = 2

    static let backupFilename = "stoicspend_backup.json"
    static let snapshotKey = "import.snapshot.data"

    // MARK: - JSON 备份文件结构

    struct BackupFile: Codable {
        var schemaVersion: Int
        var exportDate: Date
        var appVersion: String
        var expenses: [ExpenseBackup]
        var budgetMonthlyLimit: Double?
        var settings: SettingsBackup?
    }

    struct ExpenseBackup: Codable {
        var id: UUID
        var amount: Double
        var date: Date
        var note: String
        var nature: String?
        var values: [String]
        var emotionalTrigger: String?
        var category: String
        var customCategoryKey: String?   // FR-29 自定义分类（"custom:<uuid>"，旧备份无此字段）
        var emotion: String?
        var review: String?
        var flowType: String?            // FR-31 资金流类型（nil = 旧备份，回落消费）
        var refId: String?               // FR-30 外部账单交易单号
        var createdAt: Date
    }

    struct SettingsBackup: Codable {
        var hasCompletedOnboarding: Bool
        var cooldownEnabled: Bool
        var cooldownHours: Int
        var currentCurrency: String
        var customRates: [String: Double]
    }

    enum BackupError: LocalizedError {
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .malformed(let reason): return reason
            }
        }
    }

    // MARK: - JSON 编解码器（ISO8601 含毫秒，跨设备可读）

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(isoFormatter.string(from: date))
        }
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = isoFormatter.date(from: s) { return date }
            // 兼容无毫秒格式
            if let date = isoFormatterNoFraction.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "无法解析日期: \(s)")
        }
        return d
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction = ISO8601DateFormatter()

    // MARK: - CSV 导出

    /// CSV 导出（FR-10）— UTF-8 with BOM（Excel/Numbers 中文不乱码），PRD 固定表头
    /// 设置页导出与电脑端工作台共用
    static func makeCSV(expenses: [Expense]) -> Data {
        var csv = "日期,金额,性质,分类,情绪,备注,回顾结果\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        func escape(_ s: String) -> String {
            s.contains(",") || s.contains("\"") || s.contains("\n")
                ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
                : s
        }

        for e in expenses.sorted(by: { $0.date > $1.date }) {
            let nature: String
            switch e.nature {
            case .chosen: nature = "主动选择"
            case .impulse: nature = "冲动"
            case .necessity: nature = "必须花"
            case nil: nature = ""
            }
            let emotion = e.emotion?.localizedName ?? ""
            let review: String
            switch e.review {
            case .affirm: review = "会再做同样选择"
            case .reconsider: review = "会重新考虑"
            case nil: review = ""
            }
            csv += [
                formatter.string(from: e.date),
                String(format: "%.2f", e.amount),
                nature,
                e.categoryDisplayName,
                emotion,
                escape(e.note),
                review,
            ].joined(separator: ",") + "\n"
        }

        let bomData = Data([0xEF, 0xBB, 0xBF])
        var data = bomData
        data.append(csv.data(using: .utf8) ?? Data())
        return data
    }

    // MARK: - JSON 备份导出

    static func makeBackupJSON(
        expenses: [Expense],
        budget: BudgetModel?,
        settings: AppSettings?
    ) throws -> Data {
        let file = BackupFile(
            schemaVersion: schemaVersion,
            exportDate: .now,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            expenses: expenses.map(Self.expenseBackup),
            budgetMonthlyLimit: budget?.monthlyLimit,
            settings: settings.map {
                SettingsBackup(
                    hasCompletedOnboarding: $0.hasCompletedOnboarding,
                    cooldownEnabled: $0.cooldownEnabled,
                    cooldownHours: $0.cooldownHours,
                    currentCurrency: $0.currentCurrency,
                    customRates: $0.customRates
                )
            }
        )
        return try encoder.encode(file)
    }

    /// 解析并校验 JSON 备份
    static func parseBackup(_ data: Data) throws -> BackupFile {
        do {
            return try decoder.decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.malformed(String(localized: "This file is not a valid Stoic Spend backup."))
        }
    }

    /// 恢复备份 — 覆盖当前全部支出（恢复前调用方必须已做快照）
    @discardableResult
    static func restore(_ backup: BackupFile, in context: ModelContext) throws -> Int {
        try deleteAllExpenses(in: context)

        var restored = 0
        for item in backup.expenses {
            let e = Expense(
                amount: item.amount,
                date: item.date,
                note: item.note,
                nature: item.nature.flatMap(ExpenseNature.init(rawValue:)),
                values: item.values.compactMap(ValueTag.init(rawValue:)),
                emotionalTrigger: item.emotionalTrigger,
                category: ExpenseCategory(rawValue: item.category) ?? .other,
                emotion: item.emotion.flatMap(ExpenseEmotion.init(rawValue:))
            )
            e.id = item.id
            e.review = item.review.flatMap(ReviewResult.init(rawValue:))
            e.createdAt = item.createdAt
            context.insert(e)
            restored += 1
        }

        if let limit = backup.budgetMonthlyLimit {
            let descriptor = FetchDescriptor<BudgetModel>()
            if let budget = try? context.fetch(descriptor).first {
                budget.monthlyLimit = limit
            } else {
                context.insert(BudgetModel(monthlyLimit: limit))
            }
        }

        try context.save()
        return restored
    }

    // MARK: - 快照与撤销（导入前自动备份当前数据）

    /// 快照当前全部支出（存 UserDefaults，体量小可靠）
    static func makeSnapshot(expenses: [Expense]) {
        struct Snapshot: Codable {
            var expenses: [ExpenseBackup]
        }
        let snap = Snapshot(expenses: expenses.map(Self.expenseBackup))
        if let data = try? encoder.encode(snap) {
            UserDefaults.standard.set(data, forKey: snapshotKey)
        }
    }

    /// 是否存在可撤销的快照
    static var hasSnapshot: Bool {
        UserDefaults.standard.data(forKey: snapshotKey) != nil
    }

    /// 撤销最近一次导入 — 删除当前全部支出，恢复快照
    @discardableResult
    static func undoImport(in context: ModelContext) throws -> Int {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else { return 0 }
        struct Snapshot: Codable { var expenses: [ExpenseBackup] }
        guard let snap = try? decoder.decode(Snapshot.self, from: data) else {
            throw BackupError.malformed(String(localized: "Snapshot is damaged and cannot be restored."))
        }
        try deleteAllExpenses(in: context)
        for item in snap.expenses {
            context.insert(expense(from: item))
        }
        try context.save()
        UserDefaults.standard.removeObject(forKey: snapshotKey)
        return snap.expenses.count
    }

    static func clearSnapshot() {
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    // MARK: - CSV 导入（仅追加）

    struct CSVRecord: Identifiable {
        let id = UUID()
        var date: Date
        var amount: Double
        var note: String
        var category: ExpenseCategory?
        var flowType: FlowType = .expense   // FR-31「收/支」列映射
        var refId: String?                  // FR-30 交易单号（去重）
        var merchant: String?               // FR-32 交易对方（纠错规则关键词来源）
        var ruleCategoryKey: String?        // FR-32 命中纠错规则的自定义分类 key
        var ruleApplied: Bool = false       // FR-32 已按用户习惯归类（预览页标记）
    }

    struct CSVImportResult {
        var records: [CSVRecord] = []
        var skippedRows: Int = 0            // 无法解析（缺金额/日期）
        var sampleNotes: [String] = []
        // FR-30 细分口径（预览页展示）
        var totalRows: Int = 0
        var incomeCount: Int = 0
        var refundCount: Int = 0
        var transferCount: Int = 0
        var duplicateRows: Int = 0
        var headerRow: Int? = nil           // 探测到的表头行号（1-based，调试与 UI 展示）
        var recordsRuleHits: Int = 0        // FR-32 按你的习惯归类的条数
    }

    /// 表头同义词映射（FR-30 兼容微信/支付宝账单）— key 经 normalizeHeader 归一（去空格/引号，全角括号转半角，小写）
    private static let headerMap: [String: String] = [
        // 日期
        "日期": "date", "时间": "date", "交易时间": "date", "交易日期": "date", "记账时间": "date",
        "交易创建时间": "date", "付款时间": "date",
        "date": "date", "time": "date",
        // 金额
        "金额": "amount", "支出金额": "amount", "收入金额": "amount",
        "金额(元)": "amount", "金额(￥)": "amount", "amount": "amount",
        // 备注/商品（商品优先；交易对方为独立兜底列）
        "商品": "note", "商品说明": "note", "商品名称": "note",
        "备注": "note", "笔记": "note", "事项": "note", "描述": "note",
        "note": "note", "description": "note", "交易对方": "cp",
        // 分类
        "分类": "category", "类别": "category", "一级分类": "category", "category": "category",
        // 类型（收/支）
        "类型": "type", "收支": "type", "收/支": "type", "type": "type",
        // FR-30 状态与单号
        "当前状态": "status", "交易状态": "status", "status": "status",
        "交易单号": "refid", "交易号": "refid", "交易流水号": "refid",
        "订单号": "refid", "商家订单号": "refid", "refid": "refid",
    ]

    /// 表头归一化：去空白/引号，全角括号转半角，小写
    private static func normalizeHeader(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{3000}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .lowercased()
    }

    /// 「收/支」列 → 资金流类型（FR-31 口径：收入落库不统计，不计收支视作转账）
    private static func flowType(fromTypeCell raw: String) -> FlowType {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.contains("收入") || s.lowercased() == "income" { return .income }
        if s.contains("不计收支") || s == "/" || s.isEmpty || s.lowercased() == "other" { return .transfer }
        return .expense
    }

    /// 支持的日期格式（按顺序尝试）
    private static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        "yyyy/M/d HH:mm:ss", "yyyy/M/d HH:mm", "yyyy/M/d",
        "yyyy年M月d日 HH:mm", "yyyy年M月d日",
        "MM-dd HH:mm", "M/d HH:mm",
    ]

    /// 解析 CSV（FR-30）— 前 40 行探测表头；金额清洗；退款不丢弃；交易单号/日期金额备注去重
    /// - Parameter existing: 当前已有账目（用于跨文件去重；快记页/工作台不传则跳过跨文件判重）
    static func parseCSV(_ data: Data, existing: [Expense] = []) -> CSVImportResult {
        var result = CSVImportResult()

        // 去 BOM；优先 UTF-8，回退 GB18030（支付宝导出常见 GBK 编码）
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb18030) ?? ""
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        guard let rows = splitCSVRows(text) else { return result }

        // FR-30 前 40 行内探测表头（微信账单前有 4~16 行说明文字）：映射后同时含日期与金额即认定
        var headerIdx: Int? = nil
        var headers: [String] = []
        for (i, row) in rows.prefix(40).enumerated() {
            let mapped = row.map { headerMap[normalizeHeader($0)] ?? "" }
            if mapped.contains("date"), mapped.contains("amount") {
                headerIdx = i
                headers = mapped
                break
            }
        }
        guard let headerIdx, rows.count > headerIdx + 1 else { return result }
        result.headerRow = headerIdx + 1

        let dateIdx = headers.firstIndex(of: "date")
        let amountIdx = headers.firstIndex(of: "amount")
        guard let dateIdx, let amountIdx else { return result }
        let noteIdx = headers.firstIndex(of: "note")
        let cpIdx = headers.firstIndex(of: "cp")           // 交易对方（备注为空时兜底）
        let categoryIdx = headers.firstIndex(of: "category")
        // 「收/支」比「类型」优先（支付宝两者都有，类型列是 交易收款/交易付款）
        let typeIdx = headers.lastIndex(of: "type")
        let statusIdx = headers.firstIndex(of: "status")
        let refIdIdx = headers.firstIndex(of: "refid")

        // FR-30 去重基准：历史交易单号 + 历史「日期+金额+备注」
        var knownRefIds = Set(existing.compactMap { $0.refId }.filter { !$0.isEmpty })
        var knownKeys = Set(existing.map { dedupKey(date: $0.date, amount: $0.amount, note: $0.note) })

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for row in rows[(headerIdx + 1)...] {
            let trimmed = row.map { $0.trimmingCharacters(in: .whitespaces) }
            guard trimmed.contains(where: { !$0.isEmpty }) else { continue }   // 空行不计
            result.totalRows += 1

            guard row.count > max(dateIdx, amountIdx),
                  let amount = parseAmount(row[amountIdx]),
                  let date = parseDate(row[dateIdx], formatter: formatter) else {
                result.skippedRows += 1
                continue
            }

            var note = noteIdx.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : "" } ?? ""
            if note.isEmpty, let cpIdx, cpIdx < row.count {
                note = row[cpIdx].trimmingCharacters(in: .whitespaces)   // 无商品列时用交易对方
            }
            let merchant = cpIdx.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : "" } ?? ""
            var category = categoryIdx.flatMap { $0 < row.count ? mapCategory(row[$0]) : nil }

            // FR-32 分类纠错记忆：用户规则优先于自动映射
            var ruleCategoryKey: String?
            var ruleApplied = false
            let keywordSource = merchant.isEmpty ? note : merchant
            if let hit = CategoryRuleStore.match(note: keywordSource) {
                if let raw = ExpenseCategory(rawValue: hit.categoryKey) {
                    ruleApplied = true
                    result.recordsRuleHits += 1
                    category = raw
                } else if CategoryStore.uuid(fromKey: hit.categoryKey) != nil {
                    ruleCategoryKey = hit.categoryKey
                    ruleApplied = true
                    category = nil
                    result.recordsRuleHits += 1
                }
            }
            let refId = refIdIdx.flatMap { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespaces) : "" } ?? ""
            var flow: FlowType = typeIdx.flatMap { $0 < row.count ? flowType(fromTypeCell: row[$0]) : nil } ?? .expense
            if let statusIdx, statusIdx < row.count, row[statusIdx].contains("退款") {
                flow = .refund   // 已退款/已全额退款 → 负冲抵，不静默丢弃
            }

            // 去重：交易单号优先，无单号按「日期+金额+备注」
            let key = dedupKey(date: date, amount: amount, note: note)
            if !refId.isEmpty {
                if knownRefIds.contains(refId) || knownKeys.contains(key) {
                    result.duplicateRows += 1
                    continue
                }
                knownRefIds.insert(refId)
            } else if knownKeys.contains(key) {
                result.duplicateRows += 1
                continue
            }
            knownKeys.insert(key)

            switch flow {
            case .income: result.incomeCount += 1
            case .refund: result.refundCount += 1
            case .transfer: result.transferCount += 1
            case .expense: break
            }

            result.records.append(CSVRecord(
                date: date, amount: amount, note: note, category: category,
                flowType: flow, refId: refId.isEmpty ? nil : refId,
                merchant: merchant.isEmpty ? nil : merchant,
                ruleCategoryKey: ruleCategoryKey, ruleApplied: ruleApplied
            ))
        }

        result.sampleNotes = Array(result.records.prefix(3).map { record in
            let nf = DateFormatter()
            nf.dateFormat = "MM-dd"
            let tag = record.flowType == .expense ? "" : "[\(record.flowType.localizedName)] "
            return "\(nf.string(from: record.date)) \(String(format: "%.2f", record.amount)) \(tag)\(record.note)"
        })
        return result
    }

    /// 去重 key：「日期+金额+备注」（无交易单号时的判重依据）
    private static func dedupKey(date: Date, amount: Double, note: String) -> String {
        "\(Int(date.timeIntervalSince1970))|\(String(format: "%.2f", amount))|\(note)"
    }

    /// 将 CSV 记录追加写入（调用方需先 makeSnapshot）
    @discardableResult
    static func insertCSVRecords(_ records: [CSVRecord], in context: ModelContext) throws -> Int {
        for r in records {
            let e = Expense(amount: r.amount, date: r.date, note: r.note, category: r.category ?? .other)
            e.flowType = r.flowType
            e.refId = r.refId
            // FR-32 命中/批量指定的自定义分类
            if let key = r.ruleCategoryKey, let id = CategoryStore.uuid(fromKey: key) {
                e.customCategoryID = id
            }
            context.insert(e)
        }
        try context.save()
        return records.count
    }

    // MARK: - 私有工具

    /// 仅供单测（FR-31 备份字段往返）
    static func expenseBackupForTesting(_ e: Expense) -> ExpenseBackup { expenseBackup(e) }

    private static func expenseBackup(_ e: Expense) -> ExpenseBackup {        ExpenseBackup(
            id: e.id, amount: e.amount, date: e.date, note: e.note,
            nature: e.nature?.rawValue, values: e.values.map(\.rawValue),
            emotionalTrigger: e.emotionalTrigger, category: e.category.rawValue,
            customCategoryKey: e.categoryGroupKey.hasPrefix("custom:") ? e.categoryGroupKey : nil,
            emotion: e.emotion?.rawValue, review: e.review?.rawValue,
            flowType: e.flowType == .expense ? nil : e.flowType.rawValue,
            refId: e.refId, createdAt: e.createdAt
        )
    }

    private static func expense(from item: ExpenseBackup) -> Expense {
        let e = Expense(
            amount: item.amount, date: item.date, note: item.note,
            nature: item.nature.flatMap(ExpenseNature.init(rawValue:)),
            values: item.values.compactMap(ValueTag.init(rawValue:)),
            emotionalTrigger: item.emotionalTrigger,
            category: ExpenseCategory(rawValue: item.category) ?? .other,
            emotion: item.emotion.flatMap(ExpenseEmotion.init(rawValue:))
        )
        e.id = item.id
        e.customCategoryID = item.customCategoryKey.flatMap(CategoryStore.uuid(fromKey:))
        e.review = item.review.flatMap(ReviewResult.init(rawValue:))
        e.flowType = item.flowType.flatMap(FlowType.init(rawValue:)) ?? .expense
        e.refId = item.refId
        e.createdAt = item.createdAt
        return e
    }

    private static func deleteAllExpenses(in context: ModelContext) throws {
        try context.delete(model: Expense.self)
    }

    /// 简易 CSV 行解析（支持引号包裹的逗号/换行）
    private static func splitCSVRows(_ text: String) -> [[String]]? {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()

        while let ch = iterator.next() {
            if inQuotes {
                if ch == "\"" {
                    // 双引号转义
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else {
                            inQuotes = false
                            if next == "," { row.append(field); field = "" }
                            else if next == "\n" { row.append(field); rows.append(row); row = []; field = "" }
                            else if next != "\r" { field.append(next) }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\r": break
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(ch)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.isEmpty ? nil : rows
    }

    private static func parseAmount(_ s: String) -> Double? {
        var cleaned = s
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
        // FR-30 正负号清洗（含会计式尾随负号），金额取绝对值；收/支由类型列决定
        if cleaned.hasPrefix("-") || cleaned.hasSuffix("-") {
            cleaned = cleaned.replacingOccurrences(of: "-", with: "")
        }
        cleaned = cleaned.replacingOccurrences(of: "+", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    private static func parseDate(_ s: String, formatter: DateFormatter) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        for fmt in dateFormats {
            formatter.dateFormat = fmt
            if let d = formatter.date(from: trimmed) { return d }
        }
        // 纯时间戳（秒）
        if let ts = TimeInterval(trimmed), ts > 1_000_000_000, ts < 4_000_000_000 {
            return Date(timeIntervalSince1970: ts)
        }
        return nil
    }

    /// 中文分类名 → 九分法（宽松匹配）
    private static func mapCategory(_ raw: String) -> ExpenseCategory? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let table: [(ExpenseCategory, [String])] = [
            (.food, ["餐", "食", "饮", "早", "午", "晚", "水果", "外卖", "超市", "食品", "酒", "茶", "宵夜", "零食"]),
            (.beauty, ["美", "妆", "护", "理发", "衣", "鞋", "包", "饰"]),
            (.transport, ["交通", "打", "公交", "地铁", "出租", "网约", "油", "停车", "火车", "机票"]),
            (.family, ["亲", "朋", "宠物", "礼", "娃", "孩", "育儿", "猫", "狗"]),
            (.housing, ["住", "房", "租", "水", "电", "燃气", "物业", "网费"]),
            (.gadget, ["电子", "数码", "手机", "电脑", "软件", "会员", "订阅", "游戏"]),
            (.travel, ["旅", "游", "酒店", "民宿", "景点", "度假"]),
            (.learning, ["学", "书", "课", "教育", "培训", "知识"]),
        ]
        for (cat, keywords) in table {
            if keywords.contains(where: { s.contains($0) }) { return cat }
        }
        return nil
    }
}
