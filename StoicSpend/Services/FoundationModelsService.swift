import Foundation
import CryptoKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Foundation Models 服务 — 端侧 AI 功能 + 优雅降级
/// 详见 Agent.md 第 7.3 节降级策略
///
/// Phase 5 升级要点：
/// 1. `@Generable` 结构化输出 — 周复盘追问 + 财务韧性建议均使用约束 schema
/// 2. 多轮对话 — 复用 LanguageModelSession.transcript，单次会话允许 1 轮追问回复
/// 3. AI 建议缓存 — 24h TTL，相同输入命中缓存不重复调用端侧模型
/// 4. 情境化 Prompt 工程 — SpendingPattern 分析冲动占比/主导价值观/情绪触发，注入 prompt
final class FoundationModelsService {
    static let shared = FoundationModelsService()

    /// 多轮对话最多追问轮数（设计文档"够用且克制"原则）
    private let maxFollowUpTurns: Int = 1

    /// 当前活跃的多轮对话 session（单用户单进程，一次只持有一个）
    #if canImport(FoundationModels)
    private var activeSession: LanguageModelSession?
    #endif
    private var activeTurnCount: Int = 0

    private let cache = AICache()

    private init() {}

    // MARK: - 可用性检测

    enum AIAvailability {
        case available
        case unavailable(reason: String)
    }

    var availability: AIAvailability {
        #if canImport(FoundationModels)
        let status = SystemLanguageModel.default.availability
        switch status {
        case .available:
            return .available
        case .unavailable(let reason):
            let message: String
            switch reason {
            case .deviceNotEligible:
                message = String(localized: "Device not eligible for Apple Intelligence")
            case .appleIntelligenceNotEnabled:
                message = String(localized: "Apple Intelligence not enabled")
            case .modelNotReady:
                message = String(localized: "Model not ready")
            @unknown default:
                message = String(localized: "AI features unavailable")
            }
            return .unavailable(reason: message)
        @unknown default:
            return .unavailable(reason: String(localized: "AI status unknown"))
        }
        #else
        return .unavailable(reason: String(localized: "System does not support Foundation Models"))
        #endif
    }

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    // MARK: - 周复盘 AI 追问（付费功能）

    /// 基于用户近期记录生成个性化追问（结构化输出 + 多轮会话起点 + 缓存）
    /// 降级模式: 返回固定模板
    func generateWeeklyFollowUp(
        recentExpenses: [Expense],
        lastReview: WeeklyReview?
    ) async -> WeeklyFollowUpResult {
        let cacheKey = "followup:" + Self.hashKey(
            expenses: recentExpenses,
            extra: lastReview?.virtueToPractice ?? ""
        )
        if let cached = cache.get(cacheKey),
           let data = cached.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(WeeklyFollowUpResult.self, from: data) {
            return decoded
        }

        guard isAvailable else {
            return Self.fallbackFollowUp
        }

        #if canImport(FoundationModels)
        // 开启新多轮会话
        let session = LanguageModelSession(model: SystemLanguageModel.default)
        activeSession = session
        activeTurnCount = 0

        do {
            let prompt = buildFollowUpPrompt(
                recentExpenses: recentExpenses,
                lastReview: lastReview
            )
            let response = try await session.respond(
                to: prompt,
                generating: WeeklyFollowUpContent.self
            )
            let content = response.content
            let result = WeeklyFollowUpResult(
                question: content.question,
                focusAngle: content.focusAngle
            )
            // 验证非空，空则降级
            guard !result.question.isEmpty else {
                return Self.fallbackFollowUp
            }
            cache.set(cacheKey, value: result)
            return result
        } catch {
            activeSession = nil
            return Self.fallbackFollowUp
        }
        #else
        return Self.fallbackFollowUp
        #endif
    }

    /// 多轮对话：用户回复 → AI 继续追问
    /// 设计上限制为单轮追问（maxFollowUpTurns），保持"够用且克制"
    /// 返回 nil 表示无法继续（已用满次数/无活跃会话/模型不可用/生成失败）
    func continueFollowUpConversation(userReply: String) async -> String? {
        let trimmed = userReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, activeTurnCount < maxFollowUpTurns else {
            return nil
        }
        guard isAvailable else {
            return String(localized: "ai.fallback.followupReply")
        }

        #if canImport(FoundationModels)
        guard let session = activeSession else { return nil }
        do {
            let response = try await session.respond(to: trimmed)
            activeTurnCount += 1
            if activeTurnCount >= maxFollowUpTurns {
                // 用满次数，自动结束会话释放资源
                activeSession = nil
            }
            return response.content
        } catch {
            activeSession = nil
            return String(localized: "ai.fallback.followupReply")
        }
        #else
        return String(localized: "ai.fallback.followupReply")
        #endif
    }

