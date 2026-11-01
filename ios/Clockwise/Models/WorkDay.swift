import Foundation
import SwiftData

@Model
final class WorkDay {
    static let shiftDuration: TimeInterval = 9 * 60 * 60

    @Attribute(.unique) var day: Date
    var timeIn: Date
    /// The confirmed time out. Before `timeOut` (the earliest allowed time out) it's a shortfall.
    var leftAt: Date?
    /// When the user left the office area and hasn't come back or confirmed it as their time out yet.
    var departedAt: Date?
    /// The arrival was only noticed when the app was opened, so `timeIn` may be later than the real arrival.
    var isEstimated = false

    init(timeIn: Date) {
        self.day = Calendar.current.startOfDay(for: timeIn)
        self.timeIn = timeIn
    }

    var timeOut: Date { timeIn.addingTimeInterval(Self.shiftDuration) }

    var shortfall: TimeInterval? {
        guard let leftAt, leftAt < timeOut else { return nil }
        return timeOut.timeIntervalSince(leftAt)
    }

    var isTimeOutUnconfirmed: Bool { leftAt == nil && departedAt != nil }

    /// A likely shortfall from an early departure the user hasn't confirmed or dismissed.
    var unconfirmedShortfall: TimeInterval? {
        guard leftAt == nil, let departedAt, departedAt < timeOut else { return nil }
        return timeOut.timeIntervalSince(departedAt)
    }

    static func find(on date: Date, in context: ModelContext) -> WorkDay? {
        let day = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<WorkDay>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates the day's record on the first arrival. Returns nil if the day already has a time in.
    static func recordArrival(at date: Date, isEstimated: Bool = false, in context: ModelContext) -> WorkDay? {
        guard find(on: date, in: context) == nil else { return nil }
        let workDay = WorkDay(timeIn: date)
        workDay.isEstimated = isEstimated
        context.insert(workDay)
        try? context.save()
        return workDay
    }
}

extension TimeInterval {
    var hoursAndMinutes: String {
        Duration.seconds(self).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
