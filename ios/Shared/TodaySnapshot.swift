import Foundation

/// Today's shift as seen by the widget. The app writes it to the shared App Group whenever the day changes.
struct TodaySnapshot: Codable, Equatable {
    static let appGroup = "group.com.tan.clockwise"
    private static let storageKey = "todaySnapshot"

    var timeIn: Date
    var timeOut: Date

    static var stored: TodaySnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(TodaySnapshot.self, from: data)
    }

    static func save(_ snapshot: TodaySnapshot?) {
        UserDefaults(suiteName: appGroup)?.set(snapshot.flatMap { try? JSONEncoder().encode($0) }, forKey: storageKey)
    }
}
