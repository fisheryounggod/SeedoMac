// SeedoMac/AI/AIService.swift
// TODO: Full implementation in Task 16
import Foundation

final class AIService {
    static let shared = AIService()
    private init() {}

    func generateDailySummary(
        date: String,
        apps: [AppStat],
        categories: [CategoryStat],
        totalSecs: Double,
        completion: @escaping (Result<DailySummary, Error>) -> Void
    ) {
        completion(.failure(AIError.notConfigured))
    }
}

enum AIError: LocalizedError {
    case notConfigured, noAPIKey, invalidConfig, badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI not configured yet. Add API key in Settings."
        case .noAPIKey:      return "API Key not set. Go to Settings to add one."
        case .invalidConfig: return "Invalid AI configuration."
        case .badResponse:   return "AI returned an unexpected response."
        }
    }
}
