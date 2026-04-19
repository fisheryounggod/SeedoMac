// SeedoMac/Services/DataManagementService.swift
import Foundation
import AppKit

struct BackupData: Codable {
    var version: String = "2.0.0"
    var exportDate: Date = Date()
    var workSessions: [WorkSession]
    var dailySummaries: [DailySummary]
    var categories: [SessionCategory]
}

final class DataManagementService {
    static let shared = DataManagementService()
    private let store = WorkSessionStore()
    
    func exportData(completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            let backup = BackupData(
                workSessions: try store.allSessions(),
                dailySummaries: try store.allSummaries(),
                categories: try store.allCategories()
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(backup)
            
            DispatchQueue.main.async {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "SeedoBackup_\(self.dateString(Date())).json"
                panel.message = "导出 SeedoMac 数据备份"
                
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
    
    func importData(completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.message = "选择 SeedoMac 数据备份文件 (.json)"
            
            if panel.runModal() == .OK, let url = panel.url {
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let data = try Data(contentsOf: url)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let backup = try decoder.decode(BackupData.self, from: data)
                        
                        // Import categories first (dependency)
                        try self.store.bulkInsertCategories(backup.categories)
                        // Then sessions and summaries
                        try self.store.bulkInsertSessions(backup.workSessions)
                        try self.store.bulkInsertSummaries(backup.dailySummaries)
                        
                        completion(.success(backup.workSessions.count))
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
