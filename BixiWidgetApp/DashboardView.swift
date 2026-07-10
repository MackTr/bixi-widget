import SwiftUI
import Charts

// MARK: - Local-time helpers (station lives in Montréal; display everything there)

private let monitorTZ = TimeZone(identifier: "America/Toronto")!

private func makeFormatter(_ template: String) -> DateFormatter {
    let f = DateFormatter()
    f.timeZone = monitorTZ
    f.locale = Locale(identifier: "en_CA")
    f.dateFormat = template
    return f
}
private let timeFmt = makeFormatter("HH:mm")
private let dayFmt = makeFormatter("MMM d")
private let localDateFmt = makeFormatter("yyyy-MM-dd")

private func fmtMinutes(_ m: Int) -> String {
    m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
}

// MARK: - Dashboard

struct DashboardView: View {
    @State private var now: MonitorAPI.Now?
    @State private var obs: MonitorAPI.Observations?
    @State private var emptyEps: MonitorAPI.Episodes?
    @State private var fullEps: MonitorAPI.Episodes?
    @State private var stats: MonitorAPI.Stats?
    @State private var failed = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if failed && now == nil {
                        ContentUnavailableView(
                            "Couldn't reach the monitor",
                            systemImage: "wifi.slash",
                            description: Text("Pull down to retry.")
                        )
                    }
                    if let now { HeroSection(now: now) }
                    RunoutChartSection(obs: obs)
                    PatternsSection(stats: stats)
                    MorningSection(stats: stats)
                    EpisodesSection(emptyEps: emptyEps, fullEps: fullEps,
                                    holidays: stats?.excludedHolidays ?? [])
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(now?.station.name ?? "BIXI Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        async let n = MonitorAPI.now()
        async let o = MonitorAPI.observations()
        async let e = MonitorAPI.episodes(type: "empty")
        async let f = MonitorAPI.episodes(type: "full")
        async let s = MonitorAPI.stats()
        now = try? await n
        obs = try? await o
        emptyEps = try? await e
        fullEps = try? await f
        stats = try? await s
        failed = (now == nil)
    }
}

// MARK: - Shared card container

private struct Card<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Hero (now + occupancy bar)

private struct HeroSection: View {
    let now: MonitorAPI.Now

    private var statusColor: Color {
        switch now.status {
        case "empty": .red
        case "low": .orange
        case "full": .blue
        default: .green
        }
    }
    private var statusLabel: String {
        switch now.status {
        case "empty": "Empty"
        case "low": "Low"
        case "full": "Full"
        case "ok": "OK"
        default: now.status ?? "—"
        }
    }
    private var updatedText: String {
        guard let age = now.ageSeconds else { return "" }
        return age < 90 ? "updated just now" : "updated \(age / 60) min ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if now.observedAt == nil {
                Text(now.note ?? "No data yet — the collector just started.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(now.bikes ?? 0)")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText())
                        Text("bikes of \(now.station.capacity)")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(statusLabel)
                            .font(.caption).bold()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(statusColor, in: Capsule())
                        if now.stale == true {
                            Text("stale").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                occupancyBar
                legend
            }
        }
        .padding()
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Spans all capacity slots: usable bikes + broken bikes + unavailable
    /// docks are explicit segments; the remaining track is free docks.
    private var occupancyBar: some View {
        GeometryReader { geo in
            let cap = max(1, now.station.capacity)
            let w: (Int?) -> CGFloat = {
                CGFloat(max(0, $0 ?? 0)) / CGFloat(cap) * geo.size.width
            }
            HStack(spacing: 0) {
                Rectangle().fill(.green).frame(width: w(now.mechanical))
                Rectangle().fill(.blue).frame(width: w(now.ebikes))
                Rectangle().fill(.purple.opacity(0.65)).frame(width: w(now.trailer))
                Rectangle().fill(Color.primary.opacity(0.35)).frame(width: w(now.bikesDisabled))
                Spacer(minLength: 0)   // free docks = the track
                Rectangle().fill(Color.primary.opacity(0.16)).frame(width: w(now.docksDisabled))
            }
        }
        .frame(height: 16)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                dot(.green, "\(now.mechanical ?? 0) mechanical")
                dot(.blue, "\(now.ebikes ?? 0) ebikes")
                if let t = now.trailer, t > 0 { dot(.purple.opacity(0.65), "\(t) trailer") }
                if let b = now.bikesDisabled, b > 0 { dot(Color.primary.opacity(0.35), "\(b) broken") }
            }
            HStack(spacing: 10) {
                dot(Color.primary.opacity(0.10), "\(now.docksAvailable ?? 0) free docks")
                if let u = now.docksDisabled, u > 0 { dot(Color.primary.opacity(0.16), "\(u) unavailable") }
                Spacer()
                Text(updatedText).foregroundStyle(.tertiary)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func dot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}

