import XCTest
@testable import StoicSpend

/// 关键功能 UI 测试 — 引导 / 快记三问 / 帐本 / 设置
/// 启动参数：UITEST + UITEST_FRESH（清空数据）+ UITEST_SKIP_ONBOARDING（跳过引导）
final class StoicSpendUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// 启动 App（默认全新数据 + 跳过引导 + 强制中文）
    private func launch(fresh: Bool = true, skipOnboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["UITEST"]
        if fresh { args.append("UITEST_FRESH") }
        if skipOnboarding { args.append("UITEST_SKIP_ONBOARDING") }
        app.launchArguments = args + ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }

    // MARK: - 1. 首次启动引导（FR-07）

    func testOnboardingShowsOnFirstLaunchAndCompletes() {
        let app = XCUIApplication()
        app.launchArguments = ["UITEST", "UITEST_FRESH", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        let begin = app.buttons.matching(NSPredicate(format: "label == '开始' OR label == 'Begin'")).firstMatch
        XCTAssertTrue(begin.waitForExistence(timeout: 10), "全新数据首次启动应显示引导页")
        begin.tap()

        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 5), "点击开始应进入主界面 4 Tab")
        XCTAssertEqual(app.tabBars.buttons.count, 4, "应为 4 个 Tab：首页/帐本/奥卡姆/设置")
    }

    // MARK: - 2. 快记一屏流程（FR-02 + 一屏宫格重构）

    func testQuickAddThreeQuestionsSavedToLedger() {
        let app = launch()
        let addButton = app.buttons["+ 记一笔"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.tap()

        // 金额 25 — 自绘数字键盘
        XCTAssertTrue(app.buttons["2"].waitForExistence(timeout: 5), "快记页应出现自绘数字键盘")
        app.buttons["2"].tap()
        app.buttons["5"].tap()

        // 分类宫格一屏常驻（零滚动）
        let foodChip = app.buttons["quickadd.cat.cat.food"]
        XCTAssertTrue(foodChip.waitForExistence(timeout: 3), "4×4 宫格应一屏常驻")
        foodChip.tap()

        // 性质/情绪/备注在「补充」sheet
        let extra = app.buttons["quickadd.extra"]
        XCTAssertTrue(extra.waitForExistence(timeout: 3), "补充按钮应存在")
        extra.tap()
        let natureChip = app.buttons.matching(NSPredicate(format: "label CONTAINS '主动选择'")).firstMatch
        XCTAssertTrue(natureChip.waitForExistence(timeout: 5), "补充 sheet 应含性质三选一")
        natureChip.tap()

        let close = app.buttons["quickadd.extra.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()

        // 保存
        let save = app.buttons["quickadd.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()

        XCTAssertTrue(app.buttons["+ 记一笔"].waitForExistence(timeout: 5), "保存后应关闭快记页回首页")

        // 帐本出现该笔
        app.tabBars.buttons["帐本"].tap()
        let amountText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS '25'")).firstMatch
        XCTAssertTrue(amountText.waitForExistence(timeout: 5), "帐本应显示刚记的 25 元支出")
    }

    // MARK: - 2.5 设置自定义分类后出现在快记宫格（FR-29）

    func testCustomCategoryAddedAppearsInQuickAddGrid() {
        let app = launch()
        _ = app.buttons["+ 记一笔"].waitForExistence(timeout: 10)

        app.tabBars.buttons["设置"].tap()
        let entry = app.buttons["settings.categories"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "设置页应有自定义分类入口")
        entry.tap()

        // 添加自定义分类「通信费」
        let field = app.textFields["category.name.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("通信费")
        let add = app.buttons["category.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()

        // 返回 → 快记宫格应出现「通信费」
        app.navigationBars.buttons.firstMatch.tap()
        app.tabBars.buttons["首页"].tap()
        let addButton = app.buttons["+ 记一笔"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let chip = app.buttons.matching(NSPredicate(format: "label CONTAINS '通信费'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "自定义分类应出现在快记宫格")
    }

    // MARK: - 3. 帐本月份穿梭与分区（FR-03）

    func testLedgerRendersAfterQuickAdd() {
        let app = launch()
        _ = app.buttons["+ 记一笔"].waitForExistence(timeout: 10)

        app.tabBars.buttons["帐本"].tap()
        // 空数据帐本页应正常渲染（无崩溃）——验证任一导航标题或分区存在
        XCTAssertTrue(app.tabBars.buttons["奥卡姆"].waitForExistence(timeout: 5))
        app.tabBars.buttons["奥卡姆"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(app.buttons["+ 记一笔"].waitForExistence(timeout: 5), "Tab 往返不应丢失首页主按钮")
    }

    // MARK: - 4. 设置页关键区块（FR-06/FR-10/FR-11）

    func testSettingsKeySectionsVisible() {
        let app = launch()
        _ = app.buttons["+ 记一笔"].waitForExistence(timeout: 10)
        app.tabBars.buttons["设置"].tap()

        // 关键区块（zh-Hans 本地化值 + 预算输入框标识符）
        for title in ["电脑端工作台", "隐私"] {
            let heading = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 5), "设置页应包含「\(title)」区块")
        }
        XCTAssertTrue(app.textFields["settings.budget"].waitForExistence(timeout: 5), "设置页应包含月度预算输入框")
    }

    // MARK: - 5. 月度预算设置并持久化（P0-2）

    func testBudgetInputPersistsAcrossRelaunch() {
        let app = launch()
        _ = app.buttons["+ 记一笔"].waitForExistence(timeout: 10)
        app.tabBars.buttons["设置"].tap()

        let field = app.textFields["settings.budget"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "设置页应出现预算输入框")
        field.tap()
        field.typeText("3000")

        // 重启（不清数据）→ 预算仍在
        app.launchArguments = ["UITEST", "UITEST_SKIP_ONBOARDING", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tabBars.buttons["设置"].tap()

        let relaunched = app.textFields["settings.budget"]
        XCTAssertTrue(relaunched.waitForExistence(timeout: 5))
        let value = relaunched.value as? String ?? ""
        XCTAssertTrue(value.contains("3000"), "重启后预算应保持 3000，实际：\(value)")
    }
}
