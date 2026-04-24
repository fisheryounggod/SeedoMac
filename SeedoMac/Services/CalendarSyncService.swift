// Seedo/Services/CalendarSyncService.swift
import Foundation
import EventKit

final class CalendarSyncService {
    static let shared = CalendarSyncService()
    
    private let eventStore = EKEventStore()
    private let calendarName = "Seedo"
    
    private init() {}
    
    /// Requests access to the calendar. Works for macOS 13 and 14+.
    func requestAccess(completion: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            if #available(macOS 14.0, *) {
                eventStore.requestFullAccessToEvents { granted, error in
                    if let error { print("[Calendar] Access error: \(error)") }
                    completion(granted)
                }
            } else {
                eventStore.requestAccess(to: .event) { granted, error in
                    if let error { print("[Calendar] Access error: \(error)") }
                    completion(granted)
                }
            }
        case .denied, .restricted:
            print("[Calendar] Access denied or restricted.")
            completion(false)
        case .fullAccess:
            completion(true)
        case .writeOnly:
            // For Seedo, we prefer full access to find/create our specific calendar
            completion(true)
        @unknown default:
            completion(false)
        }
    }
    
    
    /// Identifies and returns the Seedo calendar.
    private func findOrCreateCalendar() throws -> EKCalendar {
        let calendars = eventStore.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == calendarName }) {
            return existing
        }
        
        print("[Calendar] Creating new '\(calendarName)' calendar...")
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = calendarName
        
        // Improved source selection: iCloud -> Local -> Any primary account source -> Default
        let source = eventStore.sources.first(where: { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("iCloud") })
                  ?? eventStore.sources.first(where: { $0.sourceType == .local })
                  ?? eventStore.sources.first(where: { $0.sourceType == .calDAV }) // e.g. Exchange, Google
                  ?? eventStore.defaultCalendarForNewEvents?.source
        
        if let source {
            newCalendar.source = source
        } else {
            throw NSError(domain: "CalendarSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "No suitable calendar source found."])
        }
        
        try eventStore.saveCalendar(newCalendar, commit: true)
        return newCalendar
    }

    /// Synchronizes a WorkSession to the "Seedo" calendar.
    func sync(session: WorkSession) {
        // Guard if explicitly disabled
        guard AppDatabase.shared.setting(for: "calendar_sync_enabled") == "true" else { return }
        
        requestAccess { [weak self] granted in
            guard let self = self, granted else { return }
            
            do {
                let calendar = try self.findOrCreateCalendar()
                
                // 1. Check for existing event within this time range to avoid duplicates
                let start = Date(timeIntervalSince1970: Double(session.startTs) / 1000)
                let end = Date(timeIntervalSince1970: Double(session.endTs) / 1000)
                
                // Search +/- 2 seconds to account for precision loss
                let predicate = self.eventStore.predicateForEvents(withStart: start.addingTimeInterval(-2), 
                                                                    end: start.addingTimeInterval(2), 
                                                                    calendars: [calendar])
                let existingEvents = self.eventStore.events(matching: predicate)
                
                let event: EKEvent
                if let existing = existingEvents.first(where: { $0.title.contains(session.summary) || $0.title.contains(session.title) }) {
                    event = existing
                    print("[Calendar] Updating existing event for session: \(session.startTs)")
                } else {
                    event = EKEvent(eventStore: self.eventStore)
                    event.calendar = calendar
                    print("[Calendar] Creating new event for session: \(session.startTs)")
                }
                
                // 2. Update properties
                // Align with Seedo UI: 'summary' is the Headline (Title in Calendar), 'title' is the Remark (Notes in Calendar)
                let cat = SessionCategory.find(session.categoryId)
                var displayTitle = session.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? cat.name : session.summary
                displayTitle = displayTitle.replacingOccurrences(of: "Focus Session: ", with: "")
                
                event.title = displayTitle
                event.startDate = start
                event.endDate = end
                
                let durationMins = Int((session.endTs - session.startTs) / 60000)
                var notes = "Duration: \(durationMins) mins\nOutcome: \(session.outcome)\n"
                
                if !session.title.isEmpty { 
                    notes += "Notes: \(session.title)\n" 
                }
                
                notes += "\n"
                
                notes += "Top Apps:\n"
                if let data = session.topAppsJson.data(using: .utf8),
                   let apps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for app in apps {
                        if let name = app["appOrDomain"] as? String, let secs = app["totalSecs"] as? Double {
                            notes += "- \(name): \(Int(secs/60))m\n"
                        }
                    }
                }
                event.notes = notes
                
                try self.eventStore.save(event, span: .thisEvent, commit: true)
            } catch {
                print("[Calendar] Sync failed: \(error.localizedDescription)")
            }
        }
    }

    /// Removes a session's event from the calendar.
    func delete(session: WorkSession) {
        requestAccess { [weak self] granted in
            guard let self = self, granted else { return }
            do {
                let calendar = try self.findOrCreateCalendar()
                let start = Date(timeIntervalSince1970: Double(session.startTs) / 1000)
                let predicate = self.eventStore.predicateForEvents(withStart: start.addingTimeInterval(-2), 
                                                                    end: start.addingTimeInterval(2), 
                                                                    calendars: [calendar])
                let existingEvents = self.eventStore.events(matching: predicate)
                
                for event in existingEvents {
                    try self.eventStore.remove(event, span: .thisEvent, commit: true)
                }
            } catch {
                print("[Calendar] Delete failed: \(error.localizedDescription)")
            }
        }
    }

    /// Forces a sync of all sessions in a given timeframe (default: past 30 days)
    func forceSyncAll(days: Int = 30) {
        print("[Calendar] Force syncing past \(days) days...")
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: now)!
        let startMs = Int64(start.timeIntervalSince1970 * 1000)
        let endMs = Int64(now.timeIntervalSince1970 * 1000)
        
        do {
            let sessions = try WorkSessionStore().sessions(from: startMs, to: endMs)
            for session in sessions {
                self.sync(session: session)
            }
        } catch {
            print("[Calendar] Force sync failed to load sessions: \(error)")
        }
    }
}
