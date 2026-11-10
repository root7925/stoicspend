import Foundation

extension Notification.Name {
    /// FR-25 — 分享扩展已解析截图，主 App 打开预填确认页
    static let captureOpenQuickAdd = Notification.Name("capture.openQuickAdd")
}

// MARK: - FR-25 待处理截图捕获（分享扩展 → 主 App，经 App Group 传递）

/// 截图解析结果。截图本身不留存，只保留提取出的金额/商户名。
struct PendingCapture: Codable, Identifiable, Equatable {
    let id: UUID
    /// 识别到的金额；nil = 识别失败，回落手动输入
    var amount: Double?
    /// 识别到的商户名（可选，落到备注）
    var merchant: String?
    let createdAt: Date
}

@MainActor
enum PendingCaptureStore {
    static let suiteName = "group.com.zhenglin.stoicspend"
    static let storageKey = "capture.pending"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// 读取并清空队列（一次一条，先进先出）
    static func load() -> PendingCapture? {
        guard let d = defaults else { return nil }
        var items: [PendingCapture] = []
        if let data = d.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PendingCapture].self, from: data) {
            items = decoded
        }
        d.removeObject(forKey: storageKey)
        return items.first
    }

    static func append(_ item: PendingCapture) {
        guard let d = defaults else { return }
        var items: [PendingCapture] = []
        if let data = d.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([PendingCapture].self, from: data) {
            items = decoded
        }
        items.append(item)
        if let data = try? JSONEncoder().encode(items) {
            d.set(data, forKey: storageKey)
        }
    }

    static func clear() {
        defaults?.removeObject(forKey: storageKey)
    }
}

// MARK: - FR-25 支付截图解析（纯规则，App 与分享扩展共用）

enum ScreenshotParser {
    /// 金额提示词优先：含「实付/合计/应付」的行 → 提取数字；其次 ¥ 前缀；最后取全文最后一条数字
    static func parseAmount(from lines: [String]) -> Double? {
        let keywords = ["实付", "合计", "应付", "付款", "金额", "total", "paid", "amount"]
        let numberPattern = "[0-9][0-9,]*(?:\\.[0-9]{1,2})?"

        for line in lines {
            let lower = line.lowercased()
            if keywords.contains(where: { lower.contains($0) }) {
                if let v = firstNumber(in: line, pattern: numberPattern) { return v }
            }
        }
        for line in lines {
            if line.contains("¥") || line.contains("￥") || line.contains("$") {
                if let v = firstNumber(in: line, pattern: numberPattern) { return v }
            }
        }
        for line in lines.reversed() {
            if let v = firstNumber(in: line, pattern: numberPattern) { return v }
        }
        return nil
    }

    /// 商户名猜测：第一条不含金额数字、且不是支付平台样板文案的文本行
    static func guessMerchant(from lines: [String]) -> String? {
        let boilerplate = ["支付", "微信", "支付宝", "账单", "详情", "收银", "钱包", "成功", "receipt", "payment", "paid"]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, trimmed.count <= 24 else { continue }
            if trimmed.contains(where: { $0.isNumber }) { continue }
            let lower = trimmed.lowercased()
            if boilerplate.contains(where: { lower.contains($0) }) { continue }
            return trimmed
        }
        return nil
    }

    private static func firstNumber(in line: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let matchRange = Range(match.range, in: line) else { return nil }
        let cleaned = String(line[matchRange]).replacingOccurrences(of: ",", with: "")
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}
