import CoreLocation
import Observation
import SwiftData

@MainActor
@Observable
final class OfficeMonitor: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var office = OfficeLocation.stored
    private(set) var isInsideOffice: Bool?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let monitorTask = Task { await CLMonitor("ClockwiseOffice") }
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let notifications: NotificationScheduler

    private static let conditionID = "office"
    private static let insideKey = "wasInsideOffice"

    init(container: ModelContainer, notifications: NotificationScheduler) {
        self.container = container
        self.notifications = notifications
        authorization = manager.authorizationStatus
        super.init()
        if office != nil, UserDefaults.standard.object(forKey: Self.insideKey) != nil {
            isInsideOffice = UserDefaults.standard.bool(forKey: Self.insideKey)
        }
        manager.delegate = self
    }

    /// Must run on every launch: iOS relaunches the app in the background to deliver geofence events.
    func start() {
        Task {
            let monitor = await monitorTask.value
            if let office, await monitor.record(for: Self.conditionID) == nil {
                await monitor.add(office.condition, identifier: Self.conditionID)
            }
            do {
                for try await event in await monitor.events {
                    handle(event)
                }
            } catch {}
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
        Task {
            let monitor = await monitorTask.value
            await monitor.remove(Self.conditionID)
            await monitor.add(location.condition, identifier: Self.conditionID)
        }
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
        Task { @MainActor in
            authorization = status
            if status == .authorizedWhenInUse {
                self.manager.requestAlwaysAuthorization()
            }
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                // Low-power; iOS relaunches the app in the background to deliver visits.
                self.manager.startMonitoringVisits()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // In-progress or open-ended visits carry distantPast/distantFuture dates.
        guard visit.arrivalDate != .distantPast, visit.departureDate != .distantFuture else { return }
        let record = (visit.coordinate, visit.arrivalDate, visit.departureDate)
        Task { @MainActor in
            let context = container.mainContext
            context.insert(Visit(
                latitude: record.0.latitude, longitude: record.0.longitude, arrival: record.1, departure: record.2))
            let cutoff = Date.now.addingTimeInterval(-Visit.retention)
            try? context.delete(model: Visit.self, where: #Predicate { $0.departure < cutoff })
            try? context.save()
        }
    }

    private func handle(_ event: CLMonitor.Event) {
        let context = container.mainContext
        let wasInside = isInsideOffice == true

        switch event.state {
        case .satisfied:
            isInsideOffice = true
            notifications.cancelEarlyOutWarning()
            let timeIn = event.date.addingTimeInterval(office?.timeInDelay ?? 0)
            if let workDay = WorkDay.recordArrival(at: timeIn, in: context) {
                notifications.scheduleReminders(timeOut: workDay.timeOut)
            } else if let workDay = WorkDay.find(on: event.date, in: context), workDay.leftAt != nil {
                // Came back after confirming an early out, so the shift is still on.
                workDay.leftAt = nil
                try? context.save()
                notifications.scheduleReminders(timeOut: workDay.timeOut)
            }

        case .unsatisfied:
            isInsideOffice = false
            // The first state reported after setting up the office is not a real departure.
            guard wasInside,
                  let workDay = WorkDay.find(on: event.date, in: context),
                  workDay.leftAt == nil,
                  event.date < workDay.timeOut
            else { break }
            notifications.scheduleEarlyOutWarning(leftAt: event.date, timeOut: workDay.timeOut)

        default:
            break
        }

        if let isInsideOffice {
            UserDefaults.standard.set(isInsideOffice, forKey: Self.insideKey)
        }
    }
}
