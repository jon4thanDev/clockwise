import SwiftData
import XCTest
@testable import Clockwise

@MainActor
final class WorkDayTests: XCTestCase {
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: WorkDay.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testTimeOutIsNineHoursAfterTimeIn() {
        let workDay = WorkDay(timeIn: date(29, 9, 12))
        XCTAssertEqual(workDay.timeOut, date(29, 18, 12))
        XCTAssertEqual(workDay.day, Calendar.current.startOfDay(for: date(29, 9, 12)))
    }

    func testShortfallOnlyWhenLeavingBeforeTimeOut() {
        let workDay = WorkDay(timeIn: date(29, 9))
        XCTAssertNil(workDay.shortfall)

        workDay.leftAt = date(29, 17, 30)
        XCTAssertEqual(workDay.shortfall, 30 * 60)

        workDay.leftAt = date(29, 18, 5)
        XCTAssertNil(workDay.shortfall)
    }

    func testRemindersFireThirtyAndThreeMinutesBeforeTimeOut() {
        let reminders = NotificationScheduler.reminders(timeOut: date(29, 18), now: date(29, 9))
        XCTAssertEqual(reminders.map(\.fireDate), [date(29, 17, 30), date(29, 17, 57)])
        XCTAssertEqual(reminders.map(\.minutesLeft), [30, 3])
    }

    func testPastRemindersAreSkipped() {
        let lateOpen = NotificationScheduler.reminders(timeOut: date(29, 18), now: date(29, 17, 45))
        XCTAssertEqual(lateOpen.map(\.minutesLeft), [3])

        XCTAssertTrue(NotificationScheduler.reminders(timeOut: date(29, 18), now: date(29, 18)).isEmpty)
    }

    func testFirstArrivalOfTheDayWins() throws {
        let context = try makeContext()

        let morning = try XCTUnwrap(WorkDay.recordArrival(at: date(29, 9), in: context))
        XCTAssertNil(WorkDay.recordArrival(at: date(29, 13), in: context), "Coming back from lunch must not create a new time in")
        XCTAssertEqual(WorkDay.find(on: date(29, 20), in: context)?.timeIn, morning.timeIn)

        let nextDay = try XCTUnwrap(WorkDay.recordArrival(at: date(30, 8, 45), in: context))
        XCTAssertEqual(nextDay.timeOut, date(30, 17, 45))
    }

    func testDefaultTimeInDelayGrowsWithRadius() {
        XCTAssertEqual(OfficeLocation.defaultTimeInDelayMinutes(radius: 50), 8)
        XCTAssertEqual(OfficeLocation.defaultTimeInDelayMinutes(radius: 150), 9)
        XCTAssertEqual(OfficeLocation.defaultTimeInDelayMinutes(radius: 500), 13)
    }

    func testCustomTimeInDelayOverridesDefault() {
        var office = OfficeLocation(latitude: 0, longitude: 0, radius: 50)
        XCTAssertEqual(office.timeInDelay, 8 * 60)

        office.timeInDelayMinutes = 3
        XCTAssertEqual(office.timeInDelay, 3 * 60)

        office.timeInDelayMinutes = nil
        XCTAssertEqual(office.timeInDelay, 8 * 60)
    }
}
