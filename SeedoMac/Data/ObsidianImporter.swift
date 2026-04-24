// Seedo/Data/ObsidianImporter.swift
import Foundation
import GRDB

/// Parses today's Obsidian daily note and upserts the parsed ` - HH:MM label`
/// lines as rows in the `offline_activities` table. Designed to be idempotent:
/// re-running on the same day skips rows that already exist (dedup by
/// `(start_ts, label)`).
///
/// Expected daily-note path: `{vault}/sources/diarys/{yyyyMMdd}.md` — matches
/// Fisher's actual vault layout.
final class ObsidianImporter {
    static let shared = ObsidianImporter()
    private init() {}

    /// Parses today's Obsidian daily note and upserts each matching line
    /// into `offline_activities`. Returns the number of NEW activities inserted.
    @discardableResult
    func importToday() throws -> Int {
        guard let vault = AppDatabase.shared.setting(for: "obsidian_vault_path"),
              !vault.isEmpty else {
            throw ImportError.noVault
        }

        let today = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let filename = df.string(from: today) + ".md"

        let fileURL = URL(fileURLWithPath: vault)
            .appendingPathComponent("sources/diarys/\(filename)")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ImportError.fileMissing(fileURL.path)
        }

        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let entries = parseEntries(content, day: today)
        return try upsertActivities(entries)
    }

    // MARK: - Parsing

    struct ParsedEntry: Equatable {
        let startTs: Int64
        let durationSecs: Int64
        let title: String
        let categoryId: String?
    }

    /// Parses ` - HH:MM <label>` lines. Duration = time-to-next-entry (with a
    /// 30-minute default for the last entry of the day).
    ///
    /// Matching rules:
    /// - Line may have leading whitespace and must start with `-`
    /// - HH:MM must be 1–2 digit hour + 2 digit minute
    /// - Label must contain `#log` (case-insensitive) or `#记录`
    /// - Label is everything after the first run of whitespace, with tags stripped
    func parseEntries(_ content: String, day: Date) -> [ParsedEntry] {
        // User's requested pattern: - (\d\d):(\d\d) #log/(\w\w) (.*?)花了(.*?)分钟
        // We use a slightly more flexible version for the category (\w+)
        let defaultPattern = #"^\s*-\s+(\d{1,2}):(\d{2})\s+#log/(\w+)\s+(.*?)\s*花了\s*(\d+)\s*分钟\s*$"#
        let customPattern = AppDatabase.shared.setting(for: "obsidian_import_regex")
        let pattern = (customPattern != nil && !customPattern!.isEmpty) ? customPattern! : defaultPattern
        
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        ) else {
            return []
        }

        let cal = Calendar.current
        var dayComps = cal.dateComponents([.year, .month, .day], from: day)
        let categories = SessionCategory.all

        var out: [ParsedEntry] = []
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let m = match, m.numberOfRanges >= 6 else { return }
            
            guard let hRange = Range(m.range(at: 1), in: content),
                  let mRange = Range(m.range(at: 2), in: content),
                  let catRange = Range(m.range(at: 3), in: content),
                  let titleRange = Range(m.range(at: 4), in: content),
                  let durRange = Range(m.range(at: 5), in: content) else { return }
            
            let hour = Int(content[hRange]) ?? 0
            let minute = Int(content[mRange]) ?? 0
            let categoryName = String(content[catRange]).trimmingCharacters(in: .whitespaces)
            let title = String(content[titleRange]).trimmingCharacters(in: .whitespaces)
            let durationMins = Int(content[durRange]) ?? 30
            
            guard (0...23).contains(hour), (0...59).contains(minute) else { return }

            dayComps.hour = hour
            dayComps.minute = minute
            dayComps.second = 0
            guard let date = cal.date(from: dayComps) else { return }

            let categoryId = categories.first { $0.name == categoryName }?.id
            
            out.append(ParsedEntry(
                startTs: Int64(date.timeIntervalSince1970 * 1000),
                durationSecs: Int64(durationMins * 60),
                title: title,
                categoryId: categoryId
            ))
        }

        return out.sorted { $0.startTs < $1.startTs }
    }



    // MARK: - Upsert

    /// Inserts entries into `work_sessions`, skipping any row that already
    /// exists with the same `(start_ts, is_manual=true)`. Returns count of NEW inserts.
    private func upsertActivities(_ entries: [ParsedEntry]) throws -> Int {
        let store = WorkSessionStore()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        var inserted = 0
        for entry in entries {
            if try existsObsidianActivity(startTs: entry.startTs) {
                continue
            }
            var session = WorkSession(
                startTs: entry.startTs,
                endTs: entry.startTs + entry.durationSecs * 1000,
                topAppsJson: "[]",
                summary: "",
                outcome: "completed",
                createdAt: nowMs,
                isManual: true,
                title: entry.title,
                categoryId: entry.categoryId
            )
            try store.insert(&session)
            inserted += 1
        }
        return inserted
    }

    /// Appends the AI summary to the end of today's Obsidian daily note.
    /// Format: `- HH:mm #work CONTENT`
    func appendSummary(_ content: String) throws {
        guard let vault = AppDatabase.shared.setting(for: "obsidian_vault_path"),
              !vault.isEmpty else {
            return
        }

        let today = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let filename = df.string(from: today) + ".md"

        let fileURL = URL(fileURLWithPath: vault)
            .appendingPathComponent("sources/diarys/\(filename)")

        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        let timeStr = tf.string(from: Date())
        
        let cleanContent = content.replacingOccurrences(of: "\n", with: " ")
        let line = "\n- \(timeStr) #work \(cleanContent)"

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            if let data = (line).data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }

    /// Appends a work session record to today's Obsidian daily note.
    /// Format: `- HH:mm #seedo Title花了X分钟，summary`
    func appendSession(_ session: WorkSession) throws {
        guard let vault = AppDatabase.shared.setting(for: "obsidian_vault_path"),
              !vault.isEmpty else { return }

        // Build file path for the session's start date (not necessarily today)
        let sessionDate = Date(timeIntervalSince1970: Double(session.startTs) / 1000)
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let filename = df.string(from: sessionDate) + ".md"

        let fileURL = URL(fileURLWithPath: vault)
            .appendingPathComponent("sources/diarys/\(filename)")

        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        tf.locale = Locale(identifier: "en_US_POSIX")
        let timeStr = tf.string(from: sessionDate)

        // Format duration
        let totalMins = Int(session.durationSecs) / 60
        let durationStr: String
        if totalMins >= 60 {
            let h = totalMins / 60
            let m = totalMins % 60
            durationStr = m > 0 ? "\(h)小时\(m)分钟" : "\(h)小时"
        } else {
            durationStr = "\(max(1, totalMins))分钟"
        }

        let category = SessionCategory.find(session.categoryId).name.replacingOccurrences(of: " ", with: "")
        let title = session.title.isEmpty ? (session.summary.isEmpty ? "专注" : session.summary) : session.title
        let summary = session.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryPart = summary.isEmpty || summary == title ? "" : summary

        // Format: - HH:mm #seedo/分类 {{summary}}花了{{X}}分钟：{{Title}}
        let line = "\n- \(timeStr) #seedo/\(category) \(summaryPart)花了\(durationStr)：\(title)"

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try line.write(to: fileURL, atomically: true, encoding: .utf8)
        } else {
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
        print("[ObsidianImporter] Appended session to \(filename): \(line.trimmingCharacters(in: .newlines))")
    }

    private func existsObsidianActivity(startTs: Int64) throws -> Bool {
        try AppDatabase.shared.pool.read { d in
            let count = try WorkSession
                .filter(Column("start_ts") == startTs && Column("is_manual") == true)
                .fetchCount(d)
            return count > 0
        }
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case noVault
        case fileMissing(String)

        var errorDescription: String? {
            switch self {
            case .noVault:
                return "Obsidian vault 路径未配置。请到设置里选择。"
            case .fileMissing(let path):
                return "找不到今天的日记文件: \(path)"
            }
        }
    }
}
