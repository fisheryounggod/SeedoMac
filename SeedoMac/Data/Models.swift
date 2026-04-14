// SeedoMac/Data/Models.swift
import Foundation
import GRDB

// MARK: - Event

struct Event: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var source: String = "desktop"
    var startTs: Int64       // Unix ms
    var endTs: Int64         // Unix ms
    var appOrDomain: String
    var bundleId: String?
    var title: String = ""
    var url: String?
    var path: String?
    var pageType: String?
    var isRedacted: Bool = false

    static let databaseTableName = "events"

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case startTs      = "start_ts"
        case endTs        = "end_ts"
        case appOrDomain  = "app_or_domain"
        case bundleId     = "bundle_id"
        case title
        case url
        case path
        case pageType     = "page_type"
        case isRedacted   = "is_redacted"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var durationMs: Int64 { max(0, endTs - startTs) }
    var durationSecs: Double { Double(durationMs) / 1000.0 }
}

// MARK: - Category

struct Category: Identifiable, Codable, Hashable, Equatable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
    var color: String = "#4A90D9"
    var rules: String = "[]"  // JSON: [{field: String, op: String, value: String}]
    var includeInStats: Bool = true

    static let databaseTableName = "categories"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case rules
        case includeInStats = "include_in_stats"
    }
}

struct CategoryRule: Codable, FetchableRecord, PersistableRecord {
    var appOrDomain: String
    var categoryId: String

    static let databaseTableName = "category_rules"

    enum CodingKeys: String, CodingKey {
        case appOrDomain  = "app_or_domain"
        case categoryId   = "category_id"
    }
}

// MARK: - Offline Activity

struct OfflineActivity: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var startTs: Int64
    var durationSecs: Int64
    var label: String
    var tagId: String?
    var createdAt: Int64

    static let databaseTableName = "offline_activities"

    enum CodingKeys: String, CodingKey {
        case id
        case startTs      = "start_ts"
        case durationSecs = "duration_secs"
        case label
        case tagId        = "tag_id"
        case createdAt    = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Daily Summary

struct DailySummary: Codable, FetchableRecord, PersistableRecord {
    var date: String       // YYYY-MM-DD (primary key)
    var content: String = ""
    var score: Int = 0
    var keywords: String = ""   // comma-separated
    var createdAt: Int64

    static let databaseTableName = "daily_summaries"

    enum CodingKeys: String, CodingKey {
        case date
        case content
        case score
        case keywords
        case createdAt = "created_at"
    }
}

// MARK: - App Setting (KV store)

struct AppSetting: Codable, FetchableRecord, PersistableRecord {
    var key: String
    var value: String

    static let databaseTableName = "settings"
}

// MARK: - View Models (not persisted)

struct CategoryStat: Identifiable {
    var id: String   // category id
    var name: String
    var color: String
    var totalSecs: Double
}

struct AppStat: Identifiable {
    var id: String { appOrDomain }
    var appOrDomain: String
    var totalSecs: Double
}

struct HeatmapDay: Identifiable {
    var id: String { date }
    var date: String        // YYYY-MM-DD
    var totalSecs: Double
    var weekIndex: Int      // 0-based week column in the year grid
    var weekdayIndex: Int   // 0=Mon … 6=Sun
}

// MARK: - Shared Helpers

/// Formats a duration in seconds to "Xh Ym" or "Ym" string.
func formatDuration(_ secs: Double) -> String {
    let h = Int(secs) / 3600
    let m = (Int(secs) % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
