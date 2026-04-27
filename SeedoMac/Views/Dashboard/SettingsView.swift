// Seedo/Views/Dashboard/SettingsView.swift
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
    @State private var obsidianImportRegex: String = ""
    @State private var obsidianExportSessions: Bool = false
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
    @State private var topAppsLimit: Int = 10
    @State private var appearance: String = "system"
    @State private var enableMacFocusMode: Bool = false
    @State private var autoExportEnabled: Bool = false
    @State private var autoExportInterval: Int = 24
    @State private var autoExportPath: String = ""
    @State private var saveStatus: String? = nil

    private let providers: [(String, String, String)] = [
        ("openai", "OpenAI", "https://api.openai.com/v1"),
        ("deepseek", "DeepSeek", "https://api.deepseek.com"),
        ("anthropic", "Anthropic", "https://api.anthropic.com/v1"),
        ("custom", "Custom", "")
    ]

    var body: some View {
        Form {
            // 1. Core Focus Settings
            Section("通用设置") {
                Toggle("开机自启", isOn: $autostartEnabled)
                    .onChange(of: autostartEnabled) { toggleAutostart($0) }
                
                Toggle("今日启用休息提醒", isOn: $breakEnabledToday)
                    .onChange(of: breakEnabledToday) { _ in
                        saveSettings()
                    }

                Toggle("开启专注时同步系统专注模式 (DND)", isOn: $enableMacFocusMode)
                    .help("在专注时间（包含 Deep Focus）自动打开系统勿扰模式，并在休息时间自动恢复")

                HStack {
                    Text("专注间隔 / 分")
                    Spacer()
                    TextField("", value: $breakWorkInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Stepper("", value: $breakWorkInterval, in: 5...240, step: 5)
                }

                HStack {
                    Text("短休息时长 / 分")
                    Spacer()
                    TextField("", value: $breakDuration, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    Stepper("", value: $breakDuration, in: 1...60, step: 1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("离席判定阈值: \(Int(afkMinutes)) 分钟").font(.caption)
                    Slider(value: $afkMinutes, in: 5...60, step: 1)
                }

                DisclosureGroup("高级循环设置 (Pomodoro)") {
                    VStack(spacing: 12) {
                        Toggle("启用长休息", isOn: $breakLongEnabled)
                        
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
                    }
                    .padding(.vertical, 8)
                }
                
                if !appState.hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text("需授予辅助功能权限以获取窗口标题").font(.caption2)
                        Button("去授权") { WindowInfoProvider.requestPermission() }
                            .buttonStyle(.borderless)
                    }
                }
            }

            // 2. AI & Sync Integrations
            Section("AI 与 外部同步") {
                DisclosureGroup("AI 模型配置") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("供应商", selection: $provider) {
                            ForEach(providers, id: \.0) { p in Text(p.1).tag(p.0) }
                        }
                        .pickerStyle(.segmented)
                        
                        TextField("模型 (Model)", text: $model)
                            .textFieldStyle(.roundedBorder)
                            
                        if provider == "custom" {
                            TextField("接口地址 (Base URL)", text: $baseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        HStack {
                            if apiKeyMasked {
                                SecureField("密钥 (API Key)", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                TextField("密钥 (API Key)", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button(apiKeyMasked ? "显示" : "隐藏") { apiKeyMasked.toggle() }
                                .buttonStyle(.plain)
                                .font(.caption2)
                        }
                        
                        Toggle("复盘定时生成", isOn: $autoSummaryEnabled)
                        if autoSummaryEnabled {
                            DatePicker("执行时间", selection: $autoSummaryTime, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.compact)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                DisclosureGroup("Obsidian 联动") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("库路径", text: $obsidianVaultPath)
                                .textFieldStyle(.roundedBorder).disabled(true)
                            Button("选取") { pickObsidianVault() }
                        }
                        Text("路径格式: {vault}/sources/diarys/{yyyyMMdd}.md").font(.system(size: 9)).foregroundStyle(.secondary)
                        
                        Divider().padding(.vertical, 4)
                        
                        // --- 导入 ---
                        Text("导入设置").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("导入匹配正则").font(.caption).foregroundStyle(.secondary)
                        TextField("", text: $obsidianImportRegex)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Text("捕获组: $1=时, $2=分, $3=内容 | 需含 #log 或 #记录 标签").font(.system(size: 9)).foregroundStyle(.secondary)
                        Toggle("自动导入今日日记", isOn: $obsidianAutoImport)
                        HStack {
                            Button("立即导入") { importObsidianNow() }
                                .disabled(obsidianVaultPath.isEmpty)
                            if let status = obsidianImportStatus {
                                Text(status).font(.caption2).foregroundStyle(.blue)
                            }
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        // --- 导出 ---
                        Text("导出设置").font(.caption.bold()).foregroundStyle(.secondary)
                        Toggle("自动导出专注记录到日记", isOn: $obsidianExportSessions)
                        Text("格式: - HH:mm #seedo Title花了X分钟，summary").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        Text("也可在活动历史右键菜单手动同步单条记录").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Toggle("同步专注记录到系统日历", isOn: $calendarSyncEnabled)
                    .onChange(of: calendarSyncEnabled) { enabled in
                        if enabled {
                            CalendarSyncService.shared.requestAccess { if !$0 { calendarSyncEnabled = false } }
                        }
                    }
                
                if calendarSyncEnabled {
                    Button(action: {
                        CalendarSyncService.shared.forceSyncAll(days: 30)
                        saveStatus = "正在同步过去 30 天记录..."
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { saveStatus = nil }
                    }) {
                        Label("立即同步过去 30 天记录", systemImage: "arrow.clockwise.icloud")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                    .padding(.leading, 20)
                }

                DisclosureGroup("提醒设置") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("使用设备超过 1 小时提醒开启计时", isOn: $appState.isUsageReminderEnabled)
                        if appState.isUsageReminderEnabled {
                            HStack {
                                Text("提醒阈值 (分钟)")
                                Spacer()
                                TextField("", value: $appState.usageReminderThresholdMins, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 50)
                                Stepper("", value: $appState.usageReminderThresholdMins, in: 10...240, step: 5)
                            }
                        }

                        Divider()

                        Toggle("定时提醒 (开启专注)", isOn: $appState.isDailyRemindersEnabled)
                        if appState.isDailyRemindersEnabled {
                            VStack(spacing: 8) {
                                ForEach(Array(appState.dailyReminderTimes.enumerated()), id: \.offset) { index, _ in
                                    HStack {
                                        DatePicker("", selection: $appState.dailyReminderTimes[index], displayedComponents: .hourAndMinute)
                                            .labelsHidden()
                                        Spacer()
                                        Button(action: { appState.dailyReminderTimes.remove(at: index) }) {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Button(action: {
                                    var comps = DateComponents()
                                    comps.hour = 9
                                    comps.minute = 0
                                    let newDate = Calendar.current.date(from: comps) ?? Date()
                                    appState.dailyReminderTimes.append(newDate)
                                }) {
                                    Label("添加提醒时间", systemImage: "plus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            // 3. UI, UX & Privacy
            Section("外观、交互与隐私") {
                DisclosureGroup("休息覆盖层外观") {
                    VStack(spacing: 12) {
                        ColorPicker("背景颜色", selection: $breakBackgroundColor)
                        
                        HStack {
                            Text("背景图片")
                            Spacer()
                            if !breakBackgroundImagePath.isEmpty {
                                Button("清除") { clearBackgroundImage() }.buttonStyle(.plain).foregroundStyle(.red)
                            }
                            Button(breakBackgroundImagePath.isEmpty ? "选择图片" : "更换") { selectBackgroundImage() }
                        }
                        
                        Button("测试覆盖层效果") { triggerTestBreak() }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 8)
                }
                
                DisclosureGroup("全局快捷键") {
                    VStack(spacing: 10) {
                        HStack {
                            Text("开始/暂停专注")
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .startPauseFocus)
                        }
                        HStack {
                            Text("开启专注悬浮窗")
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .togglePureFocus)
                        }
                        HStack {
                            Text("打开设置")
                            Spacer()
                            KeyboardShortcuts.Recorder(for: .openSettings)
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                HStack {
                    Text("热门应用统计数量")
                    Spacer()
                    TextField("", value: $topAppsLimit, format: .number).frame(width: 40).textFieldStyle(.roundedBorder)
                    Stepper("", value: $topAppsLimit, in: 5...30)
                }
                
                Toggle("脱敏窗口标题 (隐私模式)", isOn: $appState.isRedactTitles)
                
                Picker("主题模式", selection: $appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色模式").tag("light")
                    Text("深色模式").tag("dark")
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { newValue in
                    appState.appearance = newValue
                    saveSettings()
                }
            }

            // 4. Data & Logic
            Section("标签与分类管理") {
                DisclosureGroup("管理分类 (\(categories.count))") {
                    VStack(spacing: 8) {
                        ForEach($categories) { $cat in
                            HStack {
                                ColorPicker("", selection: Binding(
                                    get: { cat.color },
                                    set: { updateCategoryColor(id: cat.id, newHex: colorToHex($0)) }
                                )).labelsHidden().frame(width: 30)
                                TextField("名称", text: $cat.name).textFieldStyle(.plain).onSubmit { saveCategory(cat) }
                                Button { deleteCategory(cat) } label: { Image(systemName: "trash").foregroundStyle(.red) }.buttonStyle(.plain)
                            }
                        }
                        .onMove { moveCategories(from: $0, to: $1) }
                        
                        Button(action: addCategory) { Label("添加新分类", systemImage: "plus.circle") }
                            .buttonStyle(.plain).padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
                
                Button("打开日志目录") {
                    let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Seedo")
                    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(logDir)
                }
                .buttonStyle(.link)
                
                DisclosureGroup("数据管理 (备份与恢复)") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("导出所有记录、分类和 AI 总结为 JSON 文件。可用于在不同设备间迁移或作为备份。").font(.caption2).foregroundStyle(.secondary)
                        
                        HStack {
                            Button {
                                DataManagementService.shared.exportData { result in
                                    switch result {
                                    case .success: saveStatus = "导出成功 ✓"
                                    case .failure(let err): saveStatus = "导出失败: \(err.localizedDescription)"
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { saveStatus = nil }
                                }
                            } label: {
                                Label("导出备份 (JSON)", systemImage: "square.and.arrow.up")
                            }
                            
                            Button {
                                DataManagementService.shared.importData { result in
                                    switch result {
                                    case .success(let count): 
                                        saveStatus = "成功导入 \(count) 条记录 ✓"
                                        refreshCategories()
                                    case .failure(let err): saveStatus = "导入失败: \(err.localizedDescription)"
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { saveStatus = nil }
                                }
                            } label: {
                                Label("导入备份 (JSON)", systemImage: "square.and.arrow.down")
                            }
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        Text("定时备份").font(.caption.bold()).foregroundStyle(.secondary)
                        Toggle("启用定时自动备份", isOn: $autoExportEnabled)
                        
                        if autoExportEnabled {
                            HStack {
                                Text("备份频率")
                                Spacer()
                                Picker("", selection: $autoExportInterval) {
                                    Text("每 1 小时").tag(1)
                                    Text("每 6 小时").tag(6)
                                    Text("每 12 小时").tag(12)
                                    Text("每 24 小时").tag(24)
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                            
                            HStack {
                                TextField("备份目录", text: $autoExportPath)
                                    .textFieldStyle(.roundedBorder).disabled(true)
                                Button("选取目录") { pickAutoExportFolder() }
                            }
                            Text("备份文件将以 SeedoAutoBackup_yyyyMMdd_HHmm.json 格式保存").font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            HStack {
                Spacer()
                if let status = saveStatus { Text(status).foregroundStyle(.secondary).font(.caption) }
                Button("保存设置") { saveSettings() }.buttonStyle(.borderedProminent)
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
        let defaultRegex = #"^\s*-\s+(\d{1,2}):(\d{2})\s+(.+?)\s*$"#
        obsidianImportRegex = AppDatabase.shared.setting(for: "obsidian_import_regex") ?? defaultRegex
        obsidianExportSessions = (AppDatabase.shared.setting(for: "obsidian_export_sessions") == "true")
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
        topAppsLimit = Int(AppDatabase.shared.setting(for: "stats_top_apps_limit") ?? "10") ?? 10
        appearance = AppDatabase.shared.setting(for: "appearance") ?? "system"
        appState.appearance = appearance
        
        enableMacFocusMode = AppDatabase.shared.setting(for: "mac_focus_mode_enabled") == "true"
        autoExportEnabled = AppDatabase.shared.setting(for: "auto_export_enabled") == "true"
        autoExportInterval = Int(AppDatabase.shared.setting(for: "auto_export_interval_hours") ?? "24") ?? 24
        autoExportPath = AppDatabase.shared.setting(for: "auto_export_path") ?? ""
        
        appState.isUsageReminderEnabled = AppDatabase.shared.setting(for: "usage_reminder_enabled") == "true"
        appState.usageReminderThresholdMins = Int(AppDatabase.shared.setting(for: "usage_reminder_threshold_mins") ?? "60") ?? 60
        appState.isDailyRemindersEnabled = AppDatabase.shared.setting(for: "daily_reminders_enabled") == "true"
        
        if let timesJson = AppDatabase.shared.setting(for: "daily_reminder_times"),
           let data = timesJson.data(using: .utf8),
           let dates = try? JSONDecoder().decode([Date].self, from: data) {
            appState.dailyReminderTimes = dates
        } else {
            appState.dailyReminderTimes = []
        }

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
        AppDatabase.shared.saveSetting(key: "obsidian_import_regex", value: obsidianImportRegex)
        AppDatabase.shared.saveSetting(key: "obsidian_export_sessions", value: obsidianExportSessions ? "true" : "false")
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
        AppDatabase.shared.saveSetting(key: "stats_top_apps_limit", value: String(topAppsLimit))
        AppDatabase.shared.saveSetting(key: "appearance", value: appearance)
        
        AppDatabase.shared.saveSetting(key: "mac_focus_mode_enabled", value: enableMacFocusMode ? "true" : "false")
        AppDatabase.shared.saveSetting(key: "auto_export_enabled", value: autoExportEnabled ? "true" : "false")
        AppDatabase.shared.saveSetting(key: "auto_export_interval_hours", value: String(autoExportInterval))
        AppDatabase.shared.saveSetting(key: "auto_export_path", value: autoExportPath)
        
        appState.isMacFocusModeEnabled = enableMacFocusMode
        appState.isAutoExportEnabled = autoExportEnabled
        appState.autoExportIntervalHours = autoExportInterval
        appState.autoExportPath = autoExportPath
        
        AppDatabase.shared.saveSetting(key: "usage_reminder_enabled", value: appState.isUsageReminderEnabled ? "true" : "false")
        AppDatabase.shared.saveSetting(key: "usage_reminder_threshold_mins", value: String(appState.usageReminderThresholdMins))
        AppDatabase.shared.saveSetting(key: "daily_reminders_enabled", value: appState.isDailyRemindersEnabled ? "true" : "false")
        if let data = try? JSONEncoder().encode(appState.dailyReminderTimes),
           let json = String(data: data, encoding: .utf8) {
            AppDatabase.shared.saveSetting(key: "daily_reminder_times", value: json)
        }
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

    private func pickAutoExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "选择自动备份保存目录"
        
        if panel.runModal() == .OK, let url = panel.url {
            autoExportPath = url.path
            
            // Create security bookmark for persistence
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                let bookmarkBase64 = bookmarkData.base64EncodedString()
                AppDatabase.shared.saveSetting(key: "auto_export_bookmark", value: bookmarkBase64)
                appState.autoExportBookmark = bookmarkData
            } catch {
                print("[Settings] Failed to create bookmark: \(error)")
            }
        }
    }
}
