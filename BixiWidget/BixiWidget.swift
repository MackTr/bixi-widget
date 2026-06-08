import WidgetKit
import SwiftUI

// 👉 CHANGE THIS to your station. Find the id in station_information.json
//    (search the JSON for your station's "name", grab its "station_id").
private let MY_STATION_ID = "1"   // "1" = Drummond / de Maisonneuve

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
    var entry: BixiEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot.stationName)
                .font(.caption).bold().lineLimit(2)
            HStack(spacing: 14) {
                stat("🚲", entry.snapshot.bikes)
                stat("⚡️", entry.snapshot.ebikes)
                stat("🅿️", entry.snapshot.docks)
            }
            if let err = entry.errorText {
                Text(err).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text(entry.snapshot.lastReported, style: .time)
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func stat(_ icon: String, _ n: Int) -> some View {
        VStack { Text(icon); Text("\(n)").font(.title3).bold() }
    }
}

@main
struct BixiWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BixiWidget", provider: BixiProvider()) { entry in
            BixiWidgetView(entry: entry)
        }
        .configurationDisplayName("BIXI Station")
        .description("Live bikes and docks at your station.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
