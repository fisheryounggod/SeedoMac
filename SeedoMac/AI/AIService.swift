// SeedoMac/AI/AIService.swift
import Foundation

private let systemPrompt = """
你是一位专注效率教练。根据用户提供的某一时间段（今天、本周、本月、本年或自定义区间）的电脑使用数据，生成一份简洁的工作复盘（200字以内）。
包含：1）该时段的专注亮点；2）时间分配问题；3）一个具体改进建议。
最后给出该时段的专注评分（1-5分）和3个关键词，格式（必须在回复最后）：
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

    /// Generates a summary for the given period (does NOT persist). Caller decides whether
    /// to save via `persistSummary(_:)` — this enables the "Save to Log?" confirmation prompt.
    func generateSummary(
        periodKey: String,
        periodLabel: String,
        apps: [AppStat],
        categories: [CategoryStat],
        totalSecs: Double,
        completion: @escaping (Result<DailySummary, Error>) -> Void
    ) {
        guard let apiKey = KeychainHelper.loadAPIKey(), !apiKey.isEmpty else {
            completion(.failure(AIError.noAPIKey))
            return
        }

        let userContent = buildPrompt(
            periodLabel: periodLabel,
            apps: apps, categories: categories, totalSecs: totalSecs
        )
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
            let summary = self.parseSummary(date: periodKey, content: content)
            completion(.success(summary))
        }.resume()
    }

    /// Persists a summary (overwriting any existing row with the same date/periodKey)
    /// and posts `.dailySummaryDidSave` so the Log view can refresh.
    func persistSummary(_ summary: DailySummary) throws {
        try OfflineStore().saveSummary(summary)
        NotificationCenter.default.post(name: .dailySummaryDidSave, object: nil)
    }

    // MARK: - Helpers

    private func buildPrompt(periodLabel: String, apps: [AppStat], categories: [CategoryStat], totalSecs: Double) -> String {
        let h = Int(totalSecs) / 3600
        let m = (Int(totalSecs) % 3600) / 60
        var lines = ["时间范围：\(periodLabel)", "总使用时长：\(h)h \(m)m", "", "按分类："]
        for cat in categories {
            let pct = totalSecs > 0 ? Int(cat.totalSecs / totalSecs * 100) : 0
            let ch = Int(cat.totalSecs) / 3600
            let cm = (Int(cat.totalSecs) % 3600) / 60
            lines.append("- \(cat.name)：\(ch)h \(cm)m（\(pct)%）")
        }
        lines += ["", "Top 应用："]
        for (i, app) in apps.prefix(10).enumerated() {
            let ah = Int(app.totalSecs) / 3600
            let am = (Int(app.totalSecs) % 3600) / 60
            lines.append("\(i+1). \(app.appOrDomain) - \(ah)h \(am)m")
        }
        return lines.joined(separator: "\n")
    }

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
