# SeedoMac: Break Reminder & Dashboard Revamp — Design

**Date:** 2026-04-15
**Status:** Design approved, pending implementation plan
**Scope:** 8 changes batched into one release

## Context

Fisher just shipped the previous feature batch (Chinese labels, markdown summaries, Obsidian import, stats exclusions, plan boxes, auto daily AI summary) and wants to roll the next batch with:

1. An Eye Monitor-style break reminder that prompts for a per-session work summary
2. A cleanup of Dashboard structure (fewer top-level tabs, merged Log timeline)
3. Full edit/delete on every journal row type
4. Richer Obsidian filtering (only tagged lines)
5. AI summaries that see the full context (events + activities + work sessions + plans)
6. The missing app icon

All eight items ship together so the Dashboard structure only changes once and `work_sessions` lands in its final home on first appearance.

## Goals

- **Behavioral goal:** Fisher takes a real break every 25 min, writes a one-line summary of what he just did, and can skip gracefully when a break is inconvenient.
- **Data goal:** Every meaningful time-related record (tracked events, manual activities, Obsidian activities, work sessions, daily plans) is visible on the Log timeline and available to the AI summarizer.
- **Structural goal:** Dashboard has 3 top-level tabs (统计 / 日志 / 设置), Log has one unified timeline view, Settings is the single source of truth for all configuration.

## Non-goals

- Multi-monitor break overlay (main screen only in this release)
- CommonMark block-level rendering in summaries (still inline-only via `AttributedString`)
- Range-key PK collision handling for weekly/monthly summaries (known issue, deferred)
- Configurable Obsidian daily-note template (stays hard-coded as `{vault}/sources/diarys/{yyyyMMdd}.md`)
- Obsidian source-file round-trip (deleting a SeedoMac row does NOT modify the Obsidian file)

---

## Scope Summary

| # | Item | Status |
|---|---|---|
| 0 | Duration input fix in add-activity form | Already shipped as `a2ebb7f` |
| 1 | Break reminder + work sessions (25/5 default, full-screen overlay) | To design and ship |
| 2 | Categories page merged into Settings (as modal sheet) | To design and ship |
| 3 | Log: Activities sub-tab merged into Journal timeline | To design and ship |
| 4 | Obsidian tag filter (`#log` / `#Log` / `#LOG` / `#记录`) + label cleanup | To design and ship |
| 5 | Edit/delete on all journal rows (Summary, WorkSession, Activity) | To design and ship |
| 6 | AI summary enriched with activities + sessions + plans | To design and ship |
| 7 | App icon (AI-generated sprout + clock theme) | To design and ship |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AppDelegate                              │
│                                                                  │
│  ┌──────────────┐  ┌─────────────────┐  ┌──────────────────┐   │
│  │ Activity     │  │  Break          │  │  Overlay Window  │   │
│  │ Tracker      │──│  Scheduler      │──│  Controller      │   │
│  │ (+ AFK       │  │  (state machine │  │  (full-screen    │   │
│  │ broadcast)   │  │   + timer)      │  │   NSWindow)      │   │
│  └──────┬───────┘  └────────┬────────┘  └────────┬─────────┘   │
│         │                   │                     │             │
│         │          ┌────────▼─────────┐            │             │
│         │          │  WorkSession     │            │             │
│         └──────────│  Store           │◄───────────┘             │
│                    └──────────────────┘                          │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────────────────────┐    │
│  │ SummaryContext   │  │  AIService                       │    │
│  │ Builder          │──│  (unified prompt pipeline)       │    │
│  └──────────────────┘  └──────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘

      ▲                                             ▲
      │                                             │
      │ reads                                       │ displays
      │                                             │
