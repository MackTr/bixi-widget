import WidgetKit
import SwiftUI
import CoreLocation

struct BixiEntry: TimelineEntry {
    let date: Date
    let snapshot: StationSnapshot
    let errorText: String?
    var list: WidgetList? = nil   // which station list is showing (🏠/💼 badge)
}

/// One cheap location fix for the timeline refresh. Battery-friendly by
/// construction: kilometer accuracy (no GPS spin-up), and a recent cached
/// fix is returned for free without touching the radios at all.
private final class OneShotLocation: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func current() async -> CLLocation? {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }

        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let cached = manager.location, cached.timestamp > .now.addingTimeInterval(-10 * 60) {
            return cached
        }
        return await withCheckedContinuation { cont in
            lock.lock()
            continuation = cont
            lock.unlock()
            manager.delegate = self
            manager.requestLocation()
            // Don't let a slow fix stall the whole widget refresh.
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    /// Resumes the continuation exactly once, whichever of the delegate
    /// callback or the timeout gets here first.
    private func finish(with location: CLLocation?) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.first)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }
}

struct BixiProvider: TimelineProvider {
    func placeholder(in context: Context) -> BixiEntry {
        BixiEntry(date: .now, snapshot: .placeholder, errorText: nil, list: .home)
    }

    func getSnapshot(in context: Context, completion: @escaping (BixiEntry) -> Void) {
        completion(BixiEntry(date: .now, snapshot: .placeholder, errorText: nil, list: .home))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BixiEntry>) -> Void) {
        Task {
            let entry = await Self.makeEntry()
            // Ask iOS to refresh ~15 min from now (its practical minimum).
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    /// Picks home vs work by location (within 1 km of any work station →
    /// work list; no fix → whatever list was shown last), then walks that
    /// list in priority order and shows the first station with a mechanical
    /// bike. If they're all empty, shows the top-priority one with its zeros.
    static func makeEntry() async -> BixiEntry {
        let config = StationConfig.load()
        let home = config?.home ?? []
        let work = config?.work ?? []

        var list: WidgetList = StationConfig.loadLastList() ?? .home
        if !work.isEmpty, let here = await OneShotLocation().current() {
            let nearWork = work.contains { choice in
                guard let lat = choice.lat, let lon = choice.lon else { return false }
                return here.distance(from: CLLocation(latitude: lat, longitude: lon)) <= 1_000
            }
            list = nearWork ? .work : .home
            StationConfig.saveLastList(list)
        }
        if list == .work && work.isEmpty { list = .home }

        var choices = list == .work ? work : home
        if choices.isEmpty { choices = [StationConfig.fallbackStation] }

        do {
            let statuses = try await BixiAPI.statuses(for: choices.map(\.id))
            let pick = choices.first { (statuses[$0.id]?.mechanical ?? 0) > 0 } ?? choices[0]
            guard let st = statuses[pick.id] else {
                return BixiEntry(date: .now, snapshot: .placeholder, errorText: "Station missing from feed")
            }
            let snap = StationSnapshot(
                stationName: pick.name,
                bikes: st.bikes, ebikes: st.ebikes, docks: st.docks,
                lastReported: st.lastReported, isPlaceholder: false
            )
            return BixiEntry(date: .now, snapshot: snap, errorText: nil, list: list)
        } catch {
            return BixiEntry(date: .now, snapshot: .placeholder, errorText: "Couldn't load", list: list)
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

    /// 🏠/💼 — which list the location logic picked (nil before any fix).
    private var listIcon: String? {
        switch entry.list {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case nil: nil
        }
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if let icon = listIcon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.snapshot.stationName)
                    .font(.caption).bold().lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                stat("🚲", entry.snapshot.mechanicalBikes, .green)
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
                Image(systemName: listIcon ?? "bicycle")
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
                card("🚲", entry.snapshot.mechanicalBikes, "Bikes", .green)
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
    BixiEntry(date: .now, snapshot: .placeholder, errorText: nil, list: .home)
}

#Preview("Medium", as: .systemMedium) {
    BixiWidget()
} timeline: {
    BixiEntry(date: .now, snapshot: .placeholder, errorText: nil, list: .work)
}
