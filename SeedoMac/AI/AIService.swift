// SeedoMac/AI/AIService.swift
import Foundation

private let systemPrompt = """
你是一位严谨的个人效能教练。
任务：请根据我提供的时间统计数据和目标计划，生成一份“深度工作复盘报告”。

要求及输出格式：
1. **数据脱水 (Data Dehydration)**：精准区分“工具磨刀时间”与“核心产出时间”，量化计算目标达成率。
2. **偏差诊断 (Gap Diagnosis)**：识别是否存在“低水平勤奋”或“目标偏移”，并直接指出痛点。
3. **行动修正 (Action Correction)**：基于最小阻力原则，给出明天前三个专注块的具体任务建议。
4. **视觉评分 (Visual Scoring)**：根据“目标相关度”而非“忙碌程度”进行 1-5 分评分。

请确保回复简洁有力，直击要害。在回复的最后，请严格按照以下格式提供评分和关键词，以便系统解析：
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

        let systemPrompt = """
你在为一位寻求极致效能的专业人士提供复盘。
请基于数据生成一份结构极其压缩、信息密度极高的“深度工作复盘简报”。

#### 核心规则：
1. **严格限制字数**：每一项内容控制在 15 字以内，严禁完整长句。
2. **必须使用语义 Emoji 引导**（用于触发 UI 颜色渲染）：
   - 🔴 开头：代表痛点、干扰、不达标 (RED)
   - 🟢 开头：代表核心产出、高度专注、达标 (GREEN)
   - 🔵 开头：代表明日动作、修正建议 (BLUE)
   - 🟡 开头：代表洞察、趋势、警告 (ORANGE)
3. **内容结构**：
## 1. 复盘 (Metrics & Gaps)
- 以 🟢 或 🔴 引导数据核心结论。
## 2. 修正 (Actions)
- 以 🔵 引导明天前三个专注块的具体建议。
## 3. 评分 (Score)
- SCORE: X
- KEYWORDS: 词1, 词2, 词3
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