┌─────┴────────────────────────┐              ┌────┴──────────────┐
│  EventStore · OfflineStore   │              │  OfflineView      │
│  WorkSessionStore · Settings │              │  (unified Journal)│
└──────────────────────────────┘              └───────────────────┘
```

**Communication style:** `NotificationCenter` between components (existing convention — `settingsDidSave`, `dailySummaryDidSave`). Zero new coupling between `ActivityTracker` and `BreakScheduler`; they only share notification names.

---

## Data Model Changes

### Migration `v3_sessions_and_source`

GRDB migration registered in `AppDatabase.swift` after the existing v2:

```swift
migrator.registerMigration("v3_sessions_and_source") { db in
    // 1. Work sessions table
    try db.create(table: "work_sessions") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("start_ts",  .integer).notNull()
        t.column("end_ts",    .integer).notNull()
        t.column("summary",   .text).notNull().defaults(to: "")
        t.column("top_apps",  .text).notNull().defaults(to: "[]")
        t.column("outcome",   .text).notNull().defaults(to: "completed")
        t.column("created_at", .integer).notNull()
    }
    try db.create(
        index: "idx_work_sessions_start",
        on: "work_sessions",
        columns: ["start_ts"]
    )

    // 2. Source column on offline_activities
    try db.alter(table: "offline_activities") { t in
        t.add(column: "source", .text).notNull().defaults(to: "manual")
    }
}
```

### New model `WorkSession`

```swift
struct WorkSession: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var startTs: Int64          // Unix ms
    var endTs: Int64            // Unix ms
    var summary: String = ""
    var topApps: String = "[]"  // JSON: [TopAppSnapshot]
    var outcome: String = "completed"  // "completed" | "skipped"
    var createdAt: Int64

    static let databaseTableName = "work_sessions"

    enum CodingKeys: String, CodingKey {
        case id
        case startTs    = "start_ts"
        case endTs      = "end_ts"
        case summary
        case topApps    = "top_apps"
        case outcome
        case createdAt  = "created_at"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

struct TopAppSnapshot: Codable {
    let name: String
    let secs: Double
}
```

### `OfflineActivity` gets a `source` field

```swift
struct OfflineActivity: Identifiable, Codable, FetchableRecord, MutablePersistableRecord {
    var id: Int64?
    var startTs: Int64
    var durationSecs: Int64
    var label: String
    var tagId: String?
    var createdAt: Int64
    var source: String = "manual"   // NEW: "manual" | "obsidian"

    static let databaseTableName = "offline_activities"

    enum CodingKeys: String, CodingKey {
        case id
        case startTs      = "start_ts"
        case durationSecs = "duration_secs"
        case label
        case tagId        = "tag_id"
        case createdAt    = "created_at"
        case source
    }

    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
```

### `WorkSessionStore` (new file)

```swift
final class WorkSessionStore {
    private let db: any DatabaseWriter & DatabaseReader
    convenience init() { self.init(db: AppDatabase.shared.pool) }
    init(db: some DatabaseWriter & DatabaseReader) { self.db = db }

    @discardableResult
    func save(_ session: WorkSession) throws -> WorkSession {
        var copy = session
        try db.write { d in try copy.insert(d) }
        return copy
    }

    func update(_ session: WorkSession) throws {
        try db.write { d in try session.update(d) }
    }

    func delete(id: Int64) throws {
        try db.write { d in _ = try WorkSession.deleteOne(d, key: id) }
    }

    func sessions(from startMs: Int64, to endMs: Int64) throws -> [WorkSession] {
        try db.read { d in
            try WorkSession
                .filter(Column("start_ts") >= startMs && Column("start_ts") < endMs)
                .order(Column("start_ts").desc)
                .fetchAll(d)
        }
    }
}
```

### `OfflineStore` gains `update` + `activities(from:to:)`

```swift
func update(_ activity: OfflineActivity) throws {
    try db.write { d in try activity.update(d) }
}

func activities(from startMs: Int64, to endMs: Int64) throws -> [OfflineActivity] {
    try db.read { d in
        try OfflineActivity
            .filter(Column("start_ts") >= startMs && Column("start_ts") < endMs)
            .order(Column("start_ts").asc)
            .fetchAll(d)
    }
}
```

---

## Feature 1: Break Reminder + Work Sessions

### Settings (all persisted via `AppDatabase.setting`)

| Key | Type | Default | Purpose |
|---|---|---|---|
| `break_enabled` | Bool | `false` | Master on/off |
| `break_work_interval_secs` | Int | `1500` (25 min) | Work period length |
| `break_rest_interval_secs` | Int | `300` (5 min) | Rest period length |
| `break_pause_on_afk` | Bool | `true` | Freeze work timer when idle |
| `break_require_summary_on_skip` | Bool | `true` | Disable Skip button until summary filled |
| `break_screen_scope` | String | `"main"` | `"main"` or `"all"` |
| `break_disabled_until` | Int | `0` | Unix ms; scheduler suspends until this moment |
| `break_last_postpone_cycle` | Int | `0` | Monotonic cycle counter when last postpone happened |

### BreakConfig (new)

Thin struct that reads/writes the KV and exposes typed values. Constructed fresh on demand (no caching) — the scheduler reads it on every relevant transition to pick up Settings changes without restart.

### BreakScheduler state machine

```swift
enum BreakSchedulerState {
    case idle
    case working(workElapsed: Int)
    case workingAfk(frozenElapsed: Int)
    case postponed(until: Date)
    case pendingBreak(draft: WorkSessionDraft)
    case onBreak(draft: WorkSessionDraft, breakElapsed: Int)
    case disabledUntilTomorrow(resumeAt: Date)
}
```

**Transitions** (driven by 1s `Timer.scheduledTimer` on `.main` + `NotificationCenter` observers):

| From | Event | To | Side-effect |
|---|---|---|---|
| `idle` | `.settingsDidSave` sees `break_enabled=true` | `working(0)` | — |
| `working(n)` | tick, `n+1 < workInterval` | `working(n+1)` | — |
| `working(n)` | tick, `n+1 >= workInterval` | `pendingBreak(draft)` | Build draft (EventStore.topApps), post `.breakShouldStart` |
| `working(n)` | `.afkStateDidChange` (AFK) | `workingAfk(n)` | — |
| `workingAfk(n)` | `.afkStateDidChange` (active) | `working(n)` | — |
| `pendingBreak(d)` | `.breakActionDidStart` | `onBreak(d, 0)` | `WorkSessionStore.save(d.materialize("completed"))`, window shows countdown phase |
| `pendingBreak(d)` | `.breakActionSkip(summary)` | `working(0)` | Save session (outcome=`skipped`), overlay closes |
| `pendingBreak(d)` | `.breakActionPostpone` | `postponed(now + 5min)` | Overlay closes, do NOT save; flag cycle as postponed |
| `pendingBreak(d)` | `.breakActionDisableToday` | `disabledUntilTomorrow(midnight)` | Overlay closes, do NOT save |
| `onBreak(d, k)` | tick, `k+1 < restInterval` | `onBreak(d, k+1)` | — |
| `onBreak(d, k)` | tick, `k+1 >= restInterval` | `working(0)` | Close overlay |
| `onBreak` | `.breakActionEndEarly` | `working(0)` | Close overlay |
| `postponed(t)` | tick, `now >= t` | `pendingBreak(draft')` | Rebuild draft with fresh top_apps, post `.breakShouldStart` |
| `disabledUntilTomorrow(t)` | tick, `now >= t` | `working(0)` | — |
| any | `.settingsDidSave` and `break_enabled=false` | `idle` | Close overlay if any |

**Invariants:**

1. Work timer accumulates ONLY in `working`. Everything else freezes `workElapsed`.
2. Exactly zero or one overlay window exists at any time.
3. Postpone is limited to 1 per work cycle; after that the postpone button is disabled client-side AND the scheduler ignores a second postpone intent.
4. A draft is constructed at pendingBreak entry and regenerated on postponed→pendingBreak re-entry (so top_apps reflects work done during the postponed window).

### `WorkSessionDraft`

```swift
struct WorkSessionDraft {
    let startMs: Int64
    let endMs: Int64
    let topApps: [TopAppSnapshot]
    var summary: String = ""

    func materialize(outcome: String) -> WorkSession {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let encoded = (try? JSONEncoder().encode(topApps))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return WorkSession(
            id: nil, startTs: startMs, endTs: endMs,
            summary: summary, topApps: encoded,
            outcome: outcome, createdAt: nowMs
        )
    }
}
```

### Overlay window

`BreakOverlayWindowController` creates a single `NSWindow`:

- `styleMask: [.borderless]`
- `level: .screenSaver` — covers Dock, menu bar, and full-screen apps
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`
- `isOpaque = false`, `backgroundColor = .clear` — SwiftUI layer draws `Color.black.opacity(0.92)`
- Main screen only (`NSScreen.main`) — multi-screen deferred
- On show: `makeKeyAndOrderFront(nil)` + `NSApp.activate(ignoringOtherApps: true)`

### OverlayView (two phases)

**Phase 1 — input:**

- Title: "🌱 休息时间"
- Subtitle: "你已专注 {workInterval} 分钟，记录一下这一轮做了什么"
- Top Apps card (from draft.topApps)
- TextEditor bound to `@State draft.summary` (auto-focused via `@FocusState`)
- Four buttons:
  - "开始休息 {restInterval} 分钟" — always enabled
  - "跳过本轮" — enabled only when `draft.summary.trimmed.isNotEmpty`
  - "延后 5 分钟" — disabled if already postponed in this cycle
  - "今日禁用" — triggers a confirm alert first
- ESC key → maps to "延后 5 分钟" (fallback to "开始休息" if postpone disabled)

**Phase 2 — countdown:**

- Huge MM:SS countdown text
- "休息一下 ☕️" caption
- "提前结束" button (triggers `.breakActionEndEarly`)

Transition between phases is a `@State var phase: OverlayPhase` inside the same view — window is not recreated.

---

## Feature 2: Dashboard Restructure (Categories & Activities merges)

### Dashboard sidebar: 4 tabs → 3 tabs

```swift
enum DashboardTab: String, CaseIterable {
    case stats    = "Stats"
    case offline  = "Log"
    case settings = "Settings"

    var displayName: String {
        switch self {
        case .stats:    return "统计"
        case .offline:  return "日志"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .stats:    return "chart.bar.fill"
        case .offline:  return "text.book.closed.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
```

`DashboardView` switch statement loses `.categories` branch.

### Settings sections (top to bottom)

| # | Section | Source |
|---|---|---|
| 1 | 应用 (Launch at Login, Accessibility) | Relocated from old System section |
| 2 | AI 配置 (existing: provider / URL / model / API key) | Existing |
| 3 | 自动日度 AI 总结 (existing Change F) | Existing |
| 4 | ⏱️ 休息提醒 (NEW) | This release |
| 5 | Tracking (AFK threshold, redact titles) | Existing |
| 6 | 🏷️ 分类 (NEW — button that opens modal CategorySheet) | This release |
| 7 | Obsidian 日记导入 (existing) | Existing |
| 8 | Stats 排除分类 (existing) | Existing |
| 9 | 日志与数据 (Open Logs Folder) | Relocated from old System section |

### CategorySheet (new)

Wrapper that embeds `CategoryView()` unchanged in a modal sheet:

```swift
struct CategorySheet: View {
    let onClose: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("管理分类").font(.headline)
                Spacer()
                Button("关闭") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            CategoryView()
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
```

`CategoryView.swift` itself is not modified.

### OfflineView — single unified timeline

**Removed:**
- `LogTab` enum, `activeTab` state, segmented picker
- `activitiesContent` / `addForm` / `activityList` computed properties
- `selectedDate` state, `loadActivities()`, per-day date picker

**Added:**
- Toolbar: "+ 添加活动" button → opens `AddActivitySheet`
- New `JournalEntry` case:
  ```swift
  case workSessions(date: String, items: [WorkSession])
  ```
- Single-day chronological merge: Summary card at top, then WorkSessions and OfflineActivities interleaved by `start_ts` (NOT grouped by type)
- `⋯` menu on every row type with 编辑 / 删除

### Row types and editor bindings

| Row | Editor sheet | Store call on save |
|---|---|---|
| `DailySummary` | `SummaryEditorSheet` (existing) | `OfflineStore.saveSummary` (existing) |
| `WorkSession` | `WorkSessionEditorSheet` (new, binds `.summary` only) | `WorkSessionStore.update` |
| `OfflineActivity` (any source) | `ActivityEditorSheet` (new, binds label/start/duration) | `OfflineStore.update` |

### Obsidian-source delete warning

When Fisher clicks delete on a row where `source == "obsidian"`:

```swift
.alert("这条活动来自 Obsidian 日记", isPresented: $showDeleteObsidianAlert) {
    Button("取消", role: .cancel) { }
    Button("仅从 SeedoMac 删除", role: .destructive) {
        deleteActivity(pendingDelete)
    }
} message: {
    Text("下次导入 Obsidian 日记时，这条活动会重新出现。要永久删除，请从源文件里移除 #log 标签。")
}
```

Manual-source deletes skip the alert and delete directly.

### AddActivitySheet / ActivityEditorSheet

Both share the same form (label / date picker / start time / duration with TextField + Stepper up to 1440 min). AddActivitySheet creates via `OfflineStore.insert`, ActivityEditorSheet patches via `OfflineStore.update`.

---

## Feature 3: Obsidian Tag Filter + Cleanup

### Filter rule

A parsed Obsidian line is kept only if its label matches `(?i)#log\b|#记录` via `NSRegularExpression`. Matching uses a Unicode word boundary for `#log` (so `#logging` is NOT a match) and literal substring for `#记录` (CJK word boundaries are unreliable).

### Label cleanup

Tag substrings are stripped from the stored label so Fisher sees clean text in the timeline:

```swift
private static func hasLogTag(_ label: String) -> Bool {
    let pattern = #"(?i)#log\b|#记录"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
    let range = NSRange(label.startIndex..., in: label)
    return regex.firstMatch(in: label, range: range) != nil
}

private static func stripLogTag(_ label: String) -> String {
    var s = label
    if let regex = try? NSRegularExpression(
        pattern: #"#log\b"#, options: [.caseInsensitive]
    ) {
        let range = NSRange(s.startIndex..., in: s)
        s = regex.stringByReplacingMatches(
            in: s, range: range, withTemplate: ""
        )
    }
    s = s.replacingOccurrences(of: "#记录", with: "")
    let collapsed = s.split(separator: " ", omittingEmptySubsequences: true)
        .joined(separator: " ")
    return collapsed.trimmingCharacters(in: .whitespaces)
}
```

### Parser wiring

Inside `ObsidianImporter.parseEntries`, after extracting `rawLabel`:

```swift
let rawLabel = String(content[lRange]).trimmingCharacters(in: .whitespaces)
guard Self.hasLogTag(rawLabel) else { return }
let cleanLabel = Self.stripLogTag(rawLabel)
guard !cleanLabel.isEmpty else { return }
raw.append((Int64(date.timeIntervalSince1970 * 1000), cleanLabel))
```

### Dedup change

New dedup keys on `(source, start_ts)` instead of `(start_ts, label)`:

```swift
private func existsObsidianActivity(startTs: Int64) throws -> Bool {
    try AppDatabase.shared.pool.read { d in
        let count = try OfflineActivity
            .filter(Column("start_ts") == startTs && Column("source") == "obsidian")
            .fetchCount(d)
        return count > 0
    }
}
```

Inserts explicitly set `source: "obsidian"`. Editing an imported row's label no longer breaks dedup; editing `startTs` still can (documented limitation).

---

## Feature 4: AI Summary Context Enrichment

### New types

```swift
struct SummaryContext {
    let periodKey: String
    let periodLabel: String
    let totalSecs: Double
    let topApps: [AppStat]
    let categories: [CategoryStat]
    let manualActivities: [OfflineActivity]
    let obsidianActivities: [OfflineActivity]
    let workSessions: [WorkSession]
    let plan: String?
}

enum PlanScope: String {
    case daily, monthly, yearly
    func planKey(for periodKey: String) -> String {
        switch self {
        case .daily:   return "plan_daily:\(periodKey)"
        case .monthly: return "plan_monthly:\(periodKey)"
        case .yearly:  return "plan_yearly:\(periodKey)"
        }
    }
}
```

### `SummaryContextBuilder`

```swift
final class SummaryContextBuilder {
    static func build(
        periodKey: String,
        periodLabel: String,
        startMs: Int64,
        endMs: Int64,
        scope: PlanScope
    ) throws -> SummaryContext {
        // 1. Tracked events — Top 50 apps with excluded-category filter
        let rawApps = try EventStore().topApps(
            startMs: startMs, endMs: endMs, limit: 50
        )
        let (includedApps, catStats, totalSecs) = try filterAndBucket(rawApps)
        let limitedApps = Array(includedApps.prefix(10))

        // 2. Offline activities split by source
        let all = try OfflineStore().activities(from: startMs, to: endMs)
        let manual   = all.filter { $0.source == "manual" }
        let obsidian = all.filter { $0.source == "obsidian" }

        // 3. Work sessions
        let sessions = try WorkSessionStore().sessions(from: startMs, to: endMs)

        // 4. Plan text
        let plan = AppDatabase.shared
            .setting(for: scope.planKey(for: periodKey))
            .flatMap { $0.isEmpty ? nil : $0 }

        return SummaryContext(
            periodKey: periodKey, periodLabel: periodLabel,
            totalSecs: totalSecs,
            topApps: limitedApps, categories: catStats,
            manualActivities: manual, obsidianActivities: obsidian,
            workSessions: sessions, plan: plan
        )
    }

    private static func filterAndBucket(_ rawApps: [AppStat])
        throws -> (apps: [AppStat], cats: [CategoryStat], total: Double) {
        // Same logic as AppDelegate.runAutoDailySummary — hoisted here.
        // ...
    }
}
```

### `AIService.generateSummary` signature change

```swift
func generateSummary(
    context: SummaryContext,
    completion: @escaping (Result<DailySummary, Error>) -> Void
)
```

Old signature is removed (no backward compat callers).

### Prompt structure

```
请对 {periodLabel} 生成一段结构化的个人回顾总结。

【使用时长】{formatDuration(totalSecs)}

【应用使用 Top 10】
{topApps each line}

【分类分布】
{categories each line with percentage}

【专注会话（{sessions.count} 轮）】
{each session: HH:MM–HH:MM apps · 小结: <summary or "(未写)">}

【手动记录】
{manualActivities each line: HH:MM label (N min)}

【Obsidian 日记】
{obsidianActivities each line: HH:MM label (N min)}

【{periodLabel} 计划】
{plan ?? "(未设置)"}

---

请综合以上全部信息，输出：
1. 整体节奏和情绪
2. 完成了计划中的哪些事（明确对照计划文本）
3. 时间分配是否健康
4. 3 个关键词
5. 1-5 星自评
```

### Call sites

Both entry points migrate to the builder:

```swift
// AppDelegate.runAutoDailySummary:
let ctx = try SummaryContextBuilder.build(
    periodKey: todayKey, periodLabel: "Today",
    startMs: startMs, endMs: endMs, scope: .daily
)
AIService.shared.generateSummary(context: ctx) { ... }

// StatsView manual-summary button: same pattern, scope/period derived from
// the currently-selected period picker.
```

---

## Feature 5: App Icon

### Source image generation

Fisher provides a 1024×1024 PNG, generated via any modern image model using this prompt:

> macOS Big Sur style app icon, squircle shape with subtle gradient background in forest green (#2D5F3F) to sage green (#8FBC8F), centered motif: a small glossy green sprout with two leaves emerging from rich dark soil, intertwined with a translucent analog clock face showing faint roman numerals around the sprout's base, the clock hands made of delicate golden filaments. Subtle inner shadow, soft rim light, no text, no border, rendered at 1024x1024 px, transparent background, modern minimal flat-3D hybrid style matching Apple's SF Pro aesthetic.

### Packaging: `scripts/package_icon.sh`

Uses macOS-native `sips` to resize the source to the 10 macOS icon sizes (16/32/128/256/512 @ 1x and 2x), writes each PNG into `SeedoMac/Assets.xcassets/AppIcon.appiconset/`, and generates the matching `Contents.json`.

### project.yml

Add `CFBundleIconName: AppIcon` under `info` if not already present — Assets.xcassets-driven icon loading requires it.

---

## Notifications

Centralized in a new `SeedoMac/Common/Notifications.swift`:

```swift
extension Notification.Name {
    static let afkStateDidChange       = Notification.Name("afkStateDidChange")
    static let breakShouldStart        = Notification.Name("breakShouldStart")
    static let breakActionDidStart     = Notification.Name("breakActionDidStart")
    static let breakActionSkip         = Notification.Name("breakActionSkip")
    static let breakActionPostpone     = Notification.Name("breakActionPostpone")
    static let breakActionDisableToday = Notification.Name("breakActionDisableToday")
    static let breakActionEndEarly     = Notification.Name("breakActionEndEarly")
    static let breakDidComplete        = Notification.Name("breakDidComplete")
    static let workSessionDidSave      = Notification.Name("workSessionDidSave")
}
```

Existing notifications (`settingsDidSave`, `dailySummaryDidSave`) stay where they are.

---

## File Manifest

### New files (14)

| File | Purpose |
|---|---|
| `SeedoMac/BreakReminder/BreakConfig.swift` | Typed KV wrapper for break settings |
| `SeedoMac/BreakReminder/BreakScheduler.swift` | State machine + timer + AFK subscription |
| `SeedoMac/BreakReminder/BreakOverlayWindowController.swift` | Full-screen NSWindow lifecycle |
| `SeedoMac/BreakReminder/BreakOverlayView.swift` | Input + countdown SwiftUI phases |
| `SeedoMac/Data/WorkSessionStore.swift` | GRDB CRUD for `work_sessions` |
| `SeedoMac/AI/SummaryContext.swift` | Context struct + `PlanScope` enum |
| `SeedoMac/AI/SummaryContextBuilder.swift` | Reads all five data sources |
| `SeedoMac/Common/Notifications.swift` | Centralized notification names |
| `SeedoMac/Views/Dashboard/CategorySheet.swift` | Modal wrapper for CategoryView |
| `SeedoMac/Views/Dashboard/AddActivitySheet.swift` | Journal "+ 添加活动" form |
| `SeedoMac/Views/Dashboard/ActivityEditorSheet.swift` | Edit existing `OfflineActivity` |
| `SeedoMac/Views/Dashboard/WorkSessionEditorSheet.swift` | Edit `WorkSession.summary` |
| `SeedoMac/Assets.xcassets/AppIcon.appiconset/` | 10 PNGs + Contents.json |
| `scripts/package_icon.sh` | 1024 PNG → 10-size icon set |

### Modified files (13)

| File | Change |
|---|---|
| `SeedoMac/Data/AppDatabase.swift` | Register `v3_sessions_and_source` migration |
| `SeedoMac/Data/Models.swift` | `OfflineActivity.source`, add `WorkSession` + `TopAppSnapshot` |
| `SeedoMac/Data/OfflineStore.swift` | `update(_:)` + `activities(from:to:)` |
| `SeedoMac/Data/ObsidianImporter.swift` | Tag filter + cleanup + source field + new dedup |
| `SeedoMac/AI/AIService.swift` | `generateSummary(context:completion:)` + rebuilt prompt |
| `SeedoMac/Tracker/ActivityTracker.swift` | Post `.afkStateDidChange` on edge transitions |
| `SeedoMac/App/AppDelegate.swift` | Wire BreakScheduler + OverlayController; `runAutoDailySummary` via builder |
| `SeedoMac/Views/Dashboard/DashboardView.swift` | Drop `.categories` tab |
| `SeedoMac/Views/Dashboard/SettingsView.swift` | Reorder sections; add break reminder + categories button |
| `SeedoMac/Views/Dashboard/OfflineView.swift` | Rewrite to single unified timeline with three row types |
| `SeedoMac/Views/Dashboard/StatsView.swift` | Manual summary via `SummaryContextBuilder` |
| `project.yml` | Add `CFBundleIconName: AppIcon` under info |
| `SeedoMac/Views/Dashboard/CategoryView.swift` | **Unchanged** — just reparented into a sheet |

---

## Implementation Order

Nine commits, each independently buildable:

| # | Commit | Rationale |
|---|---|---|
| 1 | `feat(db): v3 migration — work_sessions + offline_activities.source` | Schema foundation; nothing else compiles without it |
| 2 | `feat(obsidian): tag filter (#log / #记录) + clean label + source field` | Pure backend; easy to verify by running importToday manually |
| 3 | `refactor(dashboard): merge Categories into Settings as modal sheet` | Structural change; CategoryView untouched so low risk |
| 4 | `refactor(log): merge Activities into Journal timeline with edit/delete` | Biggest UI rewrite; all three row types wired up with edit sheets |
| 5 | `feat(ai): enrich summary with activities, sessions, and plan context` | Backend-only; rides on foundation from commit 1 |
| 6 | `feat(break): add BreakScheduler + AFK broadcasting` | Headless state machine; verify via console logs before adding UI |
| 7 | `feat(break): add full-screen overlay window + countdown view` | UI layer for the scheduler; uses commit 6's notifications |
| 8 | `feat(settings): add break reminder section with test button` | Wires the Settings KV into BreakConfig |
| 9 | `feat(assets): add AppIcon (sprout + clock theme)` | Final polish, no logic |

After commit 9: `xcodebuild archive` + `hdiutil create -format UDZO` for the new DMG, then push all commits to `origin/main`.

---

## Verification

### Per-commit

Each commit: `xcodebuild -scheme SeedoMac -configuration Release build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO` must exit 0 with no new warnings on touched files.

### End-to-end (after all 9 commits)

1. **Duration fix (0)**: already shipped, regression check — type `240` into Duration, save a 4h activity
2. **Schema (1)**: launch app, verify no crash on migrate; check `sqlite3` for `work_sessions` table and `offline_activities.source` column
3. **Obsidian filter (2)**: daily note with 5 lines (3 tagged `#log`, 1 tagged `#记录`, 1 untagged) → `立即导入今天` → expect "导入 4 条活动", untagged line skipped
4. **Categories merge (3)**: Dashboard sidebar shows 3 tabs; Settings → 管理分类... opens modal with full CategoryView
5. **Log merge + edit/delete (4)**: Journal timeline shows mixed Summary/WorkSession/Activity rows in time order; `⋯` menu works on each; deleting an Obsidian row shows warning alert
6. **AI summary context (5)**: generate manual summary for Today, inspect prompt log (verbose mode) — confirm all four new sections appear
7. **Break scheduler (6)**: enable in Settings, set work interval to 60s + rest 10s; wait; verify scheduler logs tick transitions in Console.app
8. **Overlay (7)**: at break time, verify full-screen black overlay covers all apps including a full-screen Safari; type a summary; click "开始休息"; countdown starts; after 10s window closes; verify a `work_sessions` row exists
9. **Settings (8)**: test button triggers overlay immediately without waiting for the work interval
10. **Icon (9)**: Finder shows the new icon in `build/dmg-staging/SeedoMac.app`; dock shows it when running

---

## Known Deferred / Non-goals

- **Multi-screen overlay**: only main screen covered; multi-monitor users see the blackout on one screen only.
- **Sound on break**: no alert sound yet; relying on visual disruption alone.
- **Obsidian source round-trip**: SeedoMac never writes back to the Obsidian markdown file.
- **Per-session `start_ts` editing** via `ActivityEditorSheet`: technically allowed but breaks Obsidian dedup — documented as caveat, not blocked.
- **Range-key PK collision** for weekly/monthly AI summaries (inherited from previous release).
- **Postpone count > 1**: hard-capped at 1 per cycle to keep the state machine simple.
- **Break history analytics** (e.g., "you took 6 breaks today, avg focus 22 min"): deferred until `work_sessions` has enough data to be interesting.

---

## Open Risks

1. **`.screenSaver` window level conflicts with screen recording / screensharing apps** — if Fisher is on a Zoom call with screen share when a break fires, the overlay will be broadcast. Mitigation: test with Zoom; consider dropping to `.floating` if it's a problem.
2. **CGEventSource idle detection lag** — `.combinedSessionState` resets on any input; if Fisher uses a password manager that injects keys, AFK may never trigger. Existing behavior, not regressed.
3. **`work_sessions` unbounded growth** — no retention policy. At 15 sessions/day × 365 days = ~5500 rows/year; negligible for SQLite.
4. **AI prompt token growth** — enriched prompt adds ~500–2000 tokens/day. On gpt-4o-mini at $0.15/M, the extra cost is ~$0.0003 per call. Acceptable. If summary quality degrades from noise, a `break_summary_compact_mode` KV could trim Obsidian+WorkSession details.
