import CoreLocation
import SwiftData
import SwiftUI

private enum TimeOutStep: Identifiable {
    case options, picker
    var id: Self { self }
}

struct TodayView: View {
    var onSetOffice: () -> Void
    var onShowHistory: () -> Void

    @Environment(OfficeMonitor.self) private var monitor
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \WorkDay.day, order: .reverse) private var days: [WorkDay]
    @Query private var visits: [Visit]
    @AppStorage("shortfallPeriod") private var period = ShortfallPeriod.halfMonth
    @State private var isEditingTimeIn = false
    @State private var isConfirmingAwayTimeIn = false
    @State private var isConfirmingRemoval = false
    @State private var timeOutStep: TimeOutStep?

    private var today: WorkDay? {
        days.first { Calendar.current.isDateInToday($0.day) }
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    VStack(spacing: 16) {
                        header(now: context.date)
                        setupCard
                        progressCard(now: context.date)
                        if let today {
                            timesCard(today)
                            if today.leftAt == nil, let departedAt = today.departedAt {
                                departureCard(today, departedAt: departedAt)
                            }
                        }
                        shortfallCard
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .background(Color(.systemGroupedBackground))
                .safeAreaInset(edge: .bottom) { actionBar(now: context.date) }
            }
            .navigationTitle("Today")
            .toolbar {
                if today != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit times", systemImage: "pencil") { isEditingTimeIn = true }
                            Button("Remove today's time in", systemImage: "trash", role: .destructive) {
                                isConfirmingRemoval = true
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .sensoryFeedback(trigger: today?.leftAt) { _, newValue in newValue != nil ? .success : nil }
            .sheet(isPresented: $isEditingTimeIn) {
                if let today {
                    TimeInEditor(workDay: today)
                }
            }
            .sheet(item: $timeOutStep) { step in
                if let today {
                    switch step {
                    case .options: timeOutOptions(today)
                    case .picker: TimeOutSheet(workDay: today)
                    }
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

    // MARK: - Sections

    private func header(now: Date) -> some View {
        HStack {
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            if let isInside = monitor.isInsideOffice {
                Label(isInside ? "At the office" : "Away", systemImage: isInside ? "building.2.fill" : "figure.walk")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((isInside ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(isInside ? .green : .orange)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var setupCard: some View {
        let needsOffice = monitor.office == nil
        let needsAlways = monitor.authorization != .authorizedAlways
        let needsPrecise = !needsAlways && !monitor.hasPreciseLocation
        let needsNotifications = !notifications.isAuthorized
        let openSettings = {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        }

        if needsOffice || needsAlways || needsPrecise || needsNotifications {
            VStack(alignment: .leading, spacing: 0) {
                Text("Finish setup")
                    .font(.headline)
                Text("Clockwise needs these to track your time automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                if needsOffice {
                    if OfficeSuggestion.detect(from: visits)?.isConfident == true {
                        setupRow("Review your detected office", systemImage: "sparkles", action: onSetOffice)
                    } else {
                        setupRow("Set your office location", systemImage: "mappin.and.ellipse", action: onSetOffice)
                    }
                }
                if needsAlways {
                    setupRow("Allow location \"Always\"", systemImage: "location.fill") {
                        if monitor.authorization == .notDetermined {
                            monitor.requestAuthorization()
                        } else {
                            openSettings()
                        }
                    }
                }
                if needsPrecise {
                    setupRow("Turn on Precise Location", systemImage: "scope", action: openSettings)
                }
                if needsNotifications {
                    setupRow("Turn on notifications", systemImage: "bell.badge.fill", action: openSettings)
                }
            }
            .card()
        }
    }

    private func setupRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func progressCard(now: Date) -> some View {
        let workDay = today
        let remaining = workDay.map { $0.timeOut.timeIntervalSince(now) } ?? WorkDay.shiftDuration
        let worked = workDay.map { ($0.leftAt ?? now).timeIntervalSince($0.timeIn) } ?? 0
        let progress = min(max(worked / WorkDay.shiftDuration, 0), 1)
        let tint: Color = switch (workDay, workDay?.leftAt) {
        case (nil, _): .accentColor
        case (let day?, _?): day.shortfall == nil ? .green : .red
        case (_?, nil): remaining > 0 ? .accentColor : .green
        }

        return VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 16)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: progress)
                VStack(spacing: 4) {
                    if let workDay, let leftAt = workDay.leftAt {
                        Text("Timed out")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(leftAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                    } else if workDay != nil, remaining > 0 {
                        Text(Duration.seconds(remaining).formatted(.time(pattern: .hourMinuteSecond)))
                            .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                        Text("left")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if workDay != nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Done for today")
                            .font(.headline)
                    } else {
                        Image(systemName: "figure.walk.arrival")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                        Text("Not in yet")
                            .font(.headline)
                    }
                }
            }
            .frame(width: 220, height: 220)
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            Group {
                if let workDay, workDay.leftAt != nil {
                    if let shortfall = workDay.shortfall {
                        Text("\(shortfall.hoursAndMinutes) short today")
                            .foregroundStyle(.red)
                    } else {
                        Text("Full day, no shortfall")
                            .foregroundStyle(.green)
                    }
                } else if let workDay, remaining > 0 {
                    Text("You can time out at **\(workDay.timeOut.formatted(date: .omitted, time: .shortened))**")
                        .foregroundStyle(.secondary)
                } else if workDay != nil {
                    Text(-remaining >= 60 ? "You can time out now · \((-remaining).hoursAndMinutes) extra" : "You can time out now")
                        .foregroundStyle(.green)
                } else {
                    Text("Your time in is recorded automatically when you arrive at the office.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func timesCard(_ workDay: WorkDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Times")
                    .font(.headline)
                Spacer()
                Button("Edit") { isEditingTimeIn = true }
                    .font(.subheadline.weight(.semibold))
            }
            HStack(alignment: .top, spacing: 0) {
                timeColumn("Time in", time: workDay.timeIn)
                Divider().frame(height: 44)
                timeColumn("Required", time: workDay.timeOut)
                Divider().frame(height: 44)
                timeColumn("Timed out", time: workDay.leftAt)
            }
            if workDay.isEstimated {
                Label(
                    "Estimated time in: Clockwise only noticed you when you opened the app. Tap Edit if it's wrong.",
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
        .card()
    }

    private func timeColumn(_ title: String, time: Date?) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(time?.formatted(date: .omitted, time: .shortened) ?? "--")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(time == nil ? .tertiary : .primary)
        }
        .frame(maxWidth: .infinity)
    }

    private func departureCard(_ workDay: WorkDay, departedAt: Date) -> some View {
        let departedTime = departedAt.formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "figure.walk.departure")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You left the office area at \(departedTime)")
                        .font(.subheadline.weight(.semibold))
                    if let shortfall = workDay.unconfirmedShortfall {
                        Text("That's \(shortfall.hoursAndMinutes) before your required time out. Ignore this if you only stepped out.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Gone for the day? Use this as your time out.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button { recordTimeOut(workDay, at: departedAt) } label: {
                Label("Time out at \(departedTime)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .card(tint: .orange)
    }

    @ViewBuilder
    private var shortfallCard: some View {
        let interval = period.interval(offset: 0)
        let periodDays = days.filter { interval.contains($0.day) }
        let total = periodDays.compactMap(\.shortfall).reduce(0, +)
        let unconfirmedCount = periodDays.filter { $0.unconfirmedShortfall != nil }.count
        if !periodDays.isEmpty {
            Button(action: onShowHistory) {
                HStack(spacing: 12) {
                    Image(systemName: total > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.title2)
                        .foregroundStyle(total > 0 ? .red : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(total > 0 ? "\(total.hoursAndMinutes) short \(period.currentLabel)" : "No shortfall \(period.currentLabel)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if unconfirmedCount > 0 {
                            Text("\(unconfirmedCount) early departure\(unconfirmedCount == 1 ? "" : "s") to review")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    private func actionBar(now: Date) -> some View {
        VStack(spacing: 6) {
            if let today {
                if today.leftAt != nil {
                    Button {
                        today.leftAt = nil
                        try? modelContext.save()
                        notifications.scheduleReminders(timeOut: today.timeOut)
                    } label: {
                        Label("Undo time out", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button { timeOutStep = .options } label: {
                        Label("Time out", systemImage: "door.left.hand.open").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(now < today.timeOut ? .orange : .accentColor)
                }
            } else {
                Button {
                    if monitor.isInsideOffice == false {
                        isConfirmingAwayTimeIn = true
                    } else {
                        timeInNow()
                    }
                } label: {
                    Label("I'm in now", systemImage: "figure.walk.arrival").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.bar)
    }

    // MARK: - Time out drawer

    private func timeOutOptions(_ workDay: WorkDay) -> some View {
        let now = Date.now
        let detail = { (time: Date) in
            let formatted = time.formatted(date: .omitted, time: .shortened)
            return time < workDay.timeOut
                ? "\(formatted) · \(workDay.timeOut.timeIntervalSince(time).hoursAndMinutes) short"
                : "\(formatted) · full day"
        }

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time out")
                    .font(.title2.weight(.bold))
                Text("Required time out is \(workDay.timeOut.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            timeOutOption("Now", detail: detail(now), systemImage: "clock.fill", tint: .accentColor) {
                recordTimeOut(workDay, at: now)
                timeOutStep = nil
            }

            if let departedAt = workDay.departedAt {
                timeOutOption(
                    "When I left the office",
                    detail: detail(departedAt),
                    systemImage: "figure.walk.departure",
                    tint: .orange,
                    isSuggested: true
                ) {
                    recordTimeOut(workDay, at: departedAt)
                    timeOutStep = nil
                }
                Button("Choose a different time") { timeOutStep = .picker }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            } else {
                timeOutOption(
                    "When I left the office",
                    detail: "Not detected · choose the time",
                    systemImage: "figure.walk.departure",
                    tint: .orange
                ) {
                    timeOutStep = .picker
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.systemGroupedBackground))
    }

    private func timeOutOption(
        _ title: String,
        detail: String,
        systemImage: String,
        tint: Color,
        isSuggested: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        if isSuggested {
                            Text("Detected")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.15), in: Capsule())
                                .foregroundStyle(tint)
                        }
                    }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if isSuggested {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func timeInNow() {
        if let workDay = WorkDay.recordArrival(at: .now, in: modelContext) {
            notifications.scheduleReminders(timeOut: workDay.timeOut)
        }
    }

    private func recordTimeOut(_ workDay: WorkDay, at date: Date) {
        workDay.leftAt = date
        workDay.departedAt = nil
        try? modelContext.save()
        notifications.cancelReminders()
        notifications.cancelEarlyOutWarning()
    }
}

private extension View {
    func card(tint: Color? = nil) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                tint.map { AnyShapeStyle($0.opacity(0.12)) } ?? AnyShapeStyle(Color(.secondarySystemGroupedBackground)),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
    }
}

private struct TimeInEditor: View {
    let workDay: WorkDay

    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var timeIn: Date
    @State private var leftAt: Date?

    init(workDay: WorkDay) {
        self.workDay = workDay
        _timeIn = State(initialValue: workDay.timeIn)
        _leftAt = State(initialValue: workDay.leftAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time in", selection: $timeIn, displayedComponents: .hourAndMinute)
                LabeledContent(
                    "Required time out",
                    value: timeIn.addingTimeInterval(WorkDay.shiftDuration).formatted(date: .omitted, time: .shortened)
                )
                if let currentLeftAt = leftAt {
                    DatePicker(
                        "Timed out at",
                        selection: Binding(get: { currentLeftAt }, set: { leftAt = $0 }),
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            .navigationTitle(leftAt == nil ? "Edit time in" : "Edit times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        workDay.timeIn = timeIn
                        workDay.leftAt = leftAt
                        workDay.isEstimated = false
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
