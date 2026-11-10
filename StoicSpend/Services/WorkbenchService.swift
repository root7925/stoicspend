import Foundation
import SwiftData
import Network
import UIKit
import os.log

/// FR-11 电脑端工作台 — 局域网网页版
/// 形态：内嵌轻量 HTTP 服务 + Bonjour 广播；默认关；开启后显示地址与 4 位配对码
/// 安全：仅局域网；配对码换会话 token；10 分钟无活跃连接自动关闭；锁屏/退后台立即停止
@MainActor
final class WorkbenchService: ObservableObject {
    static let shared = WorkbenchService()
    private init() {}

    static let inactivityTimeout: TimeInterval = 600  // 10 分钟

    @Published private(set) var isRunning = false
    @Published private(set) var serverURL: String?     // http://192.168.x.x:port
    @Published private(set) var pairingCode: String?   // 4 位配对码

    private let server = WorkbenchHTTPServer()
    private let core = WorkbenchCore()
    private var inactivityTimer: Timer?
    private let logger = Logger(subsystem: "com.zhenglin.stoicspend", category: "Workbench")

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        core.resetSession()
        let code = core.generatePairingCode()
        pairingCode = code

        server.handler = { [weak self] request in
            guard let self else { return HTTPResponse.error(503, "Unavailable") }
            let response = self.core.route(request)
            // 有活跃请求 → 重置 10 分钟无操作计时
            DispatchQueue.main.async { self.touchActivity() }
            return response
        }
        server.start(preferredPort: 8787) { [weak self] port in
            DispatchQueue.main.async {
                guard let ip = Self.lanIPAddress() else { return }
                self?.serverURL = "http://\(ip):\(port)"
                self?.isRunning = true
            }
        }
        logger.info("工作台已启动，配对码已生成")
    }

    func stop() {
        server.stop()
        isRunning = false
        serverURL = nil
        pairingCode = nil
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        core.resetSession()
        logger.info("工作台已停止")
    }

    /// 重置 10 分钟无活跃连接计时
    private func touchActivity() {
        guard isRunning else { return }
        inactivityTimer?.invalidate()
        inactivityTimer = Timer.scheduledTimer(withTimeInterval: Self.inactivityTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.stop() }
        }
    }

    /// 取局域网 IPv4（优先 en0）
    static func lanIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, ip: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let interface = p.pointee
            if interface.ifa_addr?.pointee.sa_family == UInt8(AF_INET) {
                var addr = interface.ifa_addr!.pointee
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(&addr, socklen_t(interface.ifa_addr!.pointee.sa_len),
                               &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: hostname)
                    let name = String(cString: interface.ifa_name)
                    // 仅私网地址
                    if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                        candidates.append((name, ip))
                    }
                }
            }
            ptr = interface.ifa_next
        }
        address = candidates.first(where: { $0.name.hasPrefix("en") })?.ip ?? candidates.first?.ip
        return address
    }
}

// MARK: - 核心（非 MainActor，线程安全）

/// 路由与数据访问 — HTTP 队列调用，SwiftData 操作在专用串行队列
final class WorkbenchCore {
    private let container: ModelContainer = ModelContainerSetup.shared
    private let dbQueue = DispatchQueue(label: "com.zhenglin.stoicspend.workbench.db")
    private let lock = NSLock()
    private var tokens: Set<String> = []
    private var pairingCode: String = ""
    private var pendingImports: [String: PendingImport] = [:]
    private let logger = Logger(subsystem: "com.zhenglin.stoicspend", category: "Workbench")

    struct PendingImport {
        enum Kind { case csv, json }
        let kind: Kind
        let data: Data
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterNoFraction = ISO8601DateFormatter()

    private static func encodeDate(_ d: Date) -> String { isoFormatter.string(from: d) }
    private static func decodeDate(_ s: String) -> Date? {
        isoFormatter.date(from: s) ?? isoFormatterNoFraction.date(from: s)
    }

    // MARK: 会话

    func resetSession() {
        lock.lock(); defer { lock.unlock() }
        tokens.removeAll()
        pairingCode = ""
        pendingImports.removeAll()
    }

