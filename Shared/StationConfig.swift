import Foundation

/// One picked station. Name and coordinates are captured at pick time so the
/// widget never needs the (city-wide) information feed just to render.
struct StationChoice: Codable, Identifiable, Equatable {
    let id: String      // GBFS station_id
    let name: String
    // Optional so picks saved before coordinates existed still decode;
    // the app backfills them from the directory on launch.
    let lat: Double?
    let lon: Double?

    init(id: String, name: String, lat: Double? = nil, lon: Double? = nil) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
    }
}

/// Which station list the widget is currently showing.
enum WidgetList: String {
    case home, work
}

/// User's picks, shared between the app and the widget via the App Group.
/// Order inside each list is priority: the widget walks `home` front to back.
struct StationConfig: Codable, Equatable {
    var home: [StationChoice]
    var work: [StationChoice]   // unused by the widget until the location step

    static let empty = StationConfig(home: [], work: [])
    static let maxPerList = 3

    /// Pre-config fallback so a freshly added widget still shows something.
    static let fallbackStation = StationChoice(id: "345", name: "Regina / de Verdun", lat: 45.46734, lon: -73.57079)

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

    // MARK: - Last list shown (widget falls back to this when location is unavailable)

    private static let lastListKey = "lastWidgetList"

    static func loadLastList() -> WidgetList? {
        guard let raw = UserDefaults(suiteName: appGroupID)?.string(forKey: lastListKey) else { return nil }
        return WidgetList(rawValue: raw)
    }

    static func saveLastList(_ list: WidgetList) {
        UserDefaults(suiteName: appGroupID)?.set(list.rawValue, forKey: lastListKey)
    }
}
