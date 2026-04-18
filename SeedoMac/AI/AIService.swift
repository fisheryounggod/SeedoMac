// SeedoMac/AI/AIService.swift
import Foundation

private let systemPrompt = """
你是一位严谨的个人效能教练。
任务：请根据我提供的时间统计数据和目标计划，生成一份“深度工作复盘报告”。

要求及输出格式：
1. **工具磨刀时间（非核心产出）**：量化计算非生产性行为（社交、杂务等）。
2. **核心产出时间**：量化计算与核心目标相关的行为。
3. **效能比率**：计算核心产出占总时长的比例，并给出改进建议。
4. **痛点发现**：识别碎片化、工具沉迷、无效维护等效能杀手。
5. **明明日前三专注块建议**：基于最小阻力原则，给出具体的时间块与任务建议。

请确保回复专业、透彻、直击痛点。
在回复的最后，请严格按照以下格式提供评分和关键词，以便系统解析：
SCORE: X (1-5分)
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

        let systemPrompt = """
你正在为寻求极致效能的专业人士提供工作复盘。
请根据数据生成一份“深度工作复盘报告”，包含以下模块，并使用 Markdown 格式：

- **工具磨刀时间（非核心产出）**：量化低效能行为。
- **核心产出时间**：量化核心目标产出。
- **效能比率**：核心时间占比及评价。
- **效能痛点**：如碎片化过高、工具沉迷、无效维护等。
- **目标进度**：对比计划，列举完成度（使用 ✅/❌ 引导）。
- **明日前三专注块建议（最小阻力原则）**：给出具体的时间点、时长和任务（如 09:00-10:30 | 90m | 任务名）。

规则：
1. 语气严谨、专业、不啰嗦。
2. 最后务必附带以下解析行：
SCORE: X
KEYWORDS: 关键字1, 关键字2, 关键字3
"""
        let userContent = buildPrompt(context: context, periodLabel: periodLabel)
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userContent],
            ]
        ]
        
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

        // Robust parsing for SCORE: X and KEYWORDS: ...
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SCORE:") {
                let val = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                score = Int(val) ?? 0
            } else if trimmed.hasPrefix("KEYWORDS:") {
                keywords = trimmed.dropFirst(9).trimmingCharacters(in: .whitespaces)
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