    func generatePairingCode() -> String {
        lock.lock(); defer { lock.unlock() }
        let code = String(format: "%04d", Int.random(in: 0...9999))
        pairingCode = code
        return code
    }

    // MARK: API 数据结构

    struct PairRequest: Codable { let code: String }
    struct PairResponse: Codable { let token: String }

    struct ExpenseJSON: Codable {
        let id: String
        let date: String
        let amount: Double
        let note: String
        let nature: String?
        let category: String
    }

    struct SummaryResponse: Codable {
        let month: String
        let total: Double
        let controllable: Double
        let controllableRatio: Double
        let count: Int
        let categories: [CategoryAmount]
    }

    struct CategoryAmount: Codable {
        let key: String
        let name: String
        let amount: Double
    }

    struct MetaResponse: Codable {
        let categories: [KeyValue]
        let natures: [KeyValue]
    }

    struct KeyValue: Codable {
        let key: String
        let name: String
    }

    struct ExpenseListResponse: Codable {
        let month: String
        let expenses: [ExpenseJSON]
    }

    struct EditRequest: Codable {
        let amount: Double?
        let note: String?
        let nature: String?   // "chosen" / "impulse" / "necessity"
        let category: String? // "cat.food" 等
    }

    struct ImportPreviewResponse: Codable {
        let importId: String
        let kind: String
        let count: Int
        let skipped: Int
        let samples: [String]
        let mode: String     // append（CSV） / replace（JSON）
    }

    struct OkResponse: Codable {
        let ok: Bool
        let message: String
    }

    // MARK: 路由

    func route(_ req: HTTPRequest) -> HTTPResponse {
        // 配对不需要 token
        if req.path == "/api/pair" && req.method == "POST" {
            return handlePair(req)
        }
        if req.path == "/" && req.method == "GET" {
            return HTTPResponse.html(WorkbenchWebUI.html)
        }

        // 其余全部要求有效 token
        guard isValidToken(req.token) else {
            return HTTPResponse.error(401, "请先输入配对码")
        }

        switch (req.method, req.path) {
        case ("GET", "/api/meta"):
            return handleMeta()
        case ("GET", "/api/summary"):
            return handleSummary(req)
        case ("GET", "/api/expenses"):
            return handleExpenseList(req)
        case ("PUT", let p) where p.hasPrefix("/api/expenses/"):
            return handleEdit(req, id: String(p.dropFirst("/api/expenses/".count)))
        case ("GET", "/api/export/csv"):
            return dbQueue.sync { exportCSV() }
        case ("GET", "/api/export/json"):
            return dbQueue.sync { exportJSON() }
        case ("POST", "/api/import"):
            return handleImport(req)
        case ("POST", "/api/import/confirm"):
            return handleImportConfirm(req)
        case ("POST", "/api/import/undo"):
            return dbQueue.sync { undoImport() }
        default:
            return HTTPResponse.error(404, "Not Found")
        }
    }

    private func isValidToken(_ token: String?) -> Bool {
        guard let token else { return false }
        lock.lock(); defer { lock.unlock() }
        return tokens.contains(token)
    }

    private func decode<T: Decodable>(_ type: T.Type, from req: HTTPRequest) -> T? {
        try? JSONDecoder().decode(T.self, from: req.body)
    }

    private func jsonBody<T: Encodable>(_ object: T, status: Int = 200) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(object) else {
            return HTTPResponse.error(500, "Encode failed")
        }
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }

    // MARK: 各路由

    private func handlePair(_ req: HTTPRequest) -> HTTPResponse {
        guard let body = decode(PairRequest.self, from: req) else {
            return HTTPResponse.error(400, "Invalid request")
        }
        lock.lock()
        defer { lock.unlock() }
        guard !pairingCode.isEmpty, body.code == pairingCode else {
            return HTTPResponse.error(401, "配对码不正确")
        }
        let token = UUID().uuidString
        tokens.insert(token)
        return jsonBody(PairResponse(token: token))
    }

