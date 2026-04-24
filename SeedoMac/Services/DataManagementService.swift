// Seedo/Services/DataManagementService.swift
import Foundation
import AppKit

// MARK: - Export Compatibility Models

struct BackupData: Codable {
    var version: String = "2.0.0"
    var exportDate: Date = Date()
    var workSessions: [ExportWorkSession]
    var dailySummaries: [DailySummary]
    var categories: [SessionCategory]
}

struct ExportWorkSession: Codable {
    let id: String
    let title: String
    let summary: String
    let start_ts: Int64
    let end_ts: Int64
    let created_at: Int64
    let is_manual: Bool
    let outcome: String
    let category_id: String?
}

final class DataManagementService {
    static let shared = DataManagementService()
    private let store = WorkSessionStore()
    
    func exportData(completion: @escaping (Result<URL, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let sessions = try self.store.allSessions()
                let summaries = try self.store.allSummaries()
                let categories = SessionCategory.all
                
                let exportSessions = sessions.map { s in
                    ExportWorkSession(
                        id: String(s.id ?? 0),
                        title: s.summary, // IOS expects summary in "title" key
                        summary: s.title, // IOS expects title in "summary" key
                        start_ts: s.startTs,
                        end_ts: s.endTs,
                        created_at: s.createdAt,
                        is_manual: s.isManual,
                        outcome: s.outcome,
                        category_id: s.categoryId
                    )
                }
                
                let backup = BackupData(
                    workSessions: exportSessions,
                    dailySummaries: summaries,
                    categories: categories
                )
                
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(backup)
                
                DispatchQueue.main.async {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = "SeedoBackup_\(self.dateString(Date())).json"
                    panel.message = "导出 Seedo 数据备份"
                    
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            try data.write(to: url)
                            completion(.success(url))
                        } catch {
                            completion(.failure(error))
                        }
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func importData(completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.message = "选择 Seedo 数据备份文件 (.json)"
            
            if panel.runModal() == .OK, let url = panel.url {
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: url)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        
                        var finalSessions: [WorkSession] = []
                        var sessionCount = 0
                        
                        if let backup = try? decoder.decode(BackupData.self, from: data) {
                            // Handle new BackupData format with swap
                            finalSessions = backup.workSessions.map { es in
                                WorkSession(
                                    id: Int64(es.id),
                                    startTs: es.start_ts,
                                    endTs: es.end_ts,
                                    topAppsJson: "[]",
                                    summary: es.title, // Swap back
                                    outcome: es.outcome,
                                    createdAt: es.created_at,
                                    isManual: es.is_manual,
                                    title: es.summary, // Swap back
                                    categoryId: es.category_id
                                )
                            }
                            
                            // Import categories first (dependency)
                            try self.store.bulkInsertCategories(backup.categories)
                            // Then sessions and summaries
                            try self.store.bulkInsertSessions(finalSessions)
                            try self.store.bulkInsertSummaries(backup.dailySummaries)
                            sessionCount = finalSessions.count
                        } else if let legacySessions = try? decoder.decode([WorkSession].self, from: data) {
                            // Handle legacy [WorkSession] format
                            try self.store.bulkInsertSessions(legacySessions)
                            sessionCount = legacySessions.count
                        }
                        
                        completion(.success(sessionCount))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: date)
    }
}
