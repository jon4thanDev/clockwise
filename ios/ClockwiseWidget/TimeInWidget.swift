import SwiftUI
import WidgetKit

struct TimeInEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot?
}

struct TimeInProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimeInEntry {
        let timeIn = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        return TimeInEntry(date: .now, snapshot: TodaySnapshot(timeIn: timeIn, timeOut: timeIn.addingTimeInterval(9 * 60 * 60)))
    }

    func getSnapshot(in context: Context, completion: @escaping (TimeInEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : timeline(now: .now).entries[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimeInEntry>) -> Void) {
        completion(timeline(now: .now))
    }

    /// Yesterday's time in must not linger, so the timeline flips to "Away" at midnight.
    private func timeline(now: Date) -> Timeline<TimeInEntry> {
        let calendar = Calendar.current
        let snapshot = TodaySnapshot.stored.flatMap { calendar.isDate($0.timeIn, inSameDayAs: now) ? $0 : nil }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return Timeline(
            entries: [TimeInEntry(date: now, snapshot: snapshot), TimeInEntry(date: midnight, snapshot: nil)],
            policy: .after(midnight)
        )
    }
}

struct TimeInWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimeInEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            if let snapshot = entry.snapshot {
                Label("In \(snapshot.timeIn.formatted(date: .omitted, time: .shortened))", systemImage: "clock")
            } else {
                Label("Away from office", systemImage: "figure.walk.departure")
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                if let snapshot = entry.snapshot {
                    Text("Time in").font(.caption)
                    Text(snapshot.timeIn.formatted(date: .omitted, time: .shortened)).font(.headline)
                    Text("Out \(snapshot.timeOut.formatted(date: .omitted, time: .shortened))").font(.caption)
                } else {
                    Text("Clockwise").font(.caption)
                    Text("Away from office").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                    Text("Clockwise")
                        .font(.caption.weight(.semibold))
                }
                Spacer()
                if let snapshot = entry.snapshot {
                    Text("Time in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(snapshot.timeIn.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("Time out \(snapshot.timeOut.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "figure.walk.departure")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Away from office")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

@main
struct TimeInWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TimeInWidget", provider: TimeInProvider()) { entry in
            TimeInWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Time in")
        .description("Shows today's time in, or that you're away from the office.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}