// MARK: - "When bikes run out" (24 h step chart)

private struct RunoutChartSection: View {
    let obs: MonitorAPI.Observations?

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let bikes: Int
    }
    private struct Run: Identifiable {
        let id: Int
        let start: Date
        let end: Date
        let empty: Bool   // false = full (no docks)
    }

    var body: some View {
        Card(title: "When bikes run out", subtitle: subtitle) {
            if let obs, obs.observations.count > 1 {
                chart(obs)
            } else {
                Text("Not enough data yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        guard let obs, obs.observations.count > 1 else { return "last 24 h" }
        return zoomDomain(obs) == nil ? "last 24 h" : "zoomed to when bikes ran out"
    }

    private func points(_ obs: MonitorAPI.Observations) -> [Point] {
        var pts = obs.observations.map { Point(id: $0.ts, date: $0.date, bikes: $0.bikes) }
        // Hold the last value to the present — step data, never interpolate.
        if let last = obs.observations.last {
            pts.append(Point(id: last.ts + 1, date: .now, bikes: last.bikes))
        }
        return pts
    }

    /// Contiguous intervals where the station was empty (bikes 0) or full
    /// (docks 0), step-holding each observation until the next one.
    private func runs(_ obs: MonitorAPI.Observations) -> [Run] {
        let rows = obs.observations
        var out: [Run] = []
        for (i, r) in rows.enumerated() {
            let end = i + 1 < rows.count ? rows[i + 1].date : Date()
            if r.bikes == 0 { out.append(Run(id: r.ts, start: r.date, end: end, empty: true)) }
            else if r.docks == 0 { out.append(Run(id: -r.ts, start: r.date, end: end, empty: false)) }
        }
        return out
    }

    /// Padded window around the empty runs; nil = no run-out, show full 24 h.
    private func zoomDomain(_ obs: MonitorAPI.Observations) -> ClosedRange<Date>? {
        let empties = runs(obs).filter(\.empty)
        guard let first = empties.map(\.start).min(),
              let last = empties.map(\.end).max(),
              let windowStart = obs.observations.first?.date else { return nil }
        let pad: TimeInterval = 90 * 60
        let lo = max(windowStart, first.addingTimeInterval(-pad))
        let hi = min(Date(), last.addingTimeInterval(pad))
        return lo < hi ? lo...hi : nil
    }

    private func chart(_ obs: MonitorAPI.Observations) -> some View {
        Chart {
            ForEach(runs(obs)) { r in
                RectangleMark(xStart: .value("From", r.start), xEnd: .value("To", r.end))
                    .foregroundStyle(r.empty ? Color.red.opacity(0.10) : Color.blue.opacity(0.10))
            }
            ForEach(points(obs)) { p in
                LineMark(x: .value("Time", p.date), y: .value("Bikes", p.bikes))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXScale(domain: zoomDomain(obs) ?? fullDomain(obs))
        .chartYScale(domain: 0...max(1, obs.capacity))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(timeFmt.string(from: d))   // Montréal time, not device tz
                    }
                }
            }
        }
        .frame(height: 160)
    }

    private func fullDomain(_ obs: MonitorAPI.Observations) -> ClosedRange<Date> {
        (obs.observations.first?.date ?? .now)...Date()
    }
}

// MARK: - Patterns heatmap

private struct PatternsSection: View {
    let stats: MonitorAPI.Stats?
    @State private var metric: Metric = .pctEmpty

    enum Metric: String, CaseIterable {
        case pctEmpty = "% empty", avgBikes = "avg bikes"
    }

    /// API rows are Sun..Sat; render Mon-first like the web dashboard.
    private let dowOrder = [1, 2, 3, 4, 5, 6, 0]

