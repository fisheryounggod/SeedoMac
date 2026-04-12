// SeedoMac/Views/Dashboard/SettingsView.swift
import SwiftUI
import ServiceManagement

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

            // Tracking
            Section("Tracking") {
                VStack(alignment: .leading) {
                    Text("AFK Threshold: \(Int(afkMinutes)) minutes")
                    Slider(value: $afkMinutes, in: 5...60, step: 1)
                }

                Toggle("Redact Window Titles (Privacy)", isOn: $appState.isRedactTitles)
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
        .onAppear { loadSettings() }
    }

    // MARK: - Actions

    private func loadSettings() {
        apiKey = KeychainHelper.loadAPIKey() ?? ""
        baseURL = AppDatabase.shared.setting(for: "ai_base_url") ?? "https://api.openai.com/v1"
        model = AppDatabase.shared.setting(for: "ai_model") ?? "gpt-4o-mini"
        afkMinutes = appState.afkThresholdSecs / 60
        autostartEnabled = (SMAppService.mainApp.status == .enabled)
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
        appState.afkThresholdSecs = afkMinutes * 60
        saveStatus = "Saved ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = nil }
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
}
