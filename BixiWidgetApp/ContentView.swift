import SwiftUI
import WidgetKit

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

struct ContentView: View {
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
                    config[kind].append(StationChoice(id: picked.id, name: picked.name))
                    persist()
                }
            }
            .task { await loadDirectory() }
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
        } catch {
            directoryFailed = true
        }
    }
}

private struct StationPicker: View {
    let title: String
    let stations: [StationListItem]
    let onPick: (StationListItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [StationListItem] {
        search.isEmpty
            ? stations
            : stations.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { station in
                Button {
                    onPick(station)
                    dismiss()
                } label: {
                    Label(station.name, systemImage: "bicycle")
                }
                .foregroundStyle(.primary)
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

#Preview {
    ContentView()
}