    var body: some View {
        Card(title: "Patterns", subtitle: stats.map { "last \($0.days) days" }) {
            if let hm = stats?.heatmap {
                Picker("Metric", selection: $metric) {
                    ForEach(Metric.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                grid(hm)
                hourAxis
                footers
            } else {
                Text("Collecting… the heatmap gets meaningful after ~1–2 weeks of data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func value(_ grid: [[Double?]], _ dow: Int, _ hour: Int) -> Double? {
        guard grid.indices.contains(dow), grid[dow].indices.contains(hour) else { return nil }
        return grid[dow][hour]
    }

    private func grid(_ hm: MonitorAPI.Heatmap) -> some View {
        let g = metric == .pctEmpty ? hm.pctEmpty : hm.avgBikes
        let cap = Double(stats?.capacity ?? 19)
        let runout = stats?.morning?.runoutByDow
        return VStack(spacing: 2) {
            ForEach(dowOrder, id: \.self) { dow in
                HStack(spacing: 2) {
                    Text(hm.days.indices.contains(dow) ? hm.days[dow] : "")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                    ForEach(0..<24, id: \.self) { h in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(cellColor(value(g, dow, h), cap: cap))
                            .frame(height: 14)
                            .frame(maxWidth: .infinity)
                    }
                    Text(runoutTime(runout, dow))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private func runoutTime(_ runout: [MonitorAPI.Runout]?, _ dow: Int) -> String {
        guard let runout, runout.indices.contains(dow) else { return "" }
        return runout[dow].time ?? ""
    }

    /// null = no coverage — neutral, never rendered as zero.
    private func cellColor(_ v: Double?, cap: Double) -> Color {
        guard let v else { return Color.primary.opacity(0.05) }
        switch metric {
        case .pctEmpty: return Color.red.opacity(0.07 + 0.85 * min(1, v))
        case .avgBikes: return Color.green.opacity(0.07 + 0.85 * min(1, v / cap))
        }
    }

    private var hourAxis: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: 30, height: 1)
            HStack(spacing: 0) {
                Text("0h"); Spacer(); Text("6h"); Spacer(); Text("12h"); Spacer(); Text("18h"); Spacer()
            }
            .font(.caption2).foregroundStyle(.tertiary)
            Color.clear.frame(width: 38, height: 1)
        }
    }

    @ViewBuilder
    private var footers: some View {
        if let avg = stats?.morning?.runoutAvg?.time {
            Text("usually runs out around \(avg)")
                .font(.caption2).foregroundStyle(.secondary)
        }
        if let holidays = stats?.excludedHolidays, !holidays.isEmpty {
            Text("weekday stats exclude \(holidays.map(\.name).joined(separator: ", "))")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Weekday-morning tiles

private struct MorningSection: View {
    let stats: MonitorAPI.Stats?

    var body: some View {
        Card(title: "Weekday mornings", subtitle: subtitle) {
            if let m = stats?.morning {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    tile("First empty",
                         m.typicalFirstEmpty ?? "—",
                         "typical, \(m.window.map { $0.joined(separator: "–") } ?? "06:00–11:00")")
                    tile("Empty by \(m.targetTime ?? "08:30")",
                         pctText(m.pctEmptyAtTarget),
                         "\(m.mornings ?? 0) mornings")
                    tile("Longest empty",
                         stats?.longestEmptyMinutes.map(fmtMinutes) ?? "—",
                         "single stretch")
                    tile("Ran dry",
                         "\(m.runoutAvg?.days ?? 0)×",
                         m.runoutAvg?.time.map { "avg \($0)" } ?? "—")
                }
            } else {
                Text("Collecting… morning stats need a few weekdays of data.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String? {
        guard let d = stats?.morning?.sampleDays, d > 0 else { return nil }
        return "over \(d) day\(d == 1 ? "" : "s") of data"
    }

    private func pctText(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int((v * 100).rounded()))%"
    }

    private func tile(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Recent episodes

private struct EpisodesSection: View {
    let emptyEps: MonitorAPI.Episodes?
    let fullEps: MonitorAPI.Episodes?
    let holidays: [MonitorAPI.Holiday]
    @State private var kind: Kind = .empty

    enum Kind: String, CaseIterable { case empty = "Empty", full = "Full" }

    private var episodes: [MonitorAPI.Episode] {
        (kind == .empty ? emptyEps : fullEps)?.episodes ?? []
    }
    private var holidayDates: Set<String> { Set(holidays.map(\.date)) }

    var body: some View {
        Card(title: "Recent episodes", subtitle: "last 30 days") {
            Picker("Type", selection: $kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)

            if episodes.isEmpty {
                Text(kind == .empty ? "Never ran out — nice." : "Never filled up.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(episodes.prefix(8).enumerated()), id: \.element.id) { i, e in
                        if i > 0 { Divider() }
                        row(e)
                    }
                }
            }
        }
    }

    private func row(_ e: MonitorAPI.Episode) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(timeFmt.string(from: e.start)) → \(e.end.map { timeFmt.string(from: $0) } ?? "now")")
                    .font(.subheadline)
                HStack(spacing: 4) {
                    Text(dayFmt.string(from: e.start))
                    if holidayDates.contains(localDateFmt.string(from: e.start)) {
                        Text("· holiday")
                    }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if e.ongoing {
                Text("ongoing")
                    .font(.caption2).bold().foregroundStyle(.orange)
            }
            Text(fmtMinutes(e.minutes)).font(.subheadline.bold())
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    DashboardView()
}
