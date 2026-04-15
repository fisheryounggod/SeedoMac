// SeedoMac/Views/Dashboard/SettingsView.swift
import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var baseURL: String = "https://api.openai.com/v1"
    @State private var model: String = "gpt-4o-mini"
    @State private var provider: String = "openai"
    @State private var afkMinutes: Double = 15
    @State private var autostartEnabled = false
    @State private var apiKeyMasked = true
    @State private var saveStatus: String? = nil

    // Stats exclusion section
    @State private var allCategories: [Category] = []

    // Obsidian import section
    @State private var obsidianVaultPath: String = ""
    @State private var obsidianAutoImport: Bool = false
    @State private var obsidianImportStatus: String? = nil

    // Auto daily AI summary
    @State private var autoSummaryEnabled: Bool = false
    @State private var autoSummaryTime: Date = SettingsView.defaultAutoSummaryTime()

    private let providers = [
        ("openai",   "OpenAI",   "https://api.openai.com/v1"),
        ("deepseek", "DeepSeek", "https://api.deepseek.com/v1"),
        ("custom",   "Custom",   ""),
    ]

    var body: some View {
        Form {
            // AI Config
            Section("AI Configuration") {
                Picker("Provider", selection: $provider) {
                    ForEach(providers, id: \.0) { p in Text(p.1).tag(p.0) }
                }
                .onChange(of: provider) { newProvider in
                    if let preset = providers.first(where: { $0.0 == newProvider }), !preset.2.isEmpty {
                        baseURL = preset.2
                    }
                }

                if provider == "custom" {
                    TextField("Base URL", text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    if apiKeyMasked {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(apiKeyMasked ? "Show" : "Hide") { apiKeyMasked.toggle() }
                        .buttonStyle(.borderless)
                }
            }

            // Auto daily AI summary — triggers AIService.generateSummary for
            // today + persists silently at the configured time.
            Section("自动日度 AI 总结") {
                Toggle("每日自动生成今日 AI 总结", isOn: $autoSummaryEnabled)

                if autoSummaryEnabled {
                    HStack {
                        Text("触发时间")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        DatePicker("",
                                   selection: $autoSummaryTime,
                                   displayedComponents: [.hourAndMinute])
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        Spacer()
                    }
                    Text("每天在指定时间用今日数据生成 AI 总结，并自动保存到日志。无需确认。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Tracking
            Section("Tracking") {
                VStack(alignment: .leading) {
                    Text("AFK Threshold: \(Int(afkMinutes)) minutes")
                    Slider(value: $afkMinutes, in: 5...60, step: 1)
                }

                Toggle("Redact Window Titles (Privacy)", isOn: $appState.isRedactTitles)
            }

            // Obsidian daily-note import — parses ` - HH:MM label` lines from
            // {vault}/sources/diarys/{yyyyMMdd}.md into offline_activities.
            Section("Obsidian 日记导入") {
                HStack {
                    TextField("Vault 路径", text: $obsidianVaultPath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    Button("选择…") { pickObsidianVault() }
                }
                Text("文件路径: {vault}/sources/diarys/{yyyyMMdd}.md")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("启动时 & 每小时自动导入今天的日记",
                       isOn: $obsidianAutoImport)

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

            // Stats exclusion section — overview of which categories are
            // counted in statistics. Mirrors the per-category toggle in
            // CategoryView; single source of truth is Category.include_in_stats.
            Section("Stats 排除分类") {
                Text("关闭的分类不会计入统计和 Top Apps — 适合后台系统类分类。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if allCategories.isEmpty {
                    Text("尚未定义任何分类")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allCategories) { cat in
                        Toggle(isOn: Binding(
                            get: { cat.includeInStats },
                            set: { newVal in toggleCategoryInclude(cat, include: newVal) }
                        )) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: cat.color))
                                    .frame(width: 10, height: 10)
                                Text(cat.name)
                            }
                        }
                    }
                }
            }

            // System
            Section("System") {
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

                Button("Open Logs Folder") {
                    let logDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Logs/SeedoMac")
                    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(logDir)
                }
            }

            // Save button
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
            loadAllCategories()
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
        // Infer provider from loaded URL
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
        appState.afkThresholdSecs = afkMinutes * 60
        NotificationCenter.default.post(name: .settingsDidSave, object: nil)
        saveStatus = "Saved ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = nil }
    }

    // MARK: - Obsidian import

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
        // Persist the currently typed vault path first — importer reads from
        // settings, not local @State.
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

    // MARK: - Stats exclusion

    private func loadAllCategories() {
        DispatchQueue.global(qos: .userInitiated).async {
            let cats = (try? CategoryStore().allCategories()) ?? []
            DispatchQueue.main.async { allCategories = cats }
        }
    }

    /// Flips a category's `includeInStats` flag and persists. Local state is
    /// updated on the main thread so the toggle reflects immediately without
    /// waiting for a full reload.
    private func toggleCategoryInclude(_ cat: Category, include: Bool) {
        var updated = cat
        updated.includeInStats = include
        DispatchQueue.global(qos: .userInitiated).async {
            try? CategoryStore().save(updated)
            DispatchQueue.main.async {
                if let idx = allCategories.firstIndex(where: { $0.id == cat.id }) {
                    allCategories[idx].includeInStats = include
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
            autostartEnabled = !enable  // revert on failure
        }
    }

    // MARK: - Auto summary time helpers

    /// Default trigger time when no value has been saved (23:00 — end of day).
    private static func defaultAutoSummaryTime() -> Date {
        var comps = DateComponents()
        comps.hour = 23
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Builds a `Date` from persisted hour/minute strings so SwiftUI's
    /// DatePicker has something to bind to. Date portion is today (irrelevant
    /// — only the time component is used).
    private static func parseTimeOfDay(hour: String?, minute: String?) -> Date {
        var comps = DateComponents()
        comps.hour = Int(hour ?? "23") ?? 23
        comps.minute = Int(minute ?? "0") ?? 0
        return Calendar.current.date(from: comps) ?? defaultAutoSummaryTime()
    }
}
