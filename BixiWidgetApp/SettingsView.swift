import SwiftUI
import WidgetKit
import MapKit

enum StationListKind: String, Identifiable, CaseIterable {
    case home = "Home"
    case work = "Work"
    var id: String { rawValue }
    var icon: String { self == .home ? "house.fill" : "briefcase.fill" }
}

private extension StationConfig {
    subscript(kind: StationListKind) -> [StationChoice] {
        get { kind == .home ? home : work }
        set { if kind == .home { home = newValue } else { work = newValue } }
    }
}

struct SettingsView: View {
    @State private var config = StationConfig.load() ?? .empty
    @State private var allStations: [StationListItem] = []
    @State private var directoryFailed = false
    @State private var pickingFor: StationListKind?

    var body: some View {
        NavigationStack {
            List {
                ForEach(StationListKind.allCases) { kind in
                    section(for: kind)
                }
                Section {
                    Text("The widget shows the first Home station that still has a regular bike. Drag to reorder priority.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("BIXI Stations")
            .toolbar { EditButton() }
            .sheet(item: $pickingFor) { kind in
                StationPicker(
                    title: "Add \(kind.rawValue) station",
                    stations: allStations.filter { item in
                        !config[kind].contains { $0.id == item.id }
                    }
                ) { picked in
                    config[kind].append(StationChoice(id: picked.id, name: picked.name, lat: picked.lat, lon: picked.lon))
                    persist()
                }
            }
            .task {
                // Opening the app always nudges the widget to refresh, so a
                // new build or config never leaves it showing a stale layout.
                WidgetCenter.shared.reloadAllTimelines()
                await loadDirectory()
            }
        }
    }

    private func section(for kind: StationListKind) -> some View {
        Section {
            ForEach(config[kind]) { choice in
                Label(choice.name, systemImage: "bicycle")
            }
            .onDelete { offsets in
                config[kind].remove(atOffsets: offsets)
                persist()
            }
            .onMove { from, to in
                config[kind].move(fromOffsets: from, toOffset: to)
                persist()
            }

            if config[kind].count < StationConfig.maxPerList {
                if directoryFailed {
                    Button {
                        Task { await loadDirectory() }
                    } label: {
                        Label("Couldn't load stations — retry", systemImage: "arrow.clockwise")
                    }
                } else {
                    Button {
                        pickingFor = kind
                    } label: {
                        Label("Add station", systemImage: "plus")
                    }
                    .disabled(allStations.isEmpty)
                }
            }
        } header: {
            Label(kind.rawValue, systemImage: kind.icon)
        }
    }

    private func persist() {
        config.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadDirectory() async {
        do {
            allStations = try await BixiAPI.allStations()
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            directoryFailed = false
            backfillCoordinates()
        } catch {
            directoryFailed = true
        }
    }

    /// Picks saved before coordinates existed get them filled in from the
    /// directory, so the widget's home/work switching can measure distance.
    private func backfillCoordinates() {
        var changed = false
        for kind in StationListKind.allCases {
            config[kind] = config[kind].map { choice in
                guard choice.lat == nil,
                      let match = allStations.first(where: { $0.id == choice.id }) else { return choice }
                changed = true
                return StationChoice(id: choice.id, name: choice.name, lat: match.lat, lon: match.lon)
            }
        }
        if changed { persist() }
    }
}

private struct StationPicker: View {
    let title: String
    let stations: [StationListItem]
    let onPick: (StationListItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var mode: Mode = .map

    private enum Mode: String, CaseIterable {
        case map = "Map", list = "List"
    }

    private var filtered: [StationListItem] {
        search.isEmpty
            ? stations
            : stations.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch mode {
                case .list:
                    List(filtered) { station in
                        Button {
                            onPick(station)
                            dismiss()
                        } label: {
                            Label(station.name, systemImage: "bicycle")
                        }
                        .foregroundStyle(.primary)
                    }
                case .map:
                    StationMap(stations: filtered, searchText: search) { station in
                        onPick(station)
                        dismiss()
                    }
                }
            }
            .searchable(text: $search, prompt: "Search stations")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Map picker

private extension StationListItem {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

private struct StationMap: View {
    let stations: [StationListItem]
    let searchText: String
    let onPick: (StationListItem) -> Void

    /// Markers drawn at once. Beyond this we keep the ones nearest the
    /// camera center — zooming in always reveals everything in view.
    private static let markerCap = 120

    private static let montreal = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.52, longitude: -73.59),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )

    /// Follows the user once location permission is granted; Montréal overview otherwise.
    @State private var camera: MapCameraPosition = .userLocation(fallback: .region(Self.montreal))
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedID: String?
    @State private var liveStatus: StationStatus?
    @State private var locationManager = CLLocationManager()

    private var shownStations: [StationListItem] {
        let region = visibleRegion ?? Self.montreal
        let inView = stations.filter { region.contains($0.coordinate) }
        guard inView.count > Self.markerCap else { return inView }
        let c = region.center
        return Array(
            inView
                .sorted {
                    let a = ($0.lat - c.latitude) * ($0.lat - c.latitude) + ($0.lon - c.longitude) * ($0.lon - c.longitude)
                    let b = ($1.lat - c.latitude) * ($1.lat - c.latitude) + ($1.lon - c.longitude) * ($1.lon - c.longitude)
                    return a < b
                }
                .prefix(Self.markerCap)
        )
    }

    private var selectedStation: StationListItem? {
        stations.first { $0.id == selectedID }
    }

    var body: some View {
        Map(position: $camera, selection: $selectedID) {
            UserAnnotation()
            ForEach(shownStations) { station in
                Marker(station.name, systemImage: "bicycle", coordinate: station.coordinate)
                    .tint(.green)
                    .tag(station.id)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange { context in
            visibleRegion = context.region
        }
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }
        .onChange(of: searchText) {
            // Typing pans the map to the first match.
            if let first = stations.first(where: { $0.name.localizedCaseInsensitiveContains(searchText) }), !searchText.isEmpty {
                camera = .region(MKCoordinateRegion(
                    center: first.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                ))
            }
        }
        .task(id: selectedID) {
            liveStatus = nil
            guard let id = selectedID else { return }
            liveStatus = try? await BixiAPI.statuses(for: [id])[id]
        }
        .safeAreaInset(edge: .bottom) {
            if let station = selectedStation {
                stationCard(station)
            }
        }
    }

    private func stationCard(_ station: StationListItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let st = liveStatus {
                    Text("🚲 \(st.mechanical)   ⚡️ \(st.ebikes)   🅿️ \(st.docks)")
                        .font(.subheadline)
                } else {
                    Text("Checking availability…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Add") { onPick(station) }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }
}

private extension MKCoordinateRegion {
    func contains(_ coord: CLLocationCoordinate2D) -> Bool {
        abs(coord.latitude - center.latitude) <= span.latitudeDelta / 2 &&
        abs(coord.longitude - center.longitude) <= span.longitudeDelta / 2
    }
}

#Preview {
    SettingsView()
}
