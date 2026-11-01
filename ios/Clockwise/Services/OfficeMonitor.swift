import CoreLocation
import Observation
import SwiftData

@MainActor
@Observable
final class OfficeMonitor: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var hasPreciseLocation: Bool
    private(set) var office = OfficeLocation.stored
    private(set) var isInsideOffice: Bool?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let notifications: NotificationScheduler
    /// A launch-time state check reports where the user is, not when they crossed the boundary.
    @ObservationIgnored private var isCheckingInitialState = false

    private static let insideKey = "wasInsideOffice"
    private static let removedLegacyMonitorKey = "removedCLMonitor"

    init(container: ModelContainer, notifications: NotificationScheduler) {
        self.container = container
        self.notifications = notifications
        authorization = manager.authorizationStatus
        hasPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
        super.init()
        if office != nil, UserDefaults.standard.object(forKey: Self.insideKey) != nil {
            isInsideOffice = UserDefaults.standard.bool(forKey: Self.insideKey)
        }
        manager.delegate = self
    }

    /// Must run on every launch: iOS relaunches the app in the background to deliver region and visit events.
    /// `launchedForLocation` skips the state check, since iOS is about to deliver the crossing itself.
    func start(launchedForLocation: Bool) {
        if !UserDefaults.standard.bool(forKey: Self.removedLegacyMonitorKey) {
            // Earlier builds used CLMonitor, which didn't reliably wake the app; drop its leftover condition.
            Task {
                await CLMonitor("ClockwiseOffice").remove(OfficeLocation.regionID)
                UserDefaults.standard.set(true, forKey: Self.removedLegacyMonitorKey)
            }
        }

        guard let office else { return }
        let monitored = manager.monitoredRegions.first { $0.identifier == OfficeLocation.regionID } as? CLCircularRegion
        if monitored?.center.latitude != office.latitude
            || monitored?.center.longitude != office.longitude
            || monitored?.radius != office.radius {
            manager.startMonitoring(for: office.region)
        }
        if !launchedForLocation {
            isCheckingInitialState = true
            manager.requestState(for: office.region)
        }
    }

    func setOffice(_ location: OfficeLocation) {
        let areaChanged = office.map {
            $0.latitude != location.latitude || $0.longitude != location.longitude || $0.radius != location.radius
        } ?? true
        location.save()
        office = location
        guard areaChanged else { return }
        isInsideOffice = nil
        UserDefaults.standard.removeObject(forKey: Self.insideKey)
        manager.startMonitoring(for: location.region)
        isCheckingInitialState = true
        manager.requestState(for: location.region)
    }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let isPrecise = manager.accuracyAuthorization == .fullAccuracy
        Task { @MainActor in
            authorization = status
            hasPreciseLocation = isPrecise
            if status == .authorizedWhenInUse {
                self.manager.requestAlwaysAuthorization()
            }
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                // Low-power; iOS relaunches the app in the background to deliver visits.
                self.manager.startMonitoringVisits()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == OfficeLocation.regionID else { return }
        let date = Date.now
        Task { @MainActor in handleEntry(at: date, isEstimated: false) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == OfficeLocation.regionID else { return }
        let date = Date.now
        Task { @MainActor in handleExit(at: date) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard region.identifier == OfficeLocation.regionID else { return }
        let date = Date.now
        Task { @MainActor in
            // Real crossings arrive through didEnterRegion/didExitRegion; only the launch check is handled here.
            guard isCheckingInitialState else { return }
            isCheckingInitialState = false
            switch state {
            case .inside:
                handleEntry(at: date, isEstimated: true)
            case .outside:
                isInsideOffice = false
                UserDefaults.standard.set(false, forKey: Self.insideKey)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // Arrival is distantPast when unknown; departure is distantFuture while the visit is still in progress.
        guard visit.arrivalDate != .distantPast else { return }
        let coordinate = visit.coordinate
        let arrival = visit.arrivalDate
        let departure = visit.departureDate
        Task { @MainActor in
            handleVisitArrival(at: coordinate, arrival: arrival)
            guard departure != .distantFuture else { return }
            let context = container.mainContext
            context.insert(Visit(
                latitude: coordinate.latitude, longitude: coordinate.longitude, arrival: arrival, departure: departure))
            let cutoff = Date.now.addingTimeInterval(-Visit.retention)
            try? context.delete(model: Visit.self, where: #Predicate { $0.departure < cutoff })
            try? context.save()
        }
    }

    private func handleEntry(at date: Date, isEstimated: Bool) {
        let context = container.mainContext
        isInsideOffice = true
        UserDefaults.standard.set(true, forKey: Self.insideKey)
        notifications.cancelEarlyOutWarning()

        if let workDay = WorkDay.find(on: date, in: context) {
            // Back in the office, so stepping out didn't end the shift.
            workDay.departedAt = nil
            if workDay.leftAt != nil {
                workDay.leftAt = nil
                notifications.scheduleReminders(timeOut: workDay.timeOut)
            }
            try? context.save()
        } else {
            // An estimated arrival already happened a while ago, so the walk-in delay doesn't apply.
            let timeIn = isEstimated ? date : date.addingTimeInterval(office?.timeInDelay ?? 0)
            if let workDay = WorkDay.recordArrival(at: timeIn, isEstimated: isEstimated, in: context) {
                notifications.scheduleReminders(timeOut: workDay.timeOut)
            }
        }
    }

    private func handleExit(at date: Date) {
        let context = container.mainContext
        isInsideOffice = false
        UserDefaults.standard.set(false, forKey: Self.insideKey)
        guard let workDay = WorkDay.find(on: date, in: context), workDay.leftAt == nil else { return }
        workDay.departedAt = date
        try? context.save()
        if date < workDay.timeOut {
            notifications.scheduleEarlyOutWarning(leftAt: date, timeOut: workDay.timeOut)
        }
    }

    /// Visits report the real arrival time even when delivered late, so they back up missed or estimated arrivals.
    private func handleVisitArrival(at coordinate: CLLocationCoordinate2D, arrival: Date) {
        guard let office, Calendar.current.isDateInToday(arrival) else { return }
        let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: office.latitude, longitude: office.longitude))
        // Visit coordinates are approximate, so allow some slack beyond the radius.
        guard distance <= office.radius + 100 else { return }

        let context = container.mainContext
        let timeIn = arrival.addingTimeInterval(office.timeInDelay)
        if let workDay = WorkDay.find(on: arrival, in: context) {
            guard workDay.isEstimated, timeIn < workDay.timeIn else { return }
            workDay.timeIn = timeIn
            workDay.isEstimated = false
            try? context.save()
            if workDay.leftAt == nil {
                notifications.scheduleReminders(timeOut: workDay.timeOut)
            }
        } else if let workDay = WorkDay.recordArrival(at: timeIn, in: context) {
            notifications.scheduleReminders(timeOut: workDay.timeOut)
        }
    }
}
