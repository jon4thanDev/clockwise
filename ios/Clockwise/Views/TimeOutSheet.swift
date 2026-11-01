import SwiftData
import SwiftUI

/// Lets the user choose when they actually left, starting from the detected departure if there is one.
struct TimeOutSheet: View {
    let workDay: WorkDay

    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(workDay: WorkDay) {
        self.workDay = workDay
        _time = State(initialValue: min(workDay.departedAt ?? workDay.timeOut, .now))
    }

    var body: some View {
        let isToday = Calendar.current.isDateInToday(workDay.day)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: workDay.day)?.addingTimeInterval(-60) ?? workDay.timeOut
        let latest = max(isToday ? Date.now : endOfDay, workDay.timeIn)

        NavigationStack {
            Form {
                Section {
                    DatePicker("Timed out at", selection: $time, in: workDay.timeIn...latest, displayedComponents: .hourAndMinute)
                    LabeledContent("Time in", value: workDay.timeIn.formatted(date: .omitted, time: .shortened))
                    LabeledContent("Required time out", value: workDay.timeOut.formatted(date: .omitted, time: .shortened))
                } footer: {
                    if let departedAt = workDay.departedAt {
                        Text("Clockwise saw you leave the office area at \(departedAt.formatted(date: .omitted, time: .shortened)).")
                    } else {
                        Text("Clockwise didn't detect when you left the office area, so choose the time yourself.")
                    }
                }
                Section {
                    if time < workDay.timeOut {
                        Text("\(workDay.timeOut.timeIntervalSince(time).hoursAndMinutes) short")
                            .foregroundStyle(.red)
                    } else {
                        Text("Full day, no shortfall")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle(isToday ? "When did you leave?" : workDay.day.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        workDay.leftAt = time
                        workDay.departedAt = nil
                        try? modelContext.save()
                        if isToday {
                            notifications.cancelReminders()
                            notifications.cancelEarlyOutWarning()
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
