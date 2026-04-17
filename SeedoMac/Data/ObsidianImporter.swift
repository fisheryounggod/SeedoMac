// SeedoMac/Data/ObsidianImporter.swift
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
        let label: String
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
        let pattern = #"^\s*-\s+(\d{1,2}):(\d{2})\s+(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        ) else {
            return []
        }

        let cal = Calendar.current
        var dayComps = cal.dateComponents([.year, .month, .day], from: day)

        var raw: [(startTs: Int64, label: String)] = []
        let range = NSRange(content.startIndex..., in: content)
        regex.enumerateMatches(in: content, range: range) { match, _, _ in
            guard let m = match,
                  let hRange = Range(m.range(at: 1), in: content),
                  let mRange = Range(m.range(at: 2), in: content),
                  let lRange = Range(m.range(at: 3), in: content),
                  let hour = Int(content[hRange]),
                  let minute = Int(content[mRange]),
                  (0...23).contains(hour),
                  (0...59).contains(minute) else { return }

            let rawLabel = String(content[lRange]).trimmingCharacters(in: .whitespaces)
            guard Self.hasLogTag(rawLabel) else { return }

            dayComps.hour = hour
            dayComps.minute = minute
            dayComps.second = 0
            guard let date = cal.date(from: dayComps) else { return }

            let cleanLabel = Self.stripLogTag(rawLabel)
            guard !cleanLabel.isEmpty else { return }

            raw.append((Int64(date.timeIntervalSince1970 * 1000), cleanLabel))
        }

        // Sort by timestamp, compute duration = next.startTs - current.startTs
        // (last entry defaults to 30 minutes).
        let sorted = raw.sorted { $0.startTs < $1.startTs }
        var out: [ParsedEntry] = []
        for (i, entry) in sorted.enumerated() {
            let next = (i + 1 < sorted.count)
                ? sorted[i + 1].startTs
                : entry.startTs + 30 * 60 * 1000
            let durSecs = max(0, (next - entry.startTs) / 1000)
            out.append(ParsedEntry(
                startTs: entry.startTs,
                durationSecs: durSecs,
                label: entry.label
            ))
        }
        return out
    }

    private static func hasLogTag(_ label: String) -> Bool {
        let pattern = #"(?i)#log\b|#记录"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(label.startIndex..., in: label)
        return regex.firstMatch(in: label, range: range) != nil
    }

    private static func stripLogTag(_ label: String) -> String {
        var s = label
        if let regex = try? NSRegularExpression(pattern: #"(?i)#log\b"#, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        s = s.replacingOccurrences(of: "#记录", with: "")
        // Collapse whitespace
        let collapsed = s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapsed.trimmingCharacters(in: .whitespaces)
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
                title: entry.label
            )
            try store.insert(&session)
            inserted += 1
        }
        return inserted
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
