import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkDay.day, order: .reverse) private var days: [WorkDay]
    @AppStorage("shortfallPeriod") private var period = ShortfallPeriod.halfMonth
    @State private var offset = 0
    @State private var isSelecting = false
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var isConfirmingDelete = false
    @State private var timeOutDay: WorkDay?

    var body: some View {
        let interval = period.interval(offset: offset)
        let periodDays = days.filter { interval.contains($0.day) }
        let shortDays = periodDays.filter { $0.shortfall != nil }
        let total = shortDays.compactMap(\.shortfall).reduce(0, +)
        // Days still waiting for a confirmed time out.
        let pending = periodDays.filter { $0.leftAt == nil }
        let selected = pending.filter { selection.contains($0.persistentModelID) }
        let deletable = selected.filter { $0.departedAt != nil }

        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(ShortfallPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Button("Previous", systemImage: "chevron.left") { offset -= 1 }
                        Spacer()
                        Text(interval.start..<interval.end.addingTimeInterval(-1), format: .interval.month(.abbreviated).day())
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button("Next", systemImage: "chevron.right") { offset += 1 }
                            .disabled(offset >= 0)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total shortfall")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(total > 0 ? total.hoursAndMinutes : "None")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(total > 0 ? .red : .green)
                        Text("\(shortDays.count) of \(periodDays.count) days short")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    if periodDays.isEmpty {
                        Text("No days recorded in this period.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(periodDays) { workDay in
                        let isPending = workDay.leftAt == nil
                        let isSelected = selection.contains(workDay.persistentModelID)
                        HStack(spacing: 12) {
                            if isSelecting && isPending {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            }
                            dayRow(workDay)
                        }
                        .opacity(isSelecting && !isPending ? 0.4 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard isPending else { return }
                            if !isSelecting {
                                timeOutDay = workDay
                            } else if isSelected {
                                selection.remove(workDay.persistentModelID)
                            } else {
                                selection.insert(workDay.persistentModelID)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if isPending && !isSelecting {
                                Button("Time out", systemImage: "checkmark") { timeOutDay = workDay }
                                    .tint(.accentColor)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if !isSelecting {
                                if workDay.isTimeOutUnconfirmed {
                                    Button("Delete time out", systemImage: "xmark", role: .destructive) { discard([workDay]) }
                                } else {
                                    Button("Delete day", systemImage: "trash", role: .destructive) { deleteDay(workDay) }
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Days")
                        Spacer()
                        if isSelecting {
                            Button(selected.count == pending.count ? "Deselect All" : "Select All") {
                                selection = selected.count == pending.count ? [] : Set(pending.map(\.persistentModelID))
                            }
                            .font(.subheadline.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                } footer: {
                    if !pending.isEmpty {
                        Text("Tap a day without a confirmed time out to choose when you left. Early time outs count toward the total once confirmed. Tap Select to confirm or delete several at once.")
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { isSelecting = false }
                    }
                } else if !pending.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") { isSelecting = true }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    HStack {
                        Button("Confirm time out (\(selected.count))", systemImage: "checkmark") {
                            confirm(selected)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selected.isEmpty)
                        Spacer()
                        Button("Delete (\(deletable.count))", systemImage: "xmark", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(deletable.isEmpty)
                    }
                    .padding()
                    .background(.bar)
                }
            }
            .sheet(item: $timeOutDay) { TimeOutSheet(workDay: $0) }
            .alert("Delete \(deletable.count) unconfirmed time out\(deletable.count == 1 ? "" : "s")?", isPresented: $isConfirmingDelete) {
                Button("Delete", role: .destructive) { discard(deletable) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The days and their time in stay. Only the detected time outs that you haven't confirmed are removed.")
            }
            .onChange(of: period) { offset = 0 }
            .onChange(of: offset) { selection = [] }
            .onChange(of: isSelecting) { selection = [] }
            .onChange(of: pending.isEmpty) { _, isEmpty in
                if isEmpty { isSelecting = false }
            }
        }
    }

    private func dayRow(_ workDay: WorkDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workDay.day, format: .dateTime.weekday(.wide).month().day())
                    .font(.headline)
                if workDay.leftAt == nil {
                    Text("Unconfirmed time out")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            Text("""
                \(workDay.timeIn.formatted(date: .omitted, time: .shortened)) - \
                \((workDay.leftAt ?? workDay.departedAt ?? workDay.timeOut).formatted(date: .omitted, time: .shortened))
                """)
                .foregroundStyle(.secondary)
            if let shortfall = workDay.shortfall {
                Text("\(shortfall.hoursAndMinutes) short")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else if let shortfall = workDay.unconfirmedShortfall {
                Text("\(shortfall.hoursAndMinutes) short if confirmed")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// Uses the detected departure when there is one, otherwise the required time out (never a time in the future).
    private func confirm(_ workDays: [WorkDay]) {
        for workDay in workDays {
            workDay.leftAt = min(workDay.departedAt ?? workDay.timeOut, .now)
            workDay.departedAt = nil
            if Calendar.current.isDateInToday(workDay.day) {
                notifications.cancelReminders()
                notifications.cancelEarlyOutWarning()
            }
        }
        try? modelContext.save()
        selection = []
    }

    private func discard(_ workDays: [WorkDay]) {
        for workDay in workDays {
            workDay.departedAt = nil
        }
        try? modelContext.save()
        selection = []
    }

    private func deleteDay(_ workDay: WorkDay) {
        if Calendar.current.isDateInToday(workDay.day) {
            notifications.cancelReminders()
        }
        modelContext.delete(workDay)
        try? modelContext.save()
    }
}