    /// 显式结束多轮会话（页面关闭时调用）
    func endFollowUpConversation() {
        activeSession = nil
        activeTurnCount = 0
    }

    /// 多轮会话是否还能继续追问
    var canContinueFollowUp: Bool {
        activeTurnCount < maxFollowUpTurns && activeSession != nil && isAvailable
    }

    // MARK: - 财务韧性 AI 建议（付费功能）

    /// 根据用户的财务韧性模拟结果生成斯多葛式应对建议（结构化输出 + 缓存）
    func generateResilienceAdvice(
        savings: Double,
        monthlyIncome: Double,
        monthlyExpenses: Double,
        scenario: String
    ) async -> ResilienceAdviceResult {
        let cacheKey = "resilience:" + Self.hashKey(expenses: [], extra: """
        \(savings)|\(monthlyIncome)|\(monthlyExpenses)|\(scenario)
        """)
        if let cached = cache.get(cacheKey),
           let data = cached.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ResilienceAdviceResult.self, from: data) {
            return decoded
        }

        guard isAvailable else {
            return Self.fallbackResilienceAdvice
        }

        #if canImport(FoundationModels)
        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default)
            let prompt = buildResiliencePrompt(
                savings: savings,
                monthlyIncome: monthlyIncome,
                monthlyExpenses: monthlyExpenses,
                scenario: scenario
            )
            let response = try await session.respond(
                to: prompt,
                generating: ResilienceAdviceContent.self
            )
            let content = response.content
            let result = ResilienceAdviceResult(
                advice: content.advice,
                focusArea: content.focusArea
            )
            guard !result.advice.isEmpty else {
                return Self.fallbackResilienceAdvice
            }
            cache.set(cacheKey, value: result)
            return result
        } catch {
            return Self.fallbackResilienceAdvice
        }
        #else
        return Self.fallbackResilienceAdvice
        #endif
    }

    // MARK: - Private: Prompt 工程（情境化）

    /// 计算用户消费模式特征，注入 prompt 提升针对性
    private func buildFollowUpPrompt(
        recentExpenses: [Expense],
        lastReview: WeeklyReview?
    ) -> String {
        let pattern = SpendingPattern(analyzing: recentExpenses)
        let locale = Locale.current.identifier

        var prompt = """
        You are a Stoic financial reflection coach. Generate ONE personalized weekly follow-up question \
        in the user's preferred language (locale: \(locale)). If the locale is not English, respond in that language.

        Tone: warm, non-judgmental, grounded in Stoic philosophy (focus on what is controllable).
        Length: 1–2 sentences. End with a question.

        """

        prompt += "User's recent week (last 7 days) spending pattern:\n"
        prompt += "- Total expenses: \(pattern.expenseCount) entries, \(String(format: "%.2f", pattern.totalSpending))\n"
        if pattern.expenseCount > 0 {
            prompt += "- Impulse ratio: \(String(format: "%.0f%%", pattern.impulseRatio * 100))\n"
            if let dominant = pattern.dominantValue {
                prompt += "- Dominant value tag: \(dominant.localizedName) (\(dominant.rawValue))\n"
            }
            if let trigger = pattern.topTrigger, !trigger.isEmpty {
                prompt += "- Most frequent emotional trigger: \(trigger)\n"
            }
        } else {
            prompt += "- No expenses recorded this week\n"
        }

        if let last = lastReview, !last.virtueToPractice.isEmpty {
            prompt += "\nLast week's virtue to practice: \(last.virtueToPractice)\n"
            prompt += "Reference whether this week's pattern reflects that intention.\n"
        }

        prompt += """

        Output schema:
        - question: the personalized follow-up question (1–2 sentences)
        - focusAngle: a 2–4 word label of the reflection angle (e.g. "impulse patterns", "value alignment", "emotional triggers")
        """
        return prompt
    }

    private func buildResiliencePrompt(
        savings: Double,
        monthlyIncome: Double,
        monthlyExpenses: Double,
        scenario: String
    ) -> String {
        let locale = Locale.current.identifier
        let runwayMonths = monthlyExpenses > 0 ? savings / monthlyExpenses : 0

        return """
        You are a Stoic financial counselor. The user ran a resilience simulation. \
        Respond in the user's preferred language (locale: \(locale)). If not English, use that language.

        Situation:
        - Savings: \(String(format: "%.0f", savings))
        - Monthly income: \(String(format: "%.0f", monthlyIncome))
        - Monthly expenses: \(String(format: "%.0f", monthlyExpenses))
        - Runway if income stops: \(String(format: "%.1f", runwayMonths)) months
        - Scenario: \(scenario)

        Generate a Stoic-style counsel:
        - advice: 1–2 sentences, do not induce panic, focus on "what is controllable"
        - focusArea: a 2–4 word label of the focus (e.g. "controllables", "preparation", "acceptance")
        """
    }

    // MARK: - Private: 缓存键哈希

    private static func hashKey(expenses: [Expense], extra: String) -> String {
        var parts: [String] = []
        for e in expenses.prefix(20) {
            parts.append("\(e.id.uuidString)|\(e.amount)|\(e.nature?.rawValue ?? "")|\(e.emotionalTrigger ?? "")")
        }
        parts.append(extra)
        let combined = parts.joined(separator: "§")
        // SHA256 via CryptoKit
        let data = Data(combined.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 降级模板

    static let fallbackFollowUp = WeeklyFollowUpResult(
        question: String(localized: "ai.fallback.followup"),
        focusAngle: String(localized: "values")
    )

    static let fallbackResilienceAdvice = ResilienceAdviceResult(
        advice: String(localized: "ai.fallback.resilience"),
        focusArea: String(localized: "controllables")
    )
}

// MARK: - 公开结果类型（View 层使用，不直接 import FoundationModels）

struct WeeklyFollowUpResult: Codable, Sendable {
    let question: String
    let focusAngle: String
}

struct ResilienceAdviceResult: Codable, Sendable {
    let advice: String
    let focusArea: String
}

// MARK: - @Generable 结构化输出 schema（私有，仅 Service 内部使用）

#if canImport(FoundationModels)
@Generable(description: "A personalized Stoic weekly reflection follow-up question")
private struct WeeklyFollowUpContent {
    var question: String
    var focusAngle: String
}

@Generable(description: "A Stoic counsel for a financial resilience simulation")
private struct ResilienceAdviceContent {
    var advice: String
    var focusArea: String
}
#endif

// MARK: - 消费模式分析（情境化 Prompt 工程的输入）

private struct SpendingPattern {
    let expenseCount: Int
    let totalSpending: Double
    let impulseRatio: Double         // 冲动消费占比 0..1
    let dominantValue: ValueTag?
    let topTrigger: String?

    init(analyzing expenses: [Expense]) {
        self.expenseCount = expenses.count
        self.totalSpending = expenses.reduce(0) { $0 + $1.amount }

        guard !expenses.isEmpty else {
            self.impulseRatio = 0
            self.dominantValue = nil
            self.topTrigger = nil
            return
        }

        let impulseCount = expenses.filter { $0.nature == .impulse }.count
        self.impulseRatio = Double(impulseCount) / Double(expenses.count)

        // 主导价值观：统计 values 数组中出现频次最高的
        var valueCounts: [ValueTag: Int] = [:]
        for e in expenses {
            for v in e.values { valueCounts[v, default: 0] += 1 }
        }
        self.dominantValue = valueCounts.max(by: { $0.value < $1.value })?.key

        // 最频繁情绪触发点
        var triggerCounts: [String: Int] = [:]
        for e in expenses {
            if let t = e.emotionalTrigger, !t.isEmpty {
                triggerCounts[t, default: 0] += 1
            }
        }
        self.topTrigger = triggerCounts.max(by: { $0.value < $1.value })?.key
    }
}

// MARK: - AI 建议缓存（24h TTL，避免相同输入重复调用端侧模型）

private final class AICache {
    private struct Entry {
        let value: String
        let timestamp: Date
    }
    private var storage: [String: Entry] = [:]
    private let queue = DispatchQueue(label: "com.stoicspend.ai.cache", attributes: .concurrent)
    private let ttl: TimeInterval = 24 * 3600  // 24 小时

    func get(_ key: String) -> String? {
        queue.sync {
            guard let entry = storage[key] else { return nil }
            if Date().timeIntervalSince(entry.timestamp) > ttl {
                return nil  // 过期，让调用方重新生成
            }
            return entry.value
        }
    }

    func set<T: Encodable>(_ key: String, value: T) {
        guard let data = try? JSONEncoder().encode(value),
              let str = String(data: data, encoding: .utf8) else { return }
        queue.async(flags: .barrier) {
            self.storage[key] = Entry(value: str, timestamp: Date())
        }
    }
}


