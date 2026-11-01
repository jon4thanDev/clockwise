import Foundation

/// The span of days a shortfall total covers, matching common payroll cutoffs.
enum ShortfallPeriod: String, CaseIterable, Identifiable {
    case week
    case twoWeeks
    case halfMonth
    case month

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "Week"
        case .twoWeeks: "2 weeks"
        case .halfMonth: "Cutoff"
        case .month: "Month"
        }
    }

    /// Describes the current period, e.g. "this cutoff".
    var currentLabel: String {
        switch self {
        case .week: "this week"
        case .twoWeeks: "in the last 2 weeks"
        case .halfMonth: "this cutoff"
        case .month: "this month"
        }
    }

    /// `offset` 0 is the period containing `now`, -1 the one before it, and so on.
    /// Cutoffs are the 1st-15th and the 16th-end of month; "2 weeks" is the rolling 14 days ending today.
    func interval(offset: Int, now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .week:
            let date = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
            return calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 0)

        case .twoWeeks:
            let end = calendar.date(byAdding: .day, value: 1 + 14 * offset, to: calendar.startOfDay(for: now)) ?? now
            return DateInterval(start: calendar.date(byAdding: .day, value: -14, to: end) ?? end, end: end)

        case .halfMonth:
            let today = calendar.dateComponents([.year, .month, .day], from: now)
            let index = ((today.year ?? 0) * 12 + (today.month ?? 1) - 1) * 2 + ((today.day ?? 1) > 15 ? 1 : 0) + offset
            func start(ofHalf index: Int) -> Date {
                calendar.date(from: DateComponents(
                    year: index / 24, month: index % 24 / 2 + 1, day: index.isMultiple(of: 2) ? 1 : 16)) ?? now
            }
            return DateInterval(start: start(ofHalf: index), end: start(ofHalf: index + 1))

        case .month:
            let date = calendar.date(byAdding: .month, value: offset, to: now) ?? now
            return calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        }
    }
}
