import SwiftData
import SwiftUI

struct RootView: View {
    enum Screen { case today, office, history }

    @Environment(OfficeMonitor.self) private var monitor
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var screen = Screen.today

    var body: some View {
        TabView(selection: $screen) {
            TodayView(onSetOffice: { screen = .office }, onShowHistory: { screen = .history })
                .tabItem { Label("Today", systemImage: "clock") }
                .tag(Screen.today)
            OfficeSetupView()
                .tabItem { Label("Office", systemImage: "building.2") }
                .tag(Screen.office)
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(Screen.history)
        }
        .task {
            monitor.requestAuthorization()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                Task { await notifications.requestAuthorization() }
            }
        }
        .alert(
            "Did you time out?",
            isPresented: Binding(
                get: { notifications.pendingEarlyOut != nil },
                set: { if !$0 { notifications.pendingEarlyOut = nil } }
            ),
            presenting: notifications.pendingEarlyOut
        ) { leftAt in
            Button("Yes, I left at \(leftAt.formatted(date: .omitted, time: .shortened))", role: .destructive) {
                guard let workDay = WorkDay.find(on: leftAt, in: modelContext) else { return }
                workDay.leftAt = leftAt
                workDay.departedAt = nil
                try? modelContext.save()
                notifications.cancelReminders()
            }
            Button("No, I just stepped out", role: .cancel) {
                WorkDay.find(on: leftAt, in: modelContext)?.departedAt = nil
                try? modelContext.save()
            }
        } message: { leftAt in
            if let workDay = WorkDay.find(on: leftAt, in: modelContext) {
                Text("""
                    You left the office area at \(leftAt.formatted(date: .omitted, time: .shortened)), \
                    \(workDay.timeOut.timeIntervalSince(leftAt).hoursAndMinutes) before your time out \
                    (\(workDay.timeOut.formatted(date: .omitted, time: .shortened))). \
                    If you only stepped out for a moment, nothing will be recorded.
                    """)
            }
        }
    }
}
