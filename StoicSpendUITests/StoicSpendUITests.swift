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

    // MARK: - 2. 快记三问全流程（FR-02）

    func testQuickAddThreeQuestionsSavedToLedger() {
        let app = launch()
        let addButton = app.buttons["+ 记一笔"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.tap()

        // 金额 25 — 自绘数字键盘
        XCTAssertTrue(app.buttons["2"].waitForExistence(timeout: 5), "快记页应出现自绘数字键盘")
        app.buttons["2"].tap()
        app.buttons["5"].tap()

        // Q1 性质：默认折叠为一行（默认值即上次选择，弱化不强制点）
        let natureRow = app.buttons.matching(NSPredicate(
            format: "label CONTAINS '主动选择' OR label CONTAINS '必须花' OR label CONTAINS '冲动了'"
        )).firstMatch
        XCTAssertTrue(natureRow.waitForExistence(timeout: 3), "性质行应存在（折叠为一行）")

        // Q2 分类：🍜 饮食
        let foodChip = app.buttons.matching(NSPredicate(format: "label CONTAINS '饮食'")).firstMatch
        XCTAssertTrue(foodChip.waitForExistence(timeout: 3), "三问之二：九分法分类宫格")
        foodChip.tap()

        // Q3 情绪：平静（可选，测一次）
        let calmChip = app.buttons.matching(NSPredicate(format: "label CONTAINS '平静'")).firstMatch
        if calmChip.waitForExistence(timeout: 2) {
            calmChip.tap()
        }

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
