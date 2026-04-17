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

// MARK: - Daily Summary

struct DailySummary: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var date: String       // YYYY-MM-DD (primary key)
    var content: String = ""
    var score: Int = 0
    var keywords: String = ""   // comma-separated
    var createdAt: Int64

    // Identifiable — uses PK directly so SwiftUI list/sheet bindings work.
    var id: String { date }

    static let databaseTableName = "daily_summaries"

    enum CodingKeys: String, CodingKey {
        case date
        case content
        case score
        case keywords
        case createdAt = "created_at"
    }
}

// MARK: - Work Session (Added in v3, Updated in v4)

struct WorkSession: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var startTs: Int64
    var endTs: Int64
    var topAppsJson: String     // JSON snapshot of [AppStat]
    var summary: String = ""
    var outcome: String = "completed" // completed | skipped
    var createdAt: Int64
    var isManual: Bool = false
    var title: String = ""
    var categoryId: String? = nil

    static let databaseTableName = "work_sessions"

    enum CodingKeys: String, CodingKey {
        case id
        case startTs   = "start_ts"
        case endTs     = "end_ts"
        case topAppsJson = "top_apps_json"
        case summary
        case outcome
        case createdAt = "created_at"
        case isManual  = "is_manual"
        case title
        case categoryId = "category_id"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var durationSecs: Double { Double(max(0, endTs - startTs)) / 1000.0 }

    /// Decodes the topAppsJson into [AppStat] models.
    var topApps: [AppStat] {
        guard let data = topAppsJson.data(using: .utf8) else { return [] }
        struct RawStat: Codable { let appOrDomain: String; let totalSecs: Double }
        let raw = (try? JSONDecoder().decode([RawStat].self, from: data)) ?? []
        return raw.map { AppStat(appOrDomain: $0.appOrDomain, totalSecs: $0.totalSecs) }
    }
}

// MARK: - App Setting (KV store)

struct AppSetting: Codable, FetchableRecord, PersistableRecord {
    var key: String
    var value: String

    static let databaseTableName = "settings"
}

// MARK: - View Models (not persisted)

// MARK: - Dashboard Navigation

enum DashboardTab: String, CaseIterable {
    case stats    = "Stats"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .stats:    return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var displayName: String {
        switch self {
        case .stats:    return "统计"
        case .settings: return "设置"
        }
    }
}

// MARK: - AI Context

struct SummaryContext {
    var dateRange: String
    var topApps: [AppStat]
    var workSessions: [WorkSession]
    var planDaily: String?
    var planMonthly: String?
    var planYearly: String?
}

struct AppStat: Identifiable, Codable {
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

// MARK: - Category
struct SessionCategory: Identifiable, Hashable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var name: String
    private var colorHex: String
    var displayOrder: Int = 0
    
    var color: Color { Color(hex: colorHex) }
    var hex: String { colorHex }
    
    init(id: String, name: String, colorHex: String, displayOrder: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.displayOrder = displayOrder
    }
    
    static let databaseTableName = "categories"
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case colorHex = "color"
        case displayOrder = "display_order"
    }
    
    static var all: [SessionCategory] {
        (try? AppDatabase.shared.read { db in
            try SessionCategory.order(Column("display_order").asc).fetchAll(db)
        }) ?? []
    }
    
    static func find(_ id: String?) -> SessionCategory {
        all.first { $0.id == id } ?? SessionCategory(id: "none", name: "未分类", colorHex: "#8E8E93", displayOrder: 999)
    }
}

// MARK: - Shared Helpers

import SwiftUI
import AppKit

extension Color {
    init(hex: String) {
        self = hexToColor(hex)
    }
}

func hexToColor(_ hex: String) -> Color {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let r, g, b: Double
    switch hex.count {
    case 3: // RGB (12-bit)
        (r, g, b) = (Double((int >> 8) & 0xF) / 15, Double((int >> 4) & 0xF) / 15, Double(int & 0xF) / 15)
    case 6: // RGB (24-bit)
        (r, g, b) = (Double((int >> 16) & 0xFF) / 255, Double((int >> 8) & 0xFF) / 255, Double(int & 0xFF) / 255)
    default:
        (r, g, b) = (0, 0, 0)
    }
    return Color(red: r, green: g, blue: b)
}

func colorToHex(_ color: Color) -> String {
    let nsColor = NSColor(color)
    guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
        return "#000000"
    }
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    let ir = Int(max(0, min(255, r * 255)))
    let ig = Int(max(0, min(255, g * 255)))
    let ib = Int(max(0, min(255, b * 255)))
    return String(format: "#%02X%02X%02X", ir, ig, ib)
}

/// Formats a duration in seconds to "Xh Ym" or "Ym" string.
func formatDuration(_ secs: Double) -> String {
    let h = Int(secs) / 3600
    let m = (Int(secs) % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
