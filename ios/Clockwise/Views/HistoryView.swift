import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkDay.day, order: .reverse) private var days: [WorkDay]

    var body: some View {
        NavigationStack {
            List {
                ForEach(days) { workDay in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workDay.day, format: .dateTime.weekday(.wide).month().day())
                            .font(.headline)
                        Text("""
                            \(workDay.timeIn.formatted(date: .omitted, time: .shortened)) - \
                            \((workDay.leftAt ?? workDay.timeOut).formatted(date: .omitted, time: .shortened))
                            """)
                            .foregroundStyle(.secondary)
                        if let shortfall = workDay.shortfall {
                            Text("\(shortfall.hoursAndMinutes) short")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        if Calendar.current.isDateInToday(days[index].day) {
                            notifications.cancelReminders()
                        }
                        modelContext.delete(days[index])
                    }
                    try? modelContext.save()
                }
            }
            .overlay {
                if days.isEmpty {
                    ContentUnavailableView(
                        "No days yet",
                        systemImage: "calendar",
                        description: Text("Your time in will appear here once you arrive at the office.")
                    )
                }
            }
            .navigationTitle("History")
        }
    }
}
