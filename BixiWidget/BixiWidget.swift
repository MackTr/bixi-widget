import WidgetKit
import SwiftUI

// 👉 CHANGE THIS to your station. Find the id in station_information.json
//    (search the JSON for your station's "name", grab its "station_id").
private let MY_STATION_ID = "345"   // "345" = Regina / de Verdun

struct BixiEntry: TimelineEntry {
    let date: Date
    let snapshot: StationSnapshot
    let errorText: String?
}

struct BixiProvider: TimelineProvider {
    func placeholder(in context: Context) -> BixiEntry {
        BixiEntry(date: .now, snapshot: .placeholder, errorText: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (BixiEntry) -> Void) {
        completion(BixiEntry(date: .now, snapshot: .placeholder, errorText: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BixiEntry>) -> Void) {
        Task {
            let entry: BixiEntry
            do {
                let snap = try await BixiAPI.snapshot(for: MY_STATION_ID)
                entry = BixiEntry(date: .now, snapshot: snap, errorText: nil)
            } catch {
                entry = BixiEntry(date: .now, snapshot: .placeholder, errorText: "Couldn't load")
            }
            // Ask iOS to refresh ~15 min from now (its practical minimum).
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct BixiWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BixiEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                smallLayout
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Small (three compact stats)

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.snapshot.stationName)
                .font(.caption).bold().lineLimit(2)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                stat("🚲", entry.snapshot.bikes, .green)
                stat("⚡️", entry.snapshot.ebikes, .blue)
                stat("🅿️", entry.snapshot.docks, .secondary)
            }

            Spacer(minLength: 0)

            footer
        }
        .padding()
    }

    // MARK: - Medium (three labeled cards)

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bicycle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(entry.snapshot.stationName)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if entry.errorText != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 10) {
                card("🚲", entry.snapshot.bikes, "Bikes", .green)
                card("⚡️", entry.snapshot.ebikes, "Electric", .blue)
                card("🅿️", entry.snapshot.docks, "Parking", .secondary)
            }

            footer
        }
        .padding()
    }

    // MARK: - Pieces

    /// Small-size stat: emoji over a shrink-to-fit number, evenly spaced.
    private func stat(_ icon: String, _ n: Int, _ tint: some ShapeStyle) -> some View {
        VStack(spacing: 1) {
            Text(icon).font(.subheadline)
            Text("\(n)")
                .font(.system(.title3, design: .rounded)).bold()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }

    /// Medium-size card: emoji, big shrink-to-fit number, and a label.
    private func card(_ icon: String, _ n: Int, _ label: String, _ tint: some ShapeStyle) -> some View {
        VStack(spacing: 2) {
            Text(icon).font(.title3)
            Text("\(n)")
                .font(.system(.title, design: .rounded)).bold()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Shared footer

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
            if let err = entry.errorText {
                Text(err)
            } else {
                Text("Updated \(entry.snapshot.lastReported, style: .time)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

@main
struct BixiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BixiWidget", provider: BixiProvider()) { entry in
            BixiWidgetView(entry: entry)
        }
        .configurationDisplayName("BIXI Station")
        .description("Live bikes, e-bikes, and parking at your station.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    BixiWidget()
} timeline: {
    BixiEntry(date: .now, snapshot: .placeholder, errorText: nil)
}

#Preview("Medium", as: .systemMedium) {
    BixiWidget()
} timeline: {
    BixiEntry(date: .now, snapshot: .placeholder, errorText: nil)
}
