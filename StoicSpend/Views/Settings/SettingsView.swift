import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 页面 10 — Settings 设置
/// 订阅状态、隐私说明、AI 状态、导出数据、删除全部数据
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [AppSettings]
    @Query private var expenses: [Expense]

    @State private var showPaywall = false
    @State private var showDeleteConfirmation = false
    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var showCurrencyPicker = false
    @State private var pendingCurrency: String?  // 待确认切换的目标币种

    private var store = StoreKitService.shared
    private var aiService = FoundationModelsService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DesignTokens.Spacing.lg) {
                    // 1. 订阅状态（bronze 强调层）
                    subscriptionSection

                    // 2. 隐私 + AI Engine（合并一个 section）
                    privacyAndAISection

                    // 3. 冷静期设置（付费版解锁）
                    cooldownSection

                    // 4. 数据管理（导出 + 删除）
                    dataSection

                    // 5. 币种
                    currencySection

                    // 6. 外观
                    appearanceSection

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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
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
    }

    // MARK: - 订阅状态

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            sectionHeader("Subscription")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isPremium ? "Premium" : "Free Plan")
                        .serifTitle(20, weight: .semibold)
                        .foregroundStyle(DesignTokens.ink)
                    Text(store.isPremium
                         ? "All features unlocked"
                         : "Upgrade for AI & more")
                        .sansBody(13)
                        .foregroundStyle(DesignTokens.ash)
                }
                Spacer()

                if !store.isPremium {
                    Button {
                        showPaywall = true
                    } label: {
                        Text("Upgrade")
                            .sansBody(14, weight: .semibold)
                            .foregroundStyle(DesignTokens.paper)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .background(DesignTokens.bronze)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.card)
        // bronze 左边框强调订阅卡，与其他常规卡片区分层级
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DesignTokens.bronze)
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
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
            set: { currentSettings.cooldownEnabled = $0; try? modelContext.save() }
        )
        var cooldownHours = Binding(
            get: { currentSettings.cooldownHours },
            set: { currentSettings.cooldownHours = $0; try? modelContext.save() }
        )

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack {
                sectionHeader("Impulse Cooldown")
                Spacer()
                if !store.isPremium {
                    Image(systemName: "lock")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.ash)
                }
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
            .disabled(!store.isPremium)
            .onTapGesture {
                if !store.isPremium { showPaywall = true }
            }

            if currentSettings.cooldownEnabled || !store.isPremium {
                Picker("Duration", selection: cooldownHours) {
                    Text("24 hours").tag(24)
                    Text("72 hours").tag(72)
                }
                .pickerStyle(.segmented)
                .disabled(!store.isPremium)
                .onTapGesture {
                    if !store.isPremium { showPaywall = true }
                }
            }

            if !store.isPremium {
                Button {
                    showPaywall = true
                } label: {
                    // 去 sparkle emoji，用文字按钮保持克制
                    Text("Upgrade to Unlock")
                        .sansBody(14, weight: .semibold)
                        .foregroundStyle(DesignTokens.bronze)
                }
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

    // MARK: - 关于

    private var aboutSection: some View {
        // 关于区域最低调：无卡片背景，居中文字，视觉收敛
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text("Version 1.0.0")
                .monoData(12)
                .foregroundStyle(DesignTokens.ash.opacity(0.7))

            Text("Control what you can. Spend what matters.")
                .serifTitle(13, weight: .regular)
                .foregroundStyle(DesignTokens.ash.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.sm)
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

    private func exportData() {
        var csv = "Date,Amount,Nature,Values,EmotionalTrigger,Note\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        for e in expenses {
            let nature = e.nature?.rawValue ?? ""
            let values = e.values.map(\.rawValue).joined(separator: ";")
            let trigger = (e.emotionalTrigger ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let note = e.note.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(formatter.string(from: e.date)),\(e.amount),\(nature),\"\(values)\",\"\(trigger)\",\"\(note)\"\n"
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stoicspend_export.csv")
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            exportURL = tempURL
            showExportShare = true
        } catch {
            print("导出失败: \(error)")
        }
    }

    private func deleteAllData() {
        for expense in expenses {
            modelContext.delete(expense)
        }
        try? modelContext.save()
    }
}
