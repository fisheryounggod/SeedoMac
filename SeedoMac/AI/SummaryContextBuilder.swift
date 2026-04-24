// Seedo/AI/SummaryContextBuilder.swift
import Foundation

final class SummaryContextBuilder {
    private let eventStore = EventStore()
    private let workStore = WorkSessionStore()

    /// Builds a full context for the given date (YYYY-MM-DD) or range (YYYY-MM-DD..YYYY-MM-DD).
    func build(for dateStr: String) throws -> SummaryContext {
        let (startMs, endMs) = try parseDateRange(dateStr)
        
        let topApps = (try? eventStore.topApps(startMs: startMs, endMs: endMs, limit: 20)) ?? []
        let sessions = (try? workStore.sessions(from: startMs, to: endMs)) ?? []
        
        // Fetch plans (Daily, Monthly, Yearly)
        let startDate = Date(timeIntervalSince1970: Double(startMs) / 1000)
        let fDaily = DateFormatter(); fDaily.dateFormat = "yyyy-MM-dd"; fDaily.locale = Locale(identifier: "en_US_POSIX")
        let fMonthly = DateFormatter(); fMonthly.dateFormat = "yyyy-MM"; fMonthly.locale = Locale(identifier: "en_US_POSIX")
        let fYearly = DateFormatter(); fYearly.dateFormat = "yyyy"; fYearly.locale = Locale(identifier: "en_US_POSIX")
        
        let dKey = "plan_daily:\(fDaily.string(from: startDate))"
        let mKey = "plan_monthly:\(fMonthly.string(from: startDate))"
        let yKey = "plan_yearly:\(fYearly.string(from: startDate))"
        
        return SummaryContext(
            dateRange: dateStr,
            topApps: topApps,
            workSessions: sessions,
            planDaily: AppDatabase.shared.setting(for: dKey),
            planMonthly: AppDatabase.shared.setting(for: mKey),
            planYearly: AppDatabase.shared.setting(for: yKey)
        )
    }

    private func parseDateRange(_ dateStr: String) throws -> (Int64, Int64) {
        let parts = dateStr.components(separatedBy: "..")
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        
        if parts.count == 2, let s = f.date(from: parts[0]), let e = f.date(from: parts[1]) {
            let start = Int64(s.timeIntervalSince1970 * 1000)
            let end = Int64(e.timeIntervalSince1970 * 1000) + 86_400_000
            return (start, end)
        } else if let d = f.date(from: dateStr) {
            let start = Int64(d.timeIntervalSince1970 * 1000)
            return (start, start + 86_400_000)
        }
        throw ContextError.invalidDate(dateStr)
    }

    enum ContextError: Error {
        case invalidDate(String)
    }
}
