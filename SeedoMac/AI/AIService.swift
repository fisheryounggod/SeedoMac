// SeedoMac/AI/AIService.swift
import Foundation

private let systemPrompt = """
你是一位极致效率教练。根据用户提供的电脑使用数据、专注会话记录、离线活动日志以及设定的目标计划，生成一份专业的工作复盘（300字以内）。

重点分析：
1. **现状亮点**：基于数字和离线日志的专注成果。
2. **目标校准 (Target Calibration)**：对比设定的日/月/年计划，量化分析当前的进度偏差或达成情况。必须引用计划内容并指出计划与实际的 Gap（差距）。
3. **优化建议**：基于当前时间分配问题，输出下一步的具体改进策略。

最后给出 1-5 分的评分和 3 个关键词，格式必须严格如下（位于回复最后）：
SCORE: X
KEYWORDS: 关键词1, 关键词2, 关键词3
"""

final class AIService {
    static let shared = AIService()
    private init() {}

    private var baseURL: String {
        AppDatabase.shared.setting(for: "ai_base_url") ?? "https://api.openai.com/v1"
    }
    private var model: String {
        AppDatabase.shared.setting(for: "ai_model") ?? "gpt-4o-mini"
    }

    /// Generates a summary for the given period (does NOT persist).
    func generateSummary(
        context: SummaryContext,
        periodLabel: String,
        completion: @escaping (Result<DailySummary, Error>) -> Void
    ) {
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            completion(.failure(AIError.noAPIKey))
            return
        }

        let userContent = buildPrompt(context: context, periodLabel: periodLabel)
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userContent],
            ]
        ]
        
        // ... rest of network logic remains same ...
        guard let url = URL(string: "\(baseURL)/chat/completions"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(AIError.invalidConfig))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error)); return
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(.failure(AIError.badResponse)); return
            }
            let summary = self.parseSummary(date: context.dateRange, content: content)
            completion(.success(summary))
        }.resume()
    }

    /// Persists a summary (overwriting any existing row with the same date/periodKey)
    /// and posts `.dailySummaryDidSave` so the Log view can refresh.
    func persistSummary(_ summary: DailySummary) throws {
        try WorkSessionStore().saveSummary(summary)
        NotificationCenter.default.post(name: .dailySummaryDidSave, object: nil)
    }

    // MARK: - Helpers

    private func buildPrompt(context: SummaryContext, periodLabel: String) -> String {
        var lines = ["时间范围：\(periodLabel)", ""]
        
        // 1. Digital Activity (All-app baseline)
        let totalSecs = context.topApps.reduce(0) { $0 + $1.totalSecs }
        let h = Int(totalSecs) / 3600
        let m = (Int(totalSecs) % 3600) / 60
        lines += ["# 基础电脑统计", "记录时长：\(h)h \(m)m"]
        
        lines += ["", "核心应用使用时长："]
        for (i, app) in context.topApps.prefix(12).enumerated() {
            let ah = Int(app.totalSecs) / 3600
            let am = (Int(app.totalSecs) % 3600) / 60
            lines.append("\(i+1). \(app.appOrDomain) - \(ah)h \(am)m")
        }

        // 2. Focused Work Sessions (Unified Auto + Manual)
        if !context.workSessions.isEmpty {
            lines += ["", "# 工作实绩 (专注会话 & 手动记录)", "共计：\(context.workSessions.count) 段"]
            for ws in context.workSessions.sorted(by: { $0.startTs < $1.startTs }) {
                let start = Date(timeIntervalSince1970: Double(ws.startTs) / 1000)
                let timeStr = AIService.timeFormatter.string(from: start)
                let typePrefix = ws.isManual ? "[手动]" : "[自动]"
                // v1.3.9+: ws.summary is title, ws.title is note
                let label = ws.summary.isEmpty ? (ws.title.isEmpty ? "未记录活动" : ws.title) : ws.summary
                lines.append("- \(typePrefix) \(timeStr) | \(Int(ws.durationSecs/60))m | \(label)")
                
                if !ws.summary.isEmpty && !ws.title.isEmpty {
                    lines.append("  背景/备注：\(ws.title)")
                }
            }
        }

        // 3. Goals/Plans Alignment
        if context.planDaily != nil || context.planMonthly != nil || context.planYearly != nil {
            lines += ["", "# 目标对齐 (Target Goals)", "请结合以下设定的目标评估："]
            if let d = context.planDaily, !d.isEmpty { lines.append("- 今日任务: \(d)") }
            if let m = context.planMonthly, !m.isEmpty { lines.append("- 本阶段计划: \(m)") }
            if let y = context.planYearly, !y.isEmpty { lines.append("- 长期愿景: \(y)") }
        }

        return lines.joined(separator: "\n")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func parseSummary(date: String, content: String) -> DailySummary {
        var score = 0
        var keywords = ""
        var bodyLines: [String] = []

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("SCORE:") {
                score = Int(line.dropFirst(6).trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.hasPrefix("KEYWORDS:") {
                keywords = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
            } else {
                bodyLines.append(line)
            }
        }

        return DailySummary(
            date: date,
            content: bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            score: min(5, max(0, score)),
            keywords: keywords,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
    }
}

extension Notification.Name {
    static let dailySummaryDidSave = Notification.Name("tech.seedo.dailySummaryDidSave")
    static let settingsDidSave     = Notification.Name("tech.seedo.settingsDidSave")
}

enum AIError: LocalizedError {
    case noAPIKey, invalidConfig, badResponse
    var errorDescription: String? {
        switch self {
        case .noAPIKey:      return "API Key not configured. Go to Settings to add one."
        case .invalidConfig: return "Invalid AI configuration."
        case .badResponse:   return "AI returned an unexpected response."
        }
    }
}
