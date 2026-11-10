import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import os.log

/// 页面 10 — Settings 设置
/// 预算、隐私说明、AI 状态、导出数据、删除全部数据、关于（永久免费承诺 + 联系作者）
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var theme: ThemeManager
    @Query private var settings: [AppSettings]
    @Query private var expenses: [Expense]
    @Query private var budgets: [BudgetModel]

    @State private var showDeleteConfirmation = false
    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var showCurrencyPicker = false
    @State private var pendingCurrency: String?  // 待确认切换的目标币种

    // FR-10 导入 / 撤销
    @State private var showFileImporter = false
    @State private var csvPreview: BackupService.CSVImportResult?
    @State private var showCSVPreview = false
    @State private var importMessage: String?
    @State private var showImportMessage = false
    @State private var showUndoConfirmation = false
    @State private var hasUndoSnapshot = BackupService.hasSnapshot
    @State private var showSyncConfirmation = false

    private var aiService = FoundationModelsService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    // 1. 月度预算（免费功能）
                    budgetSection

                    // 1.6 可选 iCloud 同步（P1-5 免费）
                    syncSection

                    // 1.7 电脑端工作台（FR-11 P1，占位默认关）
                    workbenchSection

                    // 2. 隐私 + AI Engine（合并一个 section）
                    privacyAndAISection

                    // 3. 冷静期设置（免费）
                    cooldownSection

                    // 4. 数据管理（导出 + 删除）
                    dataSection

                    // 5. 币种
                    currencySection

                    // 6. 外观
                    appearanceSection

                    // 7. 晚间回顾提醒（FR-06，默认关）
                    reviewReminderSection

                    // 关于（最低调）
                    aboutSection
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.top, DesignTokens.Spacing.md)
                // 底部留足 Tab 栏高度，避免被悬浮 Tab 遮挡
                .padding(.bottom, 100)
            }
            .background(DesignTokens.paper)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            // 让 navigation bar 不透明，避免内容滚动时穿透标题
            .toolbarBackground(DesignTokens.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showCurrencyPicker) {
            currencyPickerSheet
        }
        .confirmationDialog(
            "Delete all data?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                deleteAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all expenses, reflections, and settings. This cannot be undone.")
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json, .commaSeparatedText]) { result in
            handleImportResult(result)
        }
        .sheet(isPresented: $showCSVPreview) {
            csvPreviewSheet
        }
        .alert("Import Complete", isPresented: $showImportMessage) {
            Button("Done", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
        .confirmationDialog(
            "Undo Last Import?",
            isPresented: $showUndoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Undo Import", role: .destructive) { undoLastImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Current expenses will be replaced with the snapshot taken before the import.")
        }
    }

    // MARK: - 月度预算（免费功能）

    private var budgetSection: some View {
        let currency = CurrencyService.shared.currentCurrency(in: modelContext)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                sectionHeader("Monthly Budget")
                Spacer()
                Text("Free")
                    .sansBody(12, weight: .semibold)
                    .foregroundStyle(DesignTokens.paper)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(DesignTokens.verdigris)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }

            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(CurrencyService.shared.symbol(for: currency))
                    .monoData(18)
                    .foregroundStyle(DesignTokens.ash)
                TextField("0", text: budgetInputProxy)
                    .keyboardType(.decimalPad)
                    .monoData(18)
                    .foregroundStyle(DesignTokens.ink)
                    .accessibilityIdentifier("settings.budget")
                Spacer()
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.paper)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))

            Text("Tracks your controllable (chosen) spending for the current month.")
                .sansBody(12)
                .foregroundStyle(DesignTokens.ash)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    /// 预算输入双向绑定：从 BudgetModel 取值，改动即落库
    private var budgetInputProxy: Binding<String> {
        Binding(
            get: { budgets.first.map { String(format: "%.0f", $0.monthlyLimit) } ?? "" },
            set: { newValue in
                let filtered = newValue.filter { "0123456789.".contains($0) }
                let value = Double(filtered) ?? 0
                saveBudget(value)
            }
        )
    }

    private func saveBudget(_ value: Double) {
        if let budget = budgets.first {
            budget.monthlyLimit = value
        } else {
            let budget = BudgetModel(monthlyLimit: value)
            modelContext.insert(budget)
        }
        try? modelContext.save()
    }

    // MARK: - 可选 iCloud 同步（P1-5 免费）

    private var cloudSyncEnabled: Binding<Bool> {
        Binding(
            get: { UserDefaults.standard.bool(forKey: "cloudSyncEnabled") },
            set: { newValue in
                // 开启需确认（数据将进入个人 iCloud）；关闭直接生效
                if newValue {
                    showSyncConfirmation = true
                } else {
                    UserDefaults.standard.set(false, forKey: "cloudSyncEnabled")
                }
            }
        )
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                sectionHeader("iCloud Sync")
                Spacer()
                Text("Optional")
                    .sansBody(12, weight: .semibold)
                    .foregroundStyle(DesignTokens.paper)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(DesignTokens.verdigris)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }

            Toggle(isOn: cloudSyncEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync across devices")
                        .sansBody(15)
                        .foregroundStyle(DesignTokens.ink)
                    Text("Data stays only in your Apple account — no own servers.")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
            }
            .tint(DesignTokens.bronze)

            Text("Off by default. Changes apply on next launch.")
                .sansBody(12)
                .foregroundStyle(DesignTokens.ash)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        // 首次开启提示：数据将进入个人 iCloud（PRD FR-10）
        .confirmationDialog(
            "Enable iCloud Sync?",
            isPresented: $showSyncConfirmation,
            titleVisibility: .visible
        ) {
            Button("Enable iCloud Sync") {
                UserDefaults.standard.set(true, forKey: "cloudSyncEnabled")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your data will be stored in your personal iCloud and synced across your devices. It still never touches our servers.")
        }
    }

    // MARK: - 电脑端工作台（FR-11，默认关）

    @ObservedObject private var workbench = WorkbenchService.shared

    private var workbenchSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Desktop Workbench")

            Toggle(isOn: workbenchBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Work on your computer over Wi-Fi")
                        .sansBody(15)
                        .foregroundStyle(DesignTokens.ink)
                    Text("Read and edit your ledger from a browser on the same network. Data never leaves your local network.")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
            }
            .tint(DesignTokens.bronze)

            if workbench.isRunning {
                // 地址 + 配对码（每次开启重新生成）
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    if let url = workbench.serverURL {
                        Text(url)
                            .monoData(16, weight: .semibold)
                            .foregroundStyle(DesignTokens.bronze)
                            .textSelection(.enabled)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                        Text("Pairing code")
                            .sansBody(13)
                            .foregroundStyle(DesignTokens.ash)
                        Text(workbench.pairingCode ?? "····")
                            .monoData(28, weight: .bold)
                            .foregroundStyle(DesignTokens.ink)
                            .tracking(6)
                    }
                    Text("Open the address in a browser on the same Wi-Fi, then enter the pairing code. The service stops after 10 idle minutes, or immediately when you lock the screen.")
                        .sansBody(12)
                        .foregroundStyle(DesignTokens.ash)
                }
                .padding(DesignTokens.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.paper)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            } else {
                Text("Off by default. Nothing is reachable until you turn it on.")
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.ash)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        // 锁屏 / 退后台立即不可访问（PRD FR-11）
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if workbench.isRunning { workbench.stop() }
        }
    }

    private var workbenchBinding: Binding<Bool> {
        Binding(
            get: { workbench.isRunning },
            set: { $0 ? workbench.start() : workbench.stop() }
        )
    }

    // MARK: - 隐私 + AI Engine（合并）

    private var privacyAndAISection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Privacy & AI Engine")

            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "iphone")
                    .foregroundStyle(DesignTokens.verdigris)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Data stored on this device only")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    Text("No server. No cloud. No account.")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
            }

            Divider()

            HStack(spacing: DesignTokens.Spacing.sm) {
                // 细线符号替代实心圆，去警告风：
                // 可用 → checkmark（verdigris）；不可用 → circle.dashed（ash，克制中性）
                Image(systemName: aiService.isAvailable ? "checkmark" : "circle.dashed")
                    .foregroundStyle(aiService.isAvailable ? DesignTokens.verdigris : DesignTokens.ash)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Foundation Models")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    if aiService.isAvailable {
                        Text("On-device AI is active")
                            .sansBody(13)
                            .foregroundStyle(DesignTokens.ash)
                    } else {
                        // 不可用用 ash 而非 rust，避免警告感
                        Text(reasonText)
                            .sansBody(13)
                            .foregroundStyle(DesignTokens.ash)
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - 币种设置

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Currency")

            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "dollarsign.circle")
                    .foregroundStyle(DesignTokens.bronze)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Display Currency")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    Text(currencySubtitle)
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
                Spacer()
                Text(currentCurrencyCode)
                    .monoData(14, weight: .semibold)
                    .foregroundStyle(DesignTokens.bronze)
            }

            Button {
                showCurrencyPicker = true
            } label: {
                settingRow(icon: "arrow.left.arrow.right", title: "Switch Currency", color: DesignTokens.bronze)
            }
            .confirmationDialog(
                pendingCurrency != nil ? "Switch Currency" : "",
                isPresented: Binding(
                    get: { pendingCurrency != nil },
                    set: { if !$0 { pendingCurrency = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let target = pendingCurrency {
                    Button("Convert & Switch") {
                        CurrencyService.shared.switchCurrency(to: target, in: modelContext)
                        pendingCurrency = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingCurrency = nil
                    }
                }
            } message: {
                if let target = pendingCurrency {
                    Text(currencySwitchMessage(target: target))
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var currentCurrencyCode: String {
        let code = currentSettings.currentCurrency
        return code.isEmpty ? CurrencyService.defaultCurrencyForCurrentLocale() : code
    }

    // MARK: - 外观设置

    @AppStorage("appearancePreference") private var appearance: String = "system"

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Appearance")

            themeColorRow

            // 展示层字体选择 — 仅标题/语录/大数字切换，正文保持系统（UI 安全）
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "textformat")
                    .foregroundStyle(DesignTokens.bronze)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Display Font")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    Text(Typography.displayPreviewNote)
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                    Text("Stoic ¥ 72%")
                        .font(Typography.serif(24, weight: .semibold))
                        .foregroundStyle(theme.current.accentColor)
                        .lineLimit(1)
                }
                Spacer()
                Picker("", selection: Binding(
                    get: { theme.displayFont },
                    set: { theme.displayFont = $0 }
                )) {
                    ForEach(DisplayFont.allCases) { f in
                        Text(f.localizedName).tag(f)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            // 图标动态替换（FR-06 P1）：App 图标跟随主题强调色
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "app.dashed")
                    .foregroundStyle(DesignTokens.bronze)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Icon Follows Theme")
                        .sansBody(15)
                        .foregroundStyle(DesignTokens.ink)
                    Text("App icon switches with the theme color.")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
                Spacer()
                Toggle(isOn: iconFollowsThemeBinding) { }
                    .labelsHidden()
                    .tint(DesignTokens.bronze)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(DesignTokens.bronze)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Theme")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    Text(appearanceSubtitle)
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
                Spacer()
                Picker("", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        // 主题切换后同步 App 图标（若开启跟随）
        .onChange(of: theme.current) { _, newTheme in
            AppIconService.syncIcon(for: newTheme)
        }
    }

    /// 图标跟随主题开关绑定
    private var iconFollowsThemeBinding: Binding<Bool> {
        Binding(
            get: { AppIconService.followsTheme },
            set: { AppIconService.followsTheme = $0; AppIconService.syncIcon(for: theme.current) }
        )
    }

    /// 配色主题行 — 6 个预设色圆点 + 🎲 随机色，选择存 UserDefaults 记忆
    private var themeColorRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "paintpalette")
                .foregroundStyle(DesignTokens.bronze)
            VStack(alignment: .leading, spacing: 2) {
                Text("Color Theme")
                    .sansBody(15, weight: .medium)
                    .foregroundStyle(DesignTokens.ink)
                Text(theme.current.localizedName)
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)
            }
            Spacer()
            HStack(spacing: 10) {
                ForEach(AppTheme.allCases) { t in
                    Circle()
                        .fill(t.accentColor)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().strokeBorder(
                                theme.current == t ? DesignTokens.ink : Color.clear,
                                lineWidth: 2
                            )
                        )
                        .onTapGesture { theme.current = t }
                }
                Text("🎲")
                    .font(.system(size: 18))
                    .onTapGesture { theme.randomize() }
            }
        }
    }

    // MARK: - 晚间回顾提醒（FR-06）

    @AppStorage("reviewReminderEnabled") private var reviewReminderEnabled = false
    @AppStorage("reviewReminderHour") private var reviewReminderHour = 21
    @AppStorage("reviewReminderMinute") private var reviewReminderMinute = 0

    private var reviewReminderDate: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reviewReminderHour, minute: reviewReminderMinute, second: 0, of: .now
                ) ?? .now
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                reviewReminderHour = comps.hour ?? 21
                reviewReminderMinute = comps.minute ?? 0
                applyReviewReminder()
            }
        )
    }

    private var reviewReminderSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Evening Review")

            HStack(spacing: DesignTokens.Spacing.sm) {
                Text("◈")
                    .serifTitle(18, weight: .regular)
                    .foregroundStyle(theme.current.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("晚间回顾提醒")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    Text("完全可选 · 每天一次 10 秒")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { reviewReminderEnabled },
                    set: { newValue in
                        reviewReminderEnabled = newValue
                        applyReviewReminder()
                    }
                ))
                .labelsHidden()
                .tint(theme.current.accentColor)
            }

            if reviewReminderEnabled {
                DatePicker("提醒时间", selection: reviewReminderDate, displayedComponents: .hourAndMinute)
                    .sansBody(14)
                    .foregroundStyle(DesignTokens.ink)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func applyReviewReminder() {
        ReviewReminderService.apply(
            enabled: reviewReminderEnabled,
            hour: reviewReminderHour,
            minute: reviewReminderMinute
        )
    }

    private var appearanceSubtitle: String {
        switch appearance {
        case "light": return String(localized: "Always light")
        case "dark": return String(localized: "Always dark")
        default: return String(localized: "Follow system")
        }
    }

    private var currencySubtitle: String {
        let name = CurrencyService.shared.localizedName(for: currentCurrencyCode)
        // 明确是离线内置汇率，不暗示联网更新（与无服务器承诺一致）
        return "\(name) · " + String(localized: "Bundled rates · Offline")
    }

    private var reasonText: String {
        if case .unavailable(let reason) = aiService.availability {
            return reason
        }
        return String(localized: "AI features unavailable")
    }

    /// 当前AppSettings，不存在则创建
    private var currentSettings: AppSettings {
        if let s = settings.first { return s }
        let s = AppSettings()
        modelContext.insert(s)
        try? modelContext.save()
        return s
    }

    // MARK: - 冷静期设置（付费解锁）

    private var cooldownSection: some View {
        var cooldownEnabled = Binding(
            get: { currentSettings.cooldownEnabled },
            set: {
                currentSettings.cooldownEnabled = $0
                if $0 {
                    NotificationService.scheduleCooldownReminder(hours: currentSettings.cooldownHours)
                } else {
                    NotificationService.cancelCooldownReminder()
                }
                try? modelContext.save()
            }
        )
        var cooldownHours = Binding(
            get: { currentSettings.cooldownHours },
            set: {
                currentSettings.cooldownHours = $0
                if currentSettings.cooldownEnabled {
                    NotificationService.scheduleCooldownReminder(hours: $0)
                }
                try? modelContext.save()
            }
        )

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                sectionHeader("Impulse Cooldown")
                Spacer()
                // P1-3：免费核心功能
                Text("Free")
                    .sansBody(12, weight: .semibold)
                    .foregroundStyle(DesignTokens.paper)
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, 4)
                    .background(DesignTokens.verdigris)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "hourglass")
                    .foregroundStyle(DesignTokens.bronze)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause before impulse buys")
                        .sansBody(15, weight: .medium)
                        .foregroundStyle(DesignTokens.ink)
                    Text("Let reason catch up with desire.")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
            }

            Toggle(isOn: cooldownEnabled) {
                Text("Enable Cooldown")
                    .sansBody(15)
                    .foregroundStyle(DesignTokens.ink)
            }
            .tint(DesignTokens.bronze)

            if currentSettings.cooldownEnabled {
                Picker("Duration", selection: cooldownHours) {
                    Text("24 hours").tag(24)
                    Text("72 hours").tag(72)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - 数据管理（导出 + 删除合并）

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Data")

            Button {
                exportData()
            } label: {
                settingRow(icon: "square.and.arrow.up", title: "Export Data", color: DesignTokens.bronze)
            }

            // JSON 全量备份（FR-10）：含全部字段，可用于跨设备完整恢复
            Button {
                exportBackupJSON()
            } label: {
                settingRow(icon: "externaldrive.badge.icloud", title: "Full Backup (JSON)", color: DesignTokens.bronze)
            }

            Button {
                showFileImporter = true
            } label: {
                settingRow(icon: "square.and.arrow.down", title: "Import (CSV / JSON)", color: DesignTokens.bronze)
            }

            if hasUndoSnapshot {
                Button {
                    showUndoConfirmation = true
                } label: {
                    settingRow(icon: "arrow.uturn.backward", title: "Undo Last Import", color: DesignTokens.verdigris)
                }
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .foregroundStyle(DesignTokens.rust)
                        .frame(width: 24)
                    Text("Delete All Data")
                        .sansBody(15)
                        .foregroundStyle(DesignTokens.rust)
                    Spacer()
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - 关于（完全免费承诺 + 联系作者）

    private var aboutSection: some View {
        Group {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("About")

            // 永久免费承诺 — 无订阅无内购，未来更新也免费
            VStack(alignment: .leading, spacing: 6) {
                Text("Completely free · No IAP")
                    .sansBody(15, weight: .medium)
                    .foregroundStyle(DesignTokens.ink)
                Text("No subscription. No in-app purchases. All features are free, and every future update will stay free.")
                    .sansBody(13)
                    .foregroundStyle(DesignTokens.ash)
            }

            Divider()

            Button {
                open(LegalLinks.supportEmail)
            } label: {
                settingRow(icon: "envelope", title: "Contact the Author", color: DesignTokens.bronze)
            }

            Button {
                open(LegalLinks.weiboHome)
            } label: {
                settingRow(icon: "megaphone", title: "Follow on Weibo", color: DesignTokens.bronze)
            }

            Button {
                open(LegalLinks.privacyPolicy)
            } label: {
                settingRow(icon: "hand.raised", title: "Privacy Policy", color: DesignTokens.ash)
            }

            Button {
                open(LegalLinks.termsOfUse)
            } label: {
                settingRow(icon: "doc.text", title: "Terms of Use", color: DesignTokens.ash)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))

        // 版本号（低调居中，从 Bundle 动态读取）
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text(verbatim: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .monoData(12)
                .foregroundStyle(DesignTokens.ash.opacity(0.7))

            Text("Control what you can. Spend what matters.")
                .serifTitle(13, weight: .regular)
                .foregroundStyle(DesignTokens.ash.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.xs)
        }
    }

    /// 打开外部链接（mailto / https）
    private func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    // MARK: - 通用组件

    /// 币种选择 sheet
    private var currencyPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(CurrencyService.supportedCurrencies, id: \.self) { code in
                    Button {
                        if code != currentCurrencyCode {
                            pendingCurrency = code
                        }
                        showCurrencyPicker = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CurrencyService.shared.localizedName(for: code))
                                    .sansBody(15, weight: .medium)
                                    .foregroundStyle(DesignTokens.ink)
                                Text(code)
                                    .monoData(12)
                                    .foregroundStyle(DesignTokens.ash)
                            }
                            Spacer()
                            if code == currentCurrencyCode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(DesignTokens.bronze)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showCurrencyPicker = false }
                        .foregroundStyle(DesignTokens.ash)
                }
            }
        }
    }

    /// 切换币种的确认消息
    private func currencySwitchMessage(target: String) -> String {
        let rate = CurrencyService.shared.exchangeRate(
            from: currentCurrencyCode,
            to: target,
            customRates: currentSettings.customRates
        )
        let count = expenses.count
        let fromSymbol = CurrencyService.shared.localizedName(for: currentCurrencyCode)
        let toSymbol = CurrencyService.shared.localizedName(for: target)
        return String(format: String(localized: "Convert %d records from %@ to %@? Rate: 1 %@ = %.4f %@"), count, fromSymbol, toSymbol, currentCurrencyCode, rate, target)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .sansBody(13, weight: .semibold)
            .foregroundStyle(DesignTokens.ash)
    }

    private func settingRow(icon: String, title: LocalizedStringKey, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title)
                .sansBody(15)
                .foregroundStyle(DesignTokens.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(DesignTokens.ash)
        }
    }

    // MARK: - 逻辑

    /// CSV 导出（FR-10）— UTF-8 with BOM（Excel/Numbers 中文不乱码），PRD 固定表头
    private func exportData() {
        let data = BackupService.makeCSV(expenses: expenses)

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stoicspend_export.csv")
        do {
            try data.write(to: tempURL, options: .atomic)
            exportURL = tempURL
            showExportShare = true
        } catch {
            Logger(subsystem: "com.zhenglin.stoicspend", category: "Settings").error("导出失败: \(error.localizedDescription)")
        }
    }

    /// JSON 全量备份导出（FR-10）— 全字段 + schemaVersion
    private func exportBackupJSON() {
        do {
            let data = try BackupService.makeBackupJSON(
                expenses: expenses,
                budget: budgets.first,
                settings: currentSettings
            )
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(BackupService.backupFilename)
            try data.write(to: tempURL, options: .atomic)
            exportURL = tempURL
            showExportShare = true
        } catch {
            Logger(subsystem: "com.zhenglin.stoicspend", category: "Settings").error("JSON 备份失败: \(error.localizedDescription)")
        }
    }

    // MARK: - 导入（CSV / JSON）

    /// CSV 导入预览 sheet — 条数 + 样例 + 确认
    private var csvPreviewSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text("Import Preview")
                        .serifTitle(20, weight: .semibold)
                        .foregroundStyle(DesignTokens.ink)
                    Text("\(csvPreview?.records.count ?? 0) records will be added. \(csvPreview?.skippedRows ?? 0) rows will be skipped.")
                        .sansBody(14)
                        .foregroundStyle(DesignTokens.ash)
                }

                if let samples = csvPreview?.sampleNotes, !samples.isEmpty {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        Text("Sample rows")
                            .sansBody(13, weight: .semibold)
                            .foregroundStyle(DesignTokens.ash)
                        ForEach(samples, id: \.self) { s in
                            Text(s)
                                .monoData(13)
                                .foregroundStyle(DesignTokens.ink)
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DesignTokens.paper)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                }

                Text("A snapshot of your current data will be taken automatically — you can undo after importing.")
                    .sansBody(12)
                    .foregroundStyle(DesignTokens.ash)

                Spacer()
            }
            .padding(DesignTokens.Spacing.md)
            .background(DesignTokens.paper)
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCSVPreview = false }
                        .foregroundStyle(DesignTokens.ash)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { confirmCSVImport() }
                        .fontWeight(.semibold)
                        .foregroundStyle(DesignTokens.bronze)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()

            if ext == "json" {
                let backup = try BackupService.parseBackup(data)
                BackupService.makeSnapshot(expenses: expenses)
                let count = try BackupService.restore(backup, in: modelContext)
                hasUndoSnapshot = true
                importMessage = String(format: String(localized: "Restored %d expenses from backup."), count)
                showImportMessage = true
            } else {
                let parsed = BackupService.parseCSV(data)
                if parsed.records.isEmpty {
                    importMessage = String(localized: "No importable records found. Check the file header and format.")
                    showImportMessage = true
                } else {
                    csvPreview = parsed
                    showCSVPreview = true
                }
            }
        } catch {
            importMessage = String(format: String(localized: "Import failed: %@"), error.localizedDescription)
            showImportMessage = true
        }
    }

    private func confirmCSVImport() {
        guard let records = csvPreview?.records else { return }
        BackupService.makeSnapshot(expenses: expenses)
        do {
            let count = try BackupService.insertCSVRecords(records, in: modelContext)
            hasUndoSnapshot = true
            showCSVPreview = false
            importMessage = String(format: String(localized: "Imported %d records."), count)
            showImportMessage = true
        } catch {
            showCSVPreview = false
            importMessage = String(format: String(localized: "Import failed: %@"), error.localizedDescription)
            showImportMessage = true
        }
    }

    private func undoLastImport() {
        do {
            let count = try BackupService.undoImport(in: modelContext)
            hasUndoSnapshot = BackupService.hasSnapshot
            importMessage = String(format: String(localized: "Restored %d expenses from snapshot."), count)
            showImportMessage = true
        } catch {
            importMessage = String(format: String(localized: "Import failed: %@"), error.localizedDescription)
            showImportMessage = true
        }
    }

    private func deleteAllData() {
        for expense in expenses {
            modelContext.delete(expense)
        }
        try? modelContext.save()
    }
}
