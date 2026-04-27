// Seedo/AI/AIService.swift
import Foundation

private let systemPrompt = """
你是效能复盘专家。根据用户数据生成深度工作复盘报告。严格用 Markdown 输出，不解释，不废话：
  ## 工具磨刀时间
  量化非核心行为耗时

  ## 核心产出时间
  量化核心目标产出

  ## 效能比率
  核心时间占比 + 一句评价

  ## 效能痛点
  列出主要低效原因

  ## 目标进度
  ✅/❌ 对比计划完成度

  ## 明日前三专注块
  09:00-10:30 | 90m | 任务名（最小阻力原则）
  ---
SCORE: X
KEYWORDS: 关键字1, 关键字2, 关键字3
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
你是效能复盘专家。根据用户数据生成深度工作复盘报告。严格用 Markdown 输出，不解释，不废话：
  ## 工具磨刀时间
  量化非核心行为耗时

  ## 核心产出时间
  量化核心目标产出

  ## 效能比率
  核心时间占比 + 一句评价

  ## 效能痛点
  列出主要低效原因

  ## 目标进度
  ✅/❌ 对比计划完成度

  ## 明日前三专注块
  09:00-10:30 | 90m | 任务名（最小阻力原则）
  ---
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

    /// Generates Top 3 prioritized tasks based on context.
    func generateCoachTasks(
        context: SummaryContext,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            completion(.failure(AIError.noAPIKey))
            return
        }

        let systemPrompt = """
        你是效能教练。你的任务是分析用户的长期愿景、月度计划、今日目标以及当下的实际执行情况，为用户生成当下最值得投入的 Top 3 任务。原则：最小阻力、核心产出、直击执行痛点。
        规则：
        1. 必须针对性强，能直击当前的执行痛点。
        2. 任务描述要具体、可操作。
        3. 请严格按照以下格式输出 3 个任务，控制字数5~8个汉字，不要解释，每个任务一行：
        TASK: 任务描述1
        TASK: 任务描述2
        TASK: 任务描述3
        """
        
        let userContent = buildPrompt(context: context, periodLabel: "当前执行力分析")
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
        request.timeoutInterval = 30

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
            
            let tasks = self.parseCoachTasks(content: content)
            completion(.success(tasks))
        }.resume()
    }

    private func parseCoachTasks(content: String) -> [String] {
        var tasks: [String] = []
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("TASK:") {
                let task = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !task.isEmpty {
                    tasks.append(task)
                }
            }
        }
        return Array(tasks.prefix(3))
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
