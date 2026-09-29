import CoreLocation
import Foundation
import SwiftData

/// A place the user stayed at, as reported by iOS visit monitoring.
@Model
final class Visit {
    static let retention: TimeInterval = 60 * 24 * 60 * 60

    var latitude: Double
    var longitude: Double
    var arrival: Date
    var departure: Date

    init(latitude: Double, longitude: Double, arrival: Date, departure: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.arrival = arrival
        self.departure = departure
    }
}

/// The place the user most often spends the workday at, learned from their visits.
struct OfficeSuggestion: Equatable {
    static let requiredDays = 3
    static let clusterRadius: CLLocationDistance = 150
    static let minimumDailyStay: TimeInterval = 4 * 60 * 60
    /// Workday arrivals start in this window; it filters out home, where stays span the night or start in the evening.
    static let arrivalHours = 5..<14

    let latitude: Double
    let longitude: Double
    let dayCount: Int
    let usualArrivalMinutes: Int

    var isConfident: Bool { dayCount >= Self.requiredDays }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var usualArrival: Date {
        Calendar.current.date(
            bySettingHour: usualArrivalMinutes / 60, minute: usualArrivalMinutes % 60, second: 0, of: .now) ?? .now
    }

    /// Returns the best candidate even when it isn't confident yet, so the UI can show learning progress.
    static func detect(from visits: [Visit], calendar: Calendar = .current) -> OfficeSuggestion? {
        let daytimeVisits = visits.filter {
            calendar.isDate($0.arrival, inSameDayAs: $0.departure)
                && arrivalHours.contains(calendar.component(.hour, from: $0.arrival))
        }

        var clusters: [[Visit]] = []
        for visit in daytimeVisits.sorted(by: { $0.arrival < $1.arrival }) {
            let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
            if let index = clusters.firstIndex(where: { centroid(of: $0).distance(from: location) <= clusterRadius }) {
                clusters[index].append(visit)
            } else {
                clusters.append([visit])
            }
        }

        return clusters.compactMap { cluster -> OfficeSuggestion? in
            // A lunch break splits a workday into several visits, so stays are summed per day.
            let workdays = Dictionary(grouping: cluster) { calendar.startOfDay(for: $0.arrival) }
                .values
                .filter { $0.reduce(0) { $0 + $1.departure.timeIntervalSince($1.arrival) } >= minimumDailyStay }
            guard !workdays.isEmpty else { return nil }

            let arrivalMinutes = workdays
                .compactMap { $0.map(\.arrival).min() }
                .map { calendar.component(.hour, from: $0) * 60 + calendar.component(.minute, from: $0) }
                .sorted()
            let center = centroid(of: cluster).coordinate
            return OfficeSuggestion(
                latitude: center.latitude,
                longitude: center.longitude,
                dayCount: workdays.count,
                usualArrivalMinutes: arrivalMinutes[arrivalMinutes.count / 2]
            )
        }
        .max { $0.dayCount < $1.dayCount }
    }

    private static func centroid(of visits: [Visit]) -> CLLocation {
        let count = Double(visits.count)
        return CLLocation(
            latitude: visits.map(\.latitude).reduce(0, +) / count,
            longitude: visits.map(\.longitude).reduce(0, +) / count
        )
    }
}
