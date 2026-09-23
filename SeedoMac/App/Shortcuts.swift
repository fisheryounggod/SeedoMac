import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let togglePureFocus = Self("togglePureFocus")
    static let startPauseFocus = Self("startPauseFocus")
    static let openSettings = Self("openSettings")
    static let addManualRecord = Self("addManualRecord")
    static let openStats = Self("openStats")
    static let stopAndRecord = Self("stopAndRecord")

    /// All shortcuts handled by the global Carbon event monitor.
    static let allSeedoShortcuts: [Self] = [
        .togglePureFocus,
        .startPauseFocus,
        .openSettings,
        .addManualRecord,
        .openStats,
        .stopAndRecord
    ]
}
