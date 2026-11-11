import Foundation
import SwiftData

/// App Store 截图支撑（仅 DEBUG 构建生效，发布包不含任何逻辑）：
/// 启动参数 APPSTORE_SHOT  → 跳过引导 + 灌入演示数据
/// 启动参数 -appstoreTab N → 直达指定 Tab（0 首页 / 1 帐本 / 2 奥卡姆 / 3 设置）
enum AppStoreShotSupport {
    static var isEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("APPSTORE_SHOT")
        #else
        false
        #endif
    }

    /// 解析 -appstoreTab N；无效返回 nil（默认首页）
    static var preferredTab: Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-appstoreTab"),
              idx + 1 < args.count,
              let tab = Int(args[idx + 1]), (0...3).contains(tab) else { return nil }
        return tab
        #else
        return nil
        #endif
    }

    /// -appstoreQuickAdd → 启动后直接弹出快记页
    static var wantsQuickAdd: Bool {
        #if DEBUG
        isEnabled && ProcessInfo.processInfo.arguments.contains("-appstoreQuickAdd")
        #else
        false
        #endif
    }

    /// 灌入一批贴近真实生活的演示账目（幂等：仅库为空时写入）
    @MainActor
    static func seedDemoDataIfNeeded(context: ModelContext) {
        #if DEBUG
        guard isEnabled else { return }
        var fetch = FetchDescriptor<Expense>()
        fetch.fetchLimit = 1
        if (try? context.fetch(fetch))?.isEmpty == false { return }

        let cal = Calendar.current
        let today = { (day: Int, hour: Int) -> Date in
            cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: .now))!
                .addingTimeInterval(TimeInterval(hour * 3600))
        }
        let demo: [(Double, Int, Int, String, ExpenseNature, ExpenseCategory)] = [
            (32, 0, 8, "楼下手冲咖啡", .chosen, .food),
            (1899, 0, 13, "双十一纠结三天后下单的降噪耳机", .chosen, .gadget),
            (45, 0, 19, "加班后打车回家", .necessity, .transport),
            (2580, -1, 10, "冲动报名的健身私教课", .impulse, .learning),
            (68, -1, 12, "和老妈吃面", .chosen, .family),
            (16, -1, 9, "地铁通勤", .necessity, .transport),
            (128, -2, 15, "猫咪疫苗复诊", .necessity, .family),
            (39, -2, 18, "外卖火锅", .impulse, .food),
            (199, -3, 11, "旅行基金定投", .chosen, .other),
            (96, -3, 20, "周末市集买的花瓶", .chosen, .beauty),
            (12, -4, 8, "共享单车月卡", .necessity, .transport),
            (330, -5, 14, "《沉思录》精装版", .chosen, .learning),
        ]
        for (amount, day, hour, note, nature, category) in demo {
            context.insert(Expense(
                amount: amount,
                date: today(day, hour),
                note: note,
                nature: nature,
                category: category
            ))
        }
        try? context.save()
        #endif
    }
}
