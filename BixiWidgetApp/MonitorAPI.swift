import Foundation

/// Client for the bixi-monitor Cloudflare Worker (sibling project). Read-only,
/// no auth. Canonical contract: bixi-monitor/docs/api.md — but note the deployed
/// worker's semantics (src/api.ts): `bikes` is already *usable* (cargo/trailer
/// excluded server-side), `mechanical = bikes − ebikes`, and `status` is derived
/// from usable bikes. This client displays what the API returns and never
/// re-derives counts.
enum MonitorAPI {
    static let base = URL(string: "https://bixi-monitor.bixi.workers.dev/api/v1")!
    /// The only station the monitor tracks (Regina / de Verdun, capacity 19).
    /// Independent of the widget's configurable station lists.
    static let stationID = "345"

    // MARK: - Models

    struct Station: Decodable {
        let id: String
        let name: String
        let capacity: Int
    }

    /// `/now` — everything after `station` is optional because a fresh deploy
    /// with no data returns `{ station, observation: null, note }` instead.
    struct Now: Decodable {
        let station: Station
        let observedAt: Date?
        let ageSeconds: Int?
        let stale: Bool?
        let status: String?
        let bikes: Int?          // usable bikes (cargo excluded server-side)
        let ebikes: Int?
        let trailer: Int?        // display-only, never counted
        let mechanical: Int?     // bikes − ebikes
        let docksAvailable: Int?
        let bikesDisabled: Int?
        let docksDisabled: Int?
        let note: String?
    }

    struct Observation: Decodable, Identifiable {
        let ts: Int              // epoch seconds (also emitted as ISO in `t`)
        let bikes: Int           // usable
        let ebikes: Int
        let trailer: Int?
        let mechanical: Int
        let docks: Int
        let status: String

        var id: Int { ts }
        var date: Date { Date(timeIntervalSince1970: TimeInterval(ts)) }
    }

    struct Observations: Decodable {
        let capacity: Int
        let count: Int
        let observations: [Observation]
    }

    struct Episode: Decodable, Identifiable {
        let start: Date
        let end: Date?           // null while ongoing
        let ongoing: Bool
        let minutes: Int

        var id: Date { start }
    }

    struct Episodes: Decodable {
        let type: String
        let days: Int
        let count: Int
        let episodes: [Episode]
    }

    struct Runout: Decodable {
        let minutes: Int?        // null = never ran out on that weekday
        let time: String?        // "HH:MM" local
        let days: Int?
    }

    struct Morning: Decodable {
        let window: [String]?
        let targetTime: String?
        let typicalFirstEmpty: String?   // null if it never went empty
        let sampleDays: Int?
        let pctEmptyAtTarget: Double?    // 0..1, null with no mornings
        let mornings: Int?
        let runoutByDow: [Runout]?       // [0=Sun..6=Sat]
        let runoutAvg: Runout?
    }

    struct Heatmap: Decodable {
        let days: [String]               // Sun..Sat as sent; UI reorders Mon-first
        let avgBikes: [[Double?]]        // null cell = no coverage, NOT zero
        let pctEmpty: [[Double?]]
    }

    struct Holiday: Decodable {
        let date: String                 // "2026-07-01" (local date)
        let name: String
    }

    struct Stats: Decodable {
        let days: Int
        let tz: String
        let capacity: Int
        let heatmap: Heatmap?
        let morning: Morning?
        let excludedHolidays: [Holiday]?
        let longestEmptyMinutes: Int?
    }

    // MARK: - Fetchers

    static func now() async throws -> Now { try await get("now") }

    static func observations() async throws -> Observations { try await get("observations") }

    static func episodes(type: String, days: Int = 30) async throws -> Episodes {
        try await get("episodes", query: ["type": type, "days": String(days)])
    }

    static func stats(days: Int = 30) async throws -> Stats {
        try await get("stats", query: ["days": String(days), "tz": "America/Toronto"])
    }

    // MARK: - Plumbing

    private static func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(
            url: base.appendingPathComponent("stations/\(stationID)/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(T.self, from: data)
    }

    /// The worker's timestamps come from JS `toISOString()`, which always has
    /// fractional seconds — Swift's plain .iso8601 strategy rejects those.
    private static let decoder: JSONDecoder = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()

        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath, debugDescription: "unparseable date: \(s)"))
        }
        return d
    }()
}
