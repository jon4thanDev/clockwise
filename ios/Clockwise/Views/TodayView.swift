import CoreLocation
import SwiftData
import SwiftUI

struct TodayView: View {
    var onSetOffice: () -> Void

    @Environment(OfficeMonitor.self) private var monitor
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \WorkDay.day, order: .reverse) private var days: [WorkDay]
    @Query private var visits: [Visit]
    @State private var isEditingTimeIn = false
    @State private var isConfirmingAwayTimeIn = false
    @State private var isConfirmingRemoval = false

    private var today: WorkDay? {
        days.first { Calendar.current.isDateInToday($0.day) }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                List {
                    setupSection
                    if let today {
                        shiftSection(today, now: context.date)
                    } else {
                        Section {
                            Text("No time in yet today. It will be recorded automatically when you arrive at the office.")
                                .foregroundStyle(.secondary)
                            Button("I'm in now", systemImage: "figure.walk.arrival") {
                                if monitor.isInsideOffice == false {
                                    isConfirmingAwayTimeIn = true
                                } else {
                                    timeInNow()
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Today")
            .sheet(isPresented: $isEditingTimeIn) {
                if let today {
                    TimeInEditor(workDay: today)
                }
            }
            .alert("You're not at the office", isPresented: $isConfirmingAwayTimeIn) {
                Button("Time in anyway") { timeInNow() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clockwise hasn't detected you inside the office area. If you time in now, your real arrival later today won't be recorded automatically.")
            }
            .alert("Remove today's time in?", isPresented: $isConfirmingRemoval) {
                Button("Remove", role: .destructive) {
                    guard let today else { return }
                    modelContext.delete(today)
                    try? modelContext.save()
                    notifications.cancelReminders()
                    notifications.cancelEarlyOutWarning()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Today's reminders are cancelled. If you arrive at the office later today, your time in will be recorded automatically again.")
            }
        }
    }

    private func timeInNow() {
        if let workDay = WorkDay.recordArrival(at: .now, in: modelContext) {
            notifications.scheduleReminders(timeOut: workDay.timeOut)
        }
    }

    @ViewBuilder
    private var setupSection: some View {
        let needsAlways = monitor.authorization != .authorizedAlways
        if monitor.office == nil || needsAlways || !notifications.isAuthorized {
            Section("Setup") {
                if monitor.office == nil {
                    if OfficeSuggestion.detect(from: visits)?.isConfident == true {
                        Button("We found your likely office. Review it", systemImage: "sparkles", action: onSetOffice)
                    } else {
                        Button("Set your office location", systemImage: "mappin.and.ellipse", action: onSetOffice)
                    }
                }
                if needsAlways {
                    Button("Allow location access \"Always\"", systemImage: "location") {
                        if monitor.authorization == .notDetermined {
                            monitor.requestAuthorization()
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
                if !notifications.isAuthorized {
                    Button("Turn on notifications", systemImage: "bell.badge") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
        } else if let isInside = monitor.isInsideOffice {
            Section {
                Label(
                    isInside ? "At the office" : "Away from the office",
                    systemImage: isInside ? "building.2.fill" : "figure.walk.departure"
                )
                .foregroundStyle(isInside ? .green : .orange)
            }
        }
    }

    private func shiftSection(_ workDay: WorkDay, now: Date) -> some View {
        let remaining = workDay.timeOut.timeIntervalSince(now)
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                if let leftAt = workDay.leftAt, let shortfall = workDay.shortfall {
                    Text("Left at \(leftAt.formatted(date: .omitted, time: .shortened))")
                        .font(.title2.bold())
                    Text("\(shortfall.hoursAndMinutes) short today")
                        .foregroundStyle(.red)
                } else if remaining > 0 {
                    Text(Duration.seconds(remaining).formatted(.time(pattern: .hourMinuteSecond)))
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    Text("until you can time out")
                        .foregroundStyle(.secondary)
                    ProgressView(value: WorkDay.shiftDuration - remaining, total: WorkDay.shiftDuration)
                } else {
                    Text("You can time out now")
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 8)

            LabeledContent("Time in", value: workDay.timeIn.formatted(date: .omitted, time: .shortened))
            LabeledContent("Time out", value: workDay.timeOut.formatted(date: .omitted, time: .shortened))
            Button("Edit time in", systemImage: "pencil") { isEditingTimeIn = true }
            Button("Remove today's time in", systemImage: "trash", role: .destructive) { isConfirmingRemoval = true }
        }
    }
}

private struct TimeInEditor: View {
    let workDay: WorkDay

    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var timeIn: Date

    init(workDay: WorkDay) {
        self.workDay = workDay
        _timeIn = State(initialValue: workDay.timeIn)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time in", selection: $timeIn, displayedComponents: .hourAndMinute)
                LabeledContent(
                    "Time out",
                    value: timeIn.addingTimeInterval(WorkDay.shiftDuration).formatted(date: .omitted, time: .shortened)
                )
            }
            .navigationTitle("Edit time in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        workDay.timeIn = timeIn
                        try? modelContext.save()
                        if workDay.leftAt == nil {
                            notifications.scheduleReminders(timeOut: workDay.timeOut)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
