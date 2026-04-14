// SeedoMac/Data/CategoryStore.swift
import Foundation
import GRDB

struct CategoryRuleEntry: Codable {
    var field: String   // "app" | "title"
    var op: String      // "contains" | "equals"
    var value: String
}

final class CategoryStore {
    private let db: any DatabaseWriter & DatabaseReader

    convenience init() { self.init(db: AppDatabase.shared.pool) }
    init(db: some DatabaseWriter & DatabaseReader) { self.db = db }

    func allCategories() throws -> [Category] {
        try db.read { d in try Category.fetchAll(d) }
    }

    func save(_ category: Category) throws {
        try db.write { d in try category.save(d) }
    }

    func delete(id: String) throws {
        try db.write { d in
            try Category.deleteOne(d, key: id)
            try d.execute(sql: "DELETE FROM category_rules WHERE category_id = ?", arguments: [id])
        }
    }

    /// Appends an "app equals appName" rule to the given category. No-op if the rule already exists.
    func assignApp(_ appName: String, toCategoryId categoryId: String) throws {
        var cats = try allCategories()
        guard let idx = cats.firstIndex(where: { $0.id == categoryId }) else { return }
        var entries = (try? JSONDecoder().decode([CategoryRuleEntry].self,
                                                 from: Data(cats[idx].rules.utf8))) ?? []
        guard !entries.contains(where: { $0.field == "app" && $0.op == "equals" && $0.value == appName })
        else { return }
        entries.append(CategoryRuleEntry(field: "app", op: "equals", value: appName))
        cats[idx].rules = (try? String(data: JSONEncoder().encode(entries), encoding: .utf8)) ?? "[]"
        try save(cats[idx])
    }

    /// Matches the first category whose rules satisfy (appName, title).
    /// OR logic across rules within a category; categories checked in insertion order.
    func matchCategory(for appName: String, title: String) throws -> Category? {
        let cats = try allCategories()
        let decoder = JSONDecoder()
        for cat in cats {
            guard let data = cat.rules.data(using: .utf8) else { continue }
            let rules: [CategoryRuleEntry]
            do {
                rules = try decoder.decode([CategoryRuleEntry].self, from: data)
            } catch {
                print("[CategoryStore] Failed to decode rules for category '\(cat.id)': \(error)")
                continue
            }
            for rule in rules {
                let target: String
                switch rule.field {
                case "app":   target = appName
                case "title": target = title
                default:      continue
                }
                switch rule.op {
                case "contains":
                    if target.localizedCaseInsensitiveContains(rule.value) { return cat }
                case "equals":
                    if target.caseInsensitiveCompare(rule.value) == .orderedSame { return cat }
                default:
                    continue
                }
            }
        }
        return nil
    }
}
