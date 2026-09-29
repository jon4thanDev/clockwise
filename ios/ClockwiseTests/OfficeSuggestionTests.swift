import XCTest
@testable import Clockwise

final class OfficeSuggestionTests: XCTestCase {
    private let office = (latitude: 14.5547, longitude: 121.0244)
    private let home = (latitude: 14.6091, longitude: 121.0223)

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func visit(_ place: (latitude: Double, longitude: Double), from arrival: Date, to departure: Date,
                       jitter: Double = 0) -> Visit {
        Visit(latitude: place.latitude + jitter, longitude: place.longitude - jitter, arrival: arrival, departure: departure)
    }

    /// A workday with a lunch break outside, plus the night at home.
    private func workday(_ day: Int, arrivingAt minute: Int) -> [Visit] {
        [
            visit(office, from: date(day, 9, minute), to: date(day, 12), jitter: 0.0003),
            visit(office, from: date(day, 13), to: date(day, 18), jitter: -0.0002),
            visit(home, from: date(day, 19), to: date(day + 1, 8)),
        ]
    }

    func testSuggestsOfficeAfterThreeWorkdays() throws {
        let visits = workday(21, arrivingAt: 5) + workday(22, arrivingAt: 10) + workday(23, arrivingAt: 0)

        let suggestion = try XCTUnwrap(OfficeSuggestion.detect(from: visits))

        XCTAssertTrue(suggestion.isConfident)
        XCTAssertEqual(suggestion.dayCount, 3)
        XCTAssertEqual(suggestion.usualArrivalMinutes, 9 * 60 + 5)
        XCTAssertEqual(suggestion.latitude, office.latitude, accuracy: 0.001)
        XCTAssertEqual(suggestion.longitude, office.longitude, accuracy: 0.001)
    }

    func testNotConfidentWithTooFewWorkdays() throws {
        let suggestion = try XCTUnwrap(OfficeSuggestion.detect(from: workday(21, arrivingAt: 0) + workday(22, arrivingAt: 0)))
        XCTAssertFalse(suggestion.isConfident)
        XCTAssertEqual(suggestion.dayCount, 2)
    }

    func testShortOrOvernightStaysAreIgnored() {
        let visits = [
            visit(office, from: date(21, 10), to: date(21, 11)),
            visit(home, from: date(21, 20), to: date(22, 8)),
            visit(home, from: date(22, 20), to: date(23, 8)),
        ]
        XCTAssertNil(OfficeSuggestion.detect(from: visits))
    }

    func testPicksThePlaceWithTheMostWorkdays() throws {
        let weekendHome = [
            visit(home, from: date(26, 10), to: date(26, 20)),
            visit(home, from: date(27, 10), to: date(27, 20)),
        ]
        let visits = weekendHome + (21...25).flatMap { workday($0, arrivingAt: 0) }

        let suggestion = try XCTUnwrap(OfficeSuggestion.detect(from: visits))

        XCTAssertEqual(suggestion.dayCount, 5)
        XCTAssertEqual(suggestion.latitude, office.latitude, accuracy: 0.001)
    }
}
