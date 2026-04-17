// SeedoMac/Views/Dashboard/SettingsView.swift
import SwiftUI
import ServiceManagement
import AppKit
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var baseURL: String = "https://api.openai.com/v1"
    @State private var model: String = "gpt-4o-mini"
    @State private var provider: String = "openai"
    @State private var afkMinutes: Double = 15
    @State private var autostartEnabled = false
    @State private var apiKeyMasked = true
    @State private var obsidianVaultPath: String = ""
    @State private var obsidianAutoImport: Bool = false
    @State private var obsidianImportStatus: String? = nil
    @State private var autoSummaryEnabled: Bool = false
    @State private var autoSummaryTime: Date = SettingsView.defaultAutoSummaryTime()
    @State private var breakWorkInterval: Int = 45
    @State private var breakDuration: Int = 5
    @State private var breakLongDuration: Int = 15
    @State private var breakLongFrequency: Int = 4
    @State private var breakLongEnabled: Bool = true
    @State private var breakEnabledToday: Bool = true
    @State private var breakBackgroundColor: Color = .black
    @State private var breakBackgroundImagePath: String = ""
    @State private var calendarSyncEnabled: Bool = false
    @State private var categories: [SessionCategory] = []
    @State private var saveStatus: String? = nil

    private let providers: [(String, String, String)] = [
        ("openai", "OpenAI", "https://api.openai.com/v1"),
        ("deepseek", "DeepSeek", "https://api.deepseek.com"),
        ("anthropic", "Anthropic", "https://api.anthropic.com/v1"),
        ("custom", "Custom", "")
    ]

    var body: some View {
        Form {
            Section("应用") {
                Toggle("Launch at Login", isOn: $autostartEnabled)
                    .onChange(of: autostartEnabled) { newVal in
                        toggleAutostart(newVal)
                    }

                if !appState.hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Accessibility permission required for window titles")
                            .font(.caption)
                        Button("Grant") { WindowInfoProvider.requestPermission() }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Section("AI 配置") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Provider").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $provider) {
                            ForEach(providers, id: \.0) { p in Text(p.1).tag(p.0) }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $model)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .onChange(of: provider) { newProvider in
                    if let preset = providers.first(where: { $0.0 == newProvider }), !preset.2.isEmpty {
                        baseURL = preset.2
                    }
                }

                if provider == "custom" {
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("API Key").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if apiKeyMasked {
                            SecureField("", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            TextField("", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button(apiKeyMasked ? "Show" : "Hide") { apiKeyMasked.toggle() }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                    }
                }

                HStack {
                    Toggle("每日自动生成今日 AI 总结", isOn: $autoSummaryEnabled)
                        .font(.subheadline)
                    if autoSummaryEnabled {
                        Spacer()
                        DatePicker("",
                                   selection: $autoSummaryTime,
                                   displayedComponents: [.hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .controlSize(.small)
                    }
                }
            }

            Section("基本休息设置") {
                Toggle("今日启用休息提醒", isOn: $breakEnabledToday)
                    .onChange(of: breakEnabledToday) { _ in
                        saveSettings()
                        BreakScheduler.shared.refreshConfig()
                    }

                HStack {
                    Text("开始专注间隔")
                    Spacer()
                    TextField("", value: $breakWorkInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("分钟")
                    Stepper("", value: $breakWorkInterval, in: 5...240, step: 5)
                }

                HStack {
                    Text("短休息时长")
                    Spacer()
                    TextField("", value: $breakDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("分钟")
                    Stepper("", value: $breakDuration, in: 1...60, step: 1)
                }
            }

            Section("循环休息 (Pomodoro)") {
                Toggle("启用长休息", isOn: $breakLongEnabled)
                    .font(.subheadline)

                HStack {
                    Text("长休息频率")
                    Spacer()
                    Text("每完成")
                    TextField("", value: $breakLongFrequency, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 40)
                    Text("次专注后")
                    Stepper("", value: $breakLongFrequency, in: 1...10, step: 1)
                }
                .font(.subheadline)
                .opacity(breakLongEnabled ? 1.0 : 0.5)
                .disabled(!breakLongEnabled)

                HStack {
                    Text("长休息时长")
                    Spacer()
                    TextField("", value: $breakLongDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Text("分钟")
                    Stepper("", value: $breakLongDuration, in: 5...60, step: 1)
                }
                .disabled(!breakLongEnabled)
                .opacity(breakLongEnabled ? 1.0 : 0.5)
            }

            Section("外观与个性化") {
                HStack {
                    Text("背景颜色")
                    Spacer()
                    ColorPicker("", selection: $breakBackgroundColor)
                }

                HStack {
                    Text("背景图片")
                    Spacer()
                    if !breakBackgroundImagePath.isEmpty {
                        Text(URL(fileURLWithPath: breakBackgroundImagePath).lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 150, alignment: .trailing)
                        
                        Button("清除") {
                            clearBackgroundImage()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                    
                    Button(breakBackgroundImagePath.isEmpty ? "选择图片" : "更换") {
                        selectBackgroundImage()
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Button("立即测试覆盖层") {
                        triggerTestBreak()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    HStack {
                        let elapsed = BreakScheduler.shared.workElapsedSecs / 60
                        let total = BreakScheduler.shared.sessionsSinceLongBreak
                        Text("当前专注: \(elapsed)m | 已完成 \(total)/\(breakLongFrequency)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Section("同步与集成") {
                Toggle("同步专注记录到日历", isOn: $calendarSyncEnabled)
                    .onChange(of: calendarSyncEnabled) { enabled in
                        if enabled {
                            CalendarSyncService.shared.requestAccess { granted in
                                if !granted {
                                    DispatchQueue.main.async {
                                        self.calendarSyncEnabled = false
                                    }
                                }
                            }
                        }
                    }
            }

            Section("数据追踪") {
                VStack(alignment: .leading) {
                    Text("AFK Threshold: \(Int(afkMinutes)) minutes")
                    Slider(value: $afkMinutes, in: 5...60, step: 1)
                }

                Toggle("Redact Window Titles (Privacy)", isOn: $appState.isRedactTitles)
            }

            Section("Obsidian 日记导入") {
                HStack {
                    TextField("Vault 路径", text: $obsidianVaultPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button("选择…") { pickObsidianVault() }
                }
                Text("路径: {vault}/sources/diarys/{yyyyMMdd}.md")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("自动导入今日日记", isOn: $obsidianAutoImport)

                HStack {
                    Button("立即导入今天") { importObsidianNow() }
                        .disabled(obsidianVaultPath.isEmpty)
                    if let status = obsidianImportStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("标签与分类管理") {
                ForEach($categories) { $cat in
                    HStack {
                        ColorPicker("", selection: Binding(
                            get: { cat.color },
                            set: { newVal in
                                var updated = cat
                                updated.id = cat.id // maintain ID
                                // Need to convert Color to Hex
                                let hex = colorToHex(newVal)
                                // We can't directly update private colorHex easily here without a helper
                                updateCategoryColor(id: cat.id, newHex: hex)
                            }
                        ))
                        .labelsHidden()
                        .frame(width: 40)
                        
                        TextField("名称", text: $cat.name)
                            .textFieldStyle(.plain)
                            .onSubmit { saveCategory(cat) }
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            deleteCategory(cat)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { from, to in
                    moveCategories(from: from, to: to)
                }

                Button(action: addCategory) {
                    Label("添加新分类", systemImage: "plus.circle")
                }
            }

            Section("快捷键设置") {
                HStack {
                    Text("开始专注 / 暂停")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .startPauseFocus)
                }
                HStack {
                    Text("开启纯专注模式")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .togglePureFocus)
                }
                Text("注: 快捷键在应用运行时全局生效。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("日志与数据") {
                Button("Open Logs Folder") {
                    let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Logs/SeedoMac")
                    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(logDir)
                }
            }

            HStack {
                Spacer()
                if let status = saveStatus {
                    Text(status).foregroundStyle(.secondary).font(.caption)
                }
                Button("Save Settings") { saveSettings() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadSettings()
            refreshCategories()
        }
    }

    // MARK: - Actions

    private func loadSettings() {
        apiKey = KeychainHelper.loadAPIKey() ?? ""
        baseURL = AppDatabase.shared.setting(for: "ai_base_url") ?? "https://api.openai.com/v1"
        model = AppDatabase.shared.setting(for: "ai_model") ?? "gpt-4o-mini"
        afkMinutes = appState.afkThresholdSecs / 60
        autostartEnabled = (SMAppService.mainApp.status == .enabled)
        obsidianVaultPath = AppDatabase.shared.setting(for: "obsidian_vault_path") ?? ""
        obsidianAutoImport = (AppDatabase.shared.setting(for: "obsidian_auto_import") == "true")
        autoSummaryEnabled = (AppDatabase.shared.setting(for: "auto_summary_enabled") == "true")
        autoSummaryTime = Self.parseTimeOfDay(
            hour: AppDatabase.shared.setting(for: "auto_summary_hour"),
            minute: AppDatabase.shared.setting(for: "auto_summary_minute")
        )
        // Break Reminder
        breakWorkInterval = Int(AppDatabase.shared.setting(for: "break_work_interval_mins") ?? "45") ?? 45
        breakDuration = Int(AppDatabase.shared.setting(for: "break_duration_mins") ?? "5") ?? 5
        breakLongDuration = Int(AppDatabase.shared.setting(for: "break_long_duration_mins") ?? "15") ?? 15
        breakLongFrequency = Int(AppDatabase.shared.setting(for: "break_long_frequency") ?? "4") ?? 4
        breakLongEnabled = (AppDatabase.shared.setting(for: "break_long_enabled") != "false")
        
        let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        let disabledDay = AppDatabase.shared.setting(for: "break_disabled_day") ?? ""
        breakEnabledToday = (disabledDay != todayStr)
        let bgHex = AppDatabase.shared.setting(for: "break_background_hex") ?? "#000000"
        breakBackgroundColor = Color(hex: bgHex)
        breakBackgroundImagePath = AppDatabase.shared.setting(for: "break_background_image_path") ?? ""
        calendarSyncEnabled = AppDatabase.shared.setting(for: "calendar_sync_enabled") == "true"

        if let match = providers.first(where: { $0.2 == baseURL }) {
            provider = match.0
        } else if baseURL != "https://api.openai.com/v1" {
            provider = "custom"
        }
    }

    private func saveSettings() {
        if apiKey.isEmpty {
            KeychainHelper.deleteAPIKey()
        } else {
            KeychainHelper.saveAPIKey(apiKey)
        }
        AppDatabase.shared.saveSetting(key: "ai_base_url", value: baseURL)
        AppDatabase.shared.saveSetting(key: "ai_model", value: model)
        AppDatabase.shared.saveSetting(key: "afk_threshold_secs", value: String(afkMinutes * 60))
        AppDatabase.shared.saveSetting(key: "redact_titles", value: appState.isRedactTitles ? "true" : "false")
        AppDatabase.shared.saveSetting(key: "obsidian_vault_path", value: obsidianVaultPath)
        AppDatabase.shared.saveSetting(key: "obsidian_auto_import",
                                       value: obsidianAutoImport ? "true" : "false")
        AppDatabase.shared.saveSetting(key: "auto_summary_enabled",
                                       value: autoSummaryEnabled ? "true" : "false")
        let comps = Calendar.current.dateComponents([.hour, .minute], from: autoSummaryTime)
        AppDatabase.shared.saveSetting(key: "auto_summary_hour",
                                       value: String(comps.hour ?? 23))
        AppDatabase.shared.saveSetting(key: "auto_summary_minute",
                                       value: String(comps.minute ?? 0))
        
        AppDatabase.shared.saveSetting(key: "break_work_interval_mins", value: String(breakWorkInterval))
        AppDatabase.shared.saveSetting(key: "break_duration_mins", value: String(breakDuration))
        AppDatabase.shared.saveSetting(key: "break_long_duration_mins", value: String(breakLongDuration))
        AppDatabase.shared.saveSetting(key: "break_long_frequency", value: String(breakLongFrequency))
        AppDatabase.shared.saveSetting(key: "break_long_enabled", value: breakLongEnabled ? "true" : "false")
        AppDatabase.shared.saveSetting(key: "break_background_hex", value: colorToHex(breakBackgroundColor))
        AppDatabase.shared.saveSetting(key: "break_background_image_path", value: breakBackgroundImagePath)
        AppDatabase.shared.saveSetting(key: "calendar_sync_enabled", value: calendarSyncEnabled ? "true" : "false")
        if breakEnabledToday {
            AppDatabase.shared.saveSetting(key: "break_disabled_day", value: "")
        } else {
            let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
            AppDatabase.shared.saveSetting(key: "break_disabled_day", value: todayStr)
        }
        BreakScheduler.shared.refreshConfig()

        appState.afkThresholdSecs = afkMinutes * 60
        NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        saveStatus = "Saved ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = nil }
    }

    private func pickObsidianVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择 Obsidian Vault 根目录"
        if panel.runModal() == .OK, let url = panel.url {
            obsidianVaultPath = url.path
        }
    }

    private func importObsidianNow() {
        AppDatabase.shared.saveSetting(key: "obsidian_vault_path", value: obsidianVaultPath)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let count = try ObsidianImporter.shared.importToday()
                DispatchQueue.main.async {
                    obsidianImportStatus = "导入 \(count) 条活动 ✓"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        obsidianImportStatus = nil
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    obsidianImportStatus = "失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func toggleAutostart(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() }
            else       { try SMAppService.mainApp.unregister() }
        } catch {
            print("[Autostart] Failed: \(error)")
            autostartEnabled = !enable
        }
    }

    private static func defaultAutoSummaryTime() -> Date {
        var comps = DateComponents()
        comps.hour = 23
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private static func parseTimeOfDay(hour: String?, minute: String?) -> Date {
        var comps = DateComponents()
        comps.hour = Int(hour ?? "23") ?? 23
        comps.minute = Int(minute ?? "0") ?? 0
        return Calendar.current.date(from: comps) ?? defaultAutoSummaryTime()
    }

    private func triggerTestBreak() {
        let now = Date()
        let startTs = Int64(now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000)
        let endTs   = Int64(now.timeIntervalSince1970 * 1000)
        
        NotificationCenter.default.post(
            name: .breakShouldStart,
            object: nil,
            userInfo: [
                "startTs": startTs,
                "endTs": endTs,
                "durationSecs": Double(3600),
                "canPostpone": true,
                "isLongBreak": false,
                "durationMins": 5,
                "sessionIndex": 1,
                "totalSessions": 4
            ]
        )
    }

    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        
        if panel.runModal() == .OK, let url = panel.url {
            copyBackgroundImage(from: url)
        }
    }
    
    private func copyBackgroundImage(from source: URL) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let backgroundsDir = appSupport.appendingPathComponent("Seedo/backgrounds")
        
        do {
            try FileManager.default.createDirectory(at: backgroundsDir, withIntermediateDirectories: true)
            let ext = source.pathExtension
            let destination = backgroundsDir.appendingPathComponent("custom_bg.\(ext)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            self.breakBackgroundImagePath = destination.path
            saveSettings()
            BreakScheduler.shared.refreshConfig()
        } catch {
            print("[Settings] Failed to copy background image: \(error)")
        }
    }
    
    private func clearBackgroundImage() {
        if !breakBackgroundImagePath.isEmpty {
            try? FileManager.default.removeItem(atPath: breakBackgroundImagePath)
            breakBackgroundImagePath = ""
            saveSettings()
            BreakScheduler.shared.refreshConfig()
        }
    }
    
    // MARK: - Category Management
    
    private func refreshCategories() {
        categories = SessionCategory.all
    }
    
    private func addCategory() {
        var new = SessionCategory(id: UUID().uuidString, name: "新分类", colorHex: "#4A90D9", displayOrder: categories.count)
        do {
            try AppDatabase.shared.write { db in
                try new.insert(db)
            }
            refreshCategories()
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        } catch { print("Failed to add category: \(error)") }
    }
    
    private func saveCategory(_ cat: SessionCategory) {
        var mutableCat = cat
        do {
            try AppDatabase.shared.write { db in
                try mutableCat.update(db)
            }
            refreshCategories()
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        } catch { print("Failed to save category: \(error)") }
    }
    
    private func updateCategoryColor(id: String, newHex: String) {
        guard var cat = categories.first(where: { $0.id == id }) else { return }
        // We need a way to set colorHex which is private. Actually I should make it internal or use a helper.
        // For now, I'll just re-init or use a specialized update.
        let updated = SessionCategory(id: cat.id, name: cat.name, colorHex: newHex, displayOrder: cat.displayOrder)
        saveCategory(updated)
    }
    
    private func deleteCategory(_ cat: SessionCategory) {
        do {
            try AppDatabase.shared.write { db in
                try cat.delete(db)
            }
            refreshCategories()
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        } catch { print("Failed to delete category: \(error)") }
    }
    
    private func moveCategories(from: IndexSet, to: Int) {
        var updated = categories
        updated.move(fromOffsets: from, toOffset: to)
        for i in 0..<updated.count {
            updated[i].displayOrder = i
        }
        do {
            try AppDatabase.shared.write { db in
                for cat in updated {
                    try cat.update(db)
                }
            }
            refreshCategories()
            NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        } catch { print("Failed to move categories: \(error)") }
    }
}
