// SeedoMac/Services/CalendarSyncService.swift
import Foundation
import EventKit

final class CalendarSyncService {
    static let shared = CalendarSyncService()
    
    private let eventStore = EKEventStore()
    private let calendarName = "Seedo"
    
    private init() {}
    
    /// Requests access to the calendar. Works for macOS 13 and 14+.
    func requestAccess(completion: @escaping (Bool) -> Void) {
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
    }
    
    /// Synchronizes a WorkSession to the "Seedo" calendar.
    func sync(session: WorkSession) {
        guard AppDatabase.shared.setting(for: "calendar_sync_enabled") == "true" else { return }
        
        requestAccess { [weak self] granted in
            guard let self = self, granted else { 
                print("[Calendar] Access not granted or sync disabled.")
                return 
            }
            
            do {
                let calendar = try self.findOrCreateCalendar()
                let event = EKEvent(eventStore: self.eventStore)
                
                event.calendar = calendar
                
                // Clean title
                var cleanTitle = session.title.isEmpty ? (session.summary.isEmpty ? "Focus Session" : session.summary) : session.title
                cleanTitle = cleanTitle.replacingOccurrences(of: "Focus Session: ", with: "")
                event.title = cleanTitle
                
                event.startDate = Date(timeIntervalSince1970: Double(session.startTs) / 1000)
                event.endDate = Date(timeIntervalSince1970: Double(session.endTs) / 1000)
                
                let durationMins = Int((session.endTs - session.startTs) / 60000)
                var notes = "Duration: \(durationMins) mins\nOutcome: \(session.outcome)\n\n"
                
                if !session.summary.isEmpty {
                    notes += "Summary: \(session.summary)\n\n"
                }

                notes += "Top Apps:\n"
                if let data = session.topAppsJson.data(using: .utf8),
                   let apps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for app in apps {
                        if let name = app["appOrDomain"] as? String, 
                           let secs = app["totalSecs"] as? Double {
                            notes += "- \(name): \(Int(secs/60))m\n"
                        }
                    }
                }
                
                event.notes = notes
                
                try self.eventStore.save(event, span: .thisEvent, commit: true)
                print("[Calendar] Successfully synced session: \(session.startTs)")
            } catch {
                print("[Calendar] Sync failed with error: \(error.localizedDescription)")
            }
        }
    }
    
    private func findOrCreateCalendar() throws -> EKCalendar {
        let calendars = eventStore.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == calendarName }) {
            return existing
        }
        
        print("[Calendar] Creating new '\(calendarName)' calendar...")
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = calendarName
        
        // Priority: iCloud > Local > Default
        let source = eventStore.sources.first(where: { $0.sourceType == .calDAV && $0.title.contains("iCloud") })
                  ?? eventStore.sources.first(where: { $0.sourceType == .local })
                  ?? eventStore.defaultCalendarForNewEvents?.source
        
        if let source {
            newCalendar.source = source
        } else {
            throw NSError(domain: "CalendarSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "No suitable calendar source found."])
        }
        
        try eventStore.saveCalendar(newCalendar, commit: true)
        return newCalendar
    }
}