    private func handleMeta() -> HTTPResponse {
        let categories = ExpenseCategory.allCases.map {
            KeyValue(key: $0.rawValue, name: $0.localizedName)
        }
        let natures: [KeyValue] = [
            // 与 App 内/CSV 导出一致的中文名称
            KeyValue(key: ExpenseNature.chosen.rawValue, name: "主动选择"),
            KeyValue(key: ExpenseNature.impulse.rawValue, name: "冲动"),
            KeyValue(key: ExpenseNature.necessity.rawValue, name: "必须花"),
        ]
        return jsonBody(MetaResponse(categories: categories, natures: natures))
    }

    /// month=YYYY-MM，缺省当前月
    private func monthInterval(_ month: String?) -> (start: Date, end: Date, label: String)? {
        let calendar = Calendar.current
        let label: String
        let start: Date
        if let month, let d = Self.monthFormatter.date(from: month) {
            start = d
            label = month
        } else {
            start = calendar.dateInterval(of: .month, for: .now)!.start
            label = Self.monthFormatter.string(from: start)
        }
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return (start, end, label)
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func handleSummary(_ req: HTTPRequest) -> HTTPResponse {
        guard let interval = monthInterval(req.query["month"]) else {
            return HTTPResponse.error(400, "Invalid month")
        }
        return dbQueue.sync {
            let context = ModelContext(container)
            let start = interval.start
            let end = interval.end
            let descriptor = FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date >= start && $0.date < end }
            )
            let expenses = (try? context.fetch(descriptor)) ?? []
            let total = expenses.reduce(0) { $0 + $1.amount }
            let controllable = expenses.filter { $0.isControllable }.reduce(0) { $0 + $1.amount }
            let categories = ExpenseCategory.allCases.map { cat -> CategoryAmount in
                CategoryAmount(
                    key: cat.rawValue,
                    name: cat.localizedName,
                    amount: expenses.filter { $0.category == cat }.reduce(0) { $0 + $1.amount }
                )
            }
            return jsonBody(SummaryResponse(
                month: interval.label,
                total: total,
                controllable: controllable,
                controllableRatio: total > 0 ? controllable / total : 0,
                count: expenses.count,
                categories: categories
            ))
        }
    }

    private func handleExpenseList(_ req: HTTPRequest) -> HTTPResponse {
        guard let interval = monthInterval(req.query["month"]) else {
            return HTTPResponse.error(400, "Invalid month")
        }
        return dbQueue.sync {
            let context = ModelContext(container)
            let start = interval.start
            let end = interval.end
            let descriptor = FetchDescriptor<Expense>(
                predicate: #Predicate { $0.date >= start && $0.date < end },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let expenses = (try? context.fetch(descriptor)) ?? []
            return jsonBody(ExpenseListResponse(
                month: interval.label,
                expenses: expenses.map(Self.toJSON)
            ))
        }
    }

    private static func toJSON(_ e: Expense) -> ExpenseJSON {
        ExpenseJSON(
            id: e.id.uuidString,
            date: encodeDate(e.date),
            amount: e.amount,
            note: e.note,
            nature: e.nature?.rawValue,
            category: e.category.rawValue
        )
    }

    /// 明细编辑（金额/性质/分类/备注）— 后写优先
    private func handleEdit(_ req: HTTPRequest, id: String) -> HTTPResponse {
        guard let uuid = UUID(uuidString: id), let body = decode(EditRequest.self, from: req) else {
            return HTTPResponse.error(400, "Invalid request")
        }
        return dbQueue.sync {
            let context = ModelContext(container)
            let uuid = uuid
            let descriptor = FetchDescriptor<Expense>(predicate: #Predicate { $0.id == uuid })
            guard let expense = try? context.fetch(descriptor).first else {
                return HTTPResponse.error(404, "记录不存在")
            }
            if let amount = body.amount, amount >= 0 { expense.amount = amount }
            if let note = body.note { expense.note = note }
            if let nature = body.nature { expense.nature = ExpenseNature(rawValue: nature) }
            if let category = body.category, let cat = ExpenseCategory(rawValue: category) { expense.category = cat }
            do {
                try context.save()
            } catch {
                logger.error("工作台编辑保存失败: \(error.localizedDescription)")
                return HTTPResponse.error(500, "保存失败")
            }
            return jsonBody(OkResponse(ok: true, message: "已保存"))
        }
    }

    private func exportCSV() -> HTTPResponse {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let expenses = (try? context.fetch(descriptor)) ?? []
        return HTTPResponse.data(
            BackupService.makeCSV(expenses: expenses),
            contentType: "text/csv; charset=utf-8",
            filename: "stoicspend_export.csv"
        )
    }

    private func exportJSON() -> HTTPResponse {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        let expenses = (try? context.fetch(descriptor)) ?? []
        let budgetDescriptor = FetchDescriptor<BudgetModel>()
        let budget = try? context.fetch(budgetDescriptor).first
        let settingsDescriptor = FetchDescriptor<AppSettings>()
        let settings = try? context.fetch(settingsDescriptor).first
        guard let data = try? BackupService.makeBackupJSON(expenses: expenses, budget: budget, settings: settings) else {
            return HTTPResponse.error(500, "导出失败")
        }
        return HTTPResponse.data(data, contentType: "application/json; charset=utf-8", filename: BackupService.backupFilename)
    }

    /// 上传导入 — 第一步：解析并返回预览（复用 FR-10 管线）
    private func handleImport(_ req: HTTPRequest) -> HTTPResponse {
        guard let payload = decode(ImportPayload.self, from: req), let data = Data(base64Encoded: payload.data) else {
            return HTTPResponse.error(400, "Invalid request")
        }
        let importId = UUID().uuidString

        if payload.kind == "json" {
            guard let backup = try? BackupService.parseBackup(data) else {
                return HTTPResponse.error(400, String(localized: "This file is not a valid Stoic Spend backup."))
            }
            lock.lock()
            pendingImports[importId] = PendingImport(kind: .json, data: data)
            lock.unlock()
            return jsonBody(ImportPreviewResponse(
                importId: importId, kind: "json",
                count: backup.expenses.count, skipped: 0, samples: [],
                mode: "replace"
            ))
        } else {
            let result = BackupService.parseCSV(data)
            guard !result.records.isEmpty else {
                return HTTPResponse.error(400, String(localized: "No importable records found. Check the file header and format."))
            }
            lock.lock()
            pendingImports[importId] = PendingImport(kind: .csv, data: data)
            lock.unlock()
            return jsonBody(ImportPreviewResponse(
                importId: importId, kind: "csv",
                count: result.records.count, skipped: result.skippedRows,
                samples: result.sampleNotes, mode: "append"
            ))
        }
    }

    struct ImportPayload: Codable {
        let kind: String    // "csv" / "json"
        let data: String    // base64
    }

    struct ConfirmRequest: Codable {
        let importId: String
    }

    /// 第二步：确认提交（自动快照，可撤销）
    private func handleImportConfirm(_ req: HTTPRequest) -> HTTPResponse {
        guard let body = decode(ConfirmRequest.self, from: req) else {
            return HTTPResponse.error(400, "Invalid request")
        }
        lock.lock()
        let pending = pendingImports[body.importId]
        pendingImports.removeValue(forKey: body.importId)
        lock.unlock()

        guard let pending else { return HTTPResponse.error(404, "预览已过期，请重新上传") }
        return dbQueue.sync {
            let context = ModelContext(container)
            let allDescriptor = FetchDescriptor<Expense>()
            let current = (try? context.fetch(allDescriptor)) ?? []
            BackupService.makeSnapshot(expenses: current)
            do {
                let count: Int
                switch pending.kind {
                case .csv:
                    let result = BackupService.parseCSV(pending.data)
                    count = try BackupService.insertCSVRecords(result.records, in: context)
                case .json:
                    let backup = try BackupService.parseBackup(pending.data)
                    count = try BackupService.restore(backup, in: context)
                }
                return jsonBody(OkResponse(ok: true, message: "已导入 \(count) 条，可在网页或手机端撤销"))
            } catch {
                return HTTPResponse.error(500, String(format: String(localized: "Import failed: %@"), error.localizedDescription))
            }
        }
    }

    private func undoImport() -> HTTPResponse {
        let context = ModelContext(container)
        do {
            let count = try BackupService.undoImport(in: context)
            return jsonBody(OkResponse(ok: true, message: "已恢复快照（\(count) 条）"))
        } catch {
            return HTTPResponse.error(500, error.localizedDescription)
        }
    }
}
