import Foundation

struct WidgetSnapshotStore {
    static let appGroup = "group.vn.com.fitbites.MyFitbites.widgets"
    let directory: URL?
    private static var sharedDirectory: URL? {
        #if os(iOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        #else
        nil
        #endif
    }
    init(directory: URL? = sharedDirectory) {
        self.directory = directory
    }
    private var file: URL? { directory?.appendingPathComponent("widget-snapshot-v1.json") }
    func read() -> WidgetSnapshot {
        guard let file else { return unavailable() }
        guard FileManager.default.fileExists(atPath: file.path) else { return WidgetSnapshot() }
        do {
            let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: file))
            guard snapshot.version == WidgetSnapshot.version else { return unavailable() }
            return snapshot
        } catch { return unavailable() }
    }
    func write(_ snapshot: WidgetSnapshot) throws {
        guard let file, let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var url = file
        try url.setResourceValues(excluded)
    }
    private func unavailable() -> WidgetSnapshot {
        var snapshot = WidgetSnapshot(); snapshot.status = .unavailable; return snapshot
    }
}

// A generation is captured BEFORE each request. Logout/switching invalidates in-flight responses.
struct WidgetSnapshotSession {
    var snapshot: WidgetSnapshot
    private(set) var generation = UUID()
    init(snapshot: WidgetSnapshot = WidgetSnapshot()) { self.snapshot = snapshot }
    mutating func begin(accountKey: String) {
        generation = UUID()
        if snapshot.accountKey != accountKey || snapshot.status == .signedOut {
            snapshot = WidgetSnapshot(); snapshot.accountKey = accountKey; snapshot.status = .loading
        }
    }
    mutating func signOut() {
        generation = UUID(); snapshot = WidgetSnapshot()
    }
    mutating func accept(_ ticket: UUID, update: (inout WidgetSnapshot) -> Void) -> Bool {
        guard ticket == generation, snapshot.accountKey != nil, snapshot.status != .signedOut else { return false }
        update(&snapshot); snapshot.status = .ready; snapshot.updatedAt = Date(); return true
    }
}


// Separate from the app-owned data snapshot. Remember only the daily editorial choice,
// so account refreshes or another widget instance cannot reshuffle today's feature.
struct WidgetTodaySelectionStore {
    let directory: URL?
    init(directory: URL? = WidgetSnapshotStore().directory) { self.directory = directory }
    private struct Choice: Codable {
        let sessionID: String
        let day: Int
        let kind: WidgetTodayKind
    }
    func selection(for snapshot: WidgetSnapshot, at date: Date) -> WidgetTodayKind? {
        guard snapshot.status == .ready else { return nil }
        let day = WidgetTodayCalendar.dayNumber(date)
        let file = directory?.appendingPathComponent("today-choice-v1.json")
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(Choice.self, from: data),
           saved.sessionID == snapshot.sessionID, saved.day == day {
            return saved.kind
        }
        guard let kind = snapshot.todayKind(at: date) else { return nil }
        if let directory, let file, let data = try? JSONEncoder().encode(Choice(sessionID: snapshot.sessionID, day: day, kind: kind)) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if os(iOS)
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try? data.write(to: file, options: .atomic)
            #endif
        }
        return kind
    }
}
