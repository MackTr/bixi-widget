import Foundation

/// One picked station. The name is captured at pick time so the widget
/// never needs the (city-wide) information feed just to show a title.
struct StationChoice: Codable, Identifiable, Equatable {
    let id: String      // GBFS station_id
    let name: String
}

/// User's picks, shared between the app and the widget via the App Group.
/// Order inside each list is priority: the widget walks `home` front to back.
struct StationConfig: Codable, Equatable {
    var home: [StationChoice]
    var work: [StationChoice]   // unused by the widget until the location step

    static let empty = StationConfig(home: [], work: [])
    static let maxPerList = 3

    /// Pre-config fallback so a freshly added widget still shows something.
    static let fallbackStation = StationChoice(id: "345", name: "Regina / de Verdun")

    // MARK: - Persistence (App Group)

    static let appGroupID = "group.com.macktr.BixiWidgetApp"
    private static let key = "stationConfig"

    static func load() -> StationConfig? {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StationConfig.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroupID)?.set(data, forKey: Self.key)
    }
}
