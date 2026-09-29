import Foundation
import SwiftData

@Model
final class WorkDay {
    static let shiftDuration: TimeInterval = 9 * 60 * 60

    @Attribute(.unique) var day: Date
    var timeIn: Date
    /// Set only when the user confirms they timed out before `timeOut`.
    var leftAt: Date?

    init(timeIn: Date) {
        self.day = Calendar.current.startOfDay(for: timeIn)
        self.timeIn = timeIn
    }

    var timeOut: Date { timeIn.addingTimeInterval(Self.shiftDuration) }

    var shortfall: TimeInterval? {
        guard let leftAt, leftAt < timeOut else { return nil }
        return timeOut.timeIntervalSince(leftAt)
    }

    static func find(on date: Date, in context: ModelContext) -> WorkDay? {
        let day = Calendar.current.startOfDay(for: date)
        var descriptor = FetchDescriptor<WorkDay>(predicate: #Predicate { $0.day == day })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Creates the day's record on the first arrival. Returns nil if the day already has a time in.
    static func recordArrival(at date: Date, in context: ModelContext) -> WorkDay? {
        guard find(on: date, in: context) == nil else { return nil }
        let workDay = WorkDay(timeIn: date)
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
