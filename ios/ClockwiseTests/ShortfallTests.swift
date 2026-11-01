import XCTest
@testable import Clockwise

final class ShortfallTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    // Tuesday, Sep 29 2026
    private var now: Date { date(9, 29, 15) }

    func testCutoffIsFirstOrSecondHalfOfMonth() {
        XCTAssertEqual(ShortfallPeriod.halfMonth.interval(offset: 0, now: now, calendar: calendar),
                       DateInterval(start: date(9, 16), end: date(10, 1)))
        XCTAssertEqual(ShortfallPeriod.halfMonth.interval(offset: -1, now: now, calendar: calendar),
                       DateInterval(start: date(9, 1), end: date(9, 16)))
        XCTAssertEqual(ShortfallPeriod.halfMonth.interval(offset: -2, now: now, calendar: calendar),
                       DateInterval(start: date(8, 16), end: date(9, 1)))
        XCTAssertEqual(ShortfallPeriod.halfMonth.interval(offset: 0, now: date(1, 10), calendar: calendar),
                       DateInterval(start: date(1, 1), end: date(1, 16)))
    }

    func testWeekMonthAndTwoWeeks() {
        XCTAssertEqual(ShortfallPeriod.week.interval(offset: 0, now: now, calendar: calendar),
                       DateInterval(start: date(9, 28), end: date(10, 5)))
        XCTAssertEqual(ShortfallPeriod.month.interval(offset: -1, now: now, calendar: calendar),
                       DateInterval(start: date(8, 1), end: date(9, 1)))
        XCTAssertEqual(ShortfallPeriod.twoWeeks.interval(offset: 0, now: now, calendar: calendar),
                       DateInterval(start: date(9, 16), end: date(9, 30)))
        XCTAssertEqual(ShortfallPeriod.twoWeeks.interval(offset: -1, now: now, calendar: calendar),
                       DateInterval(start: date(9, 2), end: date(9, 16)))
    }

    func testUnconfirmedShortfallUntilAnswered() {
        let workDay = WorkDay(timeIn: date(9, 29, 9))
        XCTAssertNil(workDay.unconfirmedShortfall)

        workDay.departedAt = date(9, 29, 17, 40)
        XCTAssertEqual(workDay.unconfirmedShortfall, 20 * 60)
        XCTAssertNil(workDay.shortfall, "Unconfirmed departures don't count toward the total")

        workDay.leftAt = workDay.departedAt
        workDay.departedAt = nil
        XCTAssertNil(workDay.unconfirmedShortfall)
        XCTAssertEqual(workDay.shortfall, 20 * 60)
    }
}
