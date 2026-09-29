import CoreLocation
import Foundation

struct OfficeLocation: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var radius: CLLocationDistance
    /// Minutes between entering the radius and actually timing in; nil uses the radius-based default.
    var timeInDelayMinutes: Int?

    private static let storageKey = "officeLocation"

    /// About 7 minutes from the building entrance to the time clock, plus walking the radius at 80 m/min (50 m -> 8 min).
    static func defaultTimeInDelayMinutes(radius: CLLocationDistance) -> Int {
        Int((7 + radius / 80).rounded())
    }

    var timeInDelay: TimeInterval {
        Double(timeInDelayMinutes ?? Self.defaultTimeInDelayMinutes(radius: radius)) * 60
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var condition: CLMonitor.CircularGeographicCondition {
        CLMonitor.CircularGeographicCondition(center: coordinate, radius: radius)
    }

    static var stored: OfficeLocation? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(OfficeLocation.self, from: data)
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.storageKey)
    }
}
