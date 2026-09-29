import SwiftData
import SwiftUI
import UserNotifications
import WidgetKit

@main
struct ClockwiseApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appDelegate.monitor)
                .environment(appDelegate.notifications)
        }
        .modelContainer(appDelegate.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let container: ModelContainer
    let notifications = NotificationScheduler()
    let monitor: OfficeMonitor

    override init() {
        do {
            container = try ModelContainer(for: WorkDay.self, Visit.self)
        } catch {
            fatalError("Could not open the Clockwise database: \(error)")
        }
        monitor = OfficeMonitor(container: container, notifications: notifications)
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // The delegate must be set before launch finishes so taps on banners are delivered.
        UNUserNotificationCenter.current().delegate = notifications
        monitor.start()

        // Every change to a WorkDay (arrival, edit, delete) goes through a save, including background arrivals.
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWidget() }
        }
        refreshWidget()
        return true
    }

    private func refreshWidget() {
        let snapshot = WorkDay.find(on: .now, in: container.mainContext)
            .map { TodaySnapshot(timeIn: $0.timeIn, timeOut: $0.timeOut) }
        guard snapshot != TodaySnapshot.stored else { return }
        TodaySnapshot.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
