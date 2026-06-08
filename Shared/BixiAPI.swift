import Foundation

// MARK: - Service

enum BixiAPI {
    static let statusURL = URL(string: "https://gbfs.velobixi.com/gbfs/en/station_status.json")!
    static let infoURL   = URL(string: "https://gbfs.velobixi.com/gbfs/en/station_information.json")!

    /// Fetch the two GBFS feeds and return a snapshot for `stationId`.
    ///
    /// Widget extensions get only ~30 MB of memory, and the BIXI feed is the
    /// *whole city* (~900 stations) — there is no single-station endpoint. So we:
    ///   • fetch the feeds **sequentially**, releasing each payload before the
    ///     next, instead of holding two whole-city blobs at once, and
    ///   • **stream-decode**, keeping only the matching station and discarding
    ///     every other row as we walk the array (never building a full array).
    static func snapshot(for stationId: String) async throws -> StationSnapshot {
        let status: StatusStation = try await fetchStation(from: statusURL, id: stationId)
        // Name is non-critical — if the info feed hiccups, fall back gracefully.
        let info: InfoStation? = try? await fetchStation(from: infoURL, id: stationId)

        return StationSnapshot(
            stationName: info?.name ?? "Station \(stationId)",
            bikes: status.num_bikes_available,
            ebikes: status.num_ebikes_available,
            docks: status.num_docks_available,
            lastReported: Date(timeIntervalSince1970: TimeInterval(status.last_reported)),
            isPlaceholder: false
        )
    }

    private static func fetchStation<Row: StationRow>(from url: URL, id: String) async throws -> Row {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: req)

        let decoder = JSONDecoder()
        decoder.userInfo[.targetStationID] = id
        guard let row = try decoder.decode(StationFeed<Row>.self, from: data).match else {
            throw BixiError.stationNotFound(id)
        }
        return row
    }

    enum BixiError: Error { case stationNotFound(String) }
}

// MARK: - Streaming decode (keep only the target station)

private extension CodingUserInfoKey {
    static let targetStationID = CodingUserInfoKey(rawValue: "targetStationID")!
}

private protocol StationRow: Decodable { var station_id: String { get } }

/// Walks `data.stations` one element at a time and keeps only the row whose
/// `station_id` matches the target; stops as soon as it's found. Never holds
/// the whole array in memory.
private struct StationFeed<Row: StationRow>: Decodable {
    let match: Row?

    private enum Top: String, CodingKey { case data }
    private enum Mid: String, CodingKey { case stations }

    init(from decoder: Decoder) throws {
        let target = decoder.userInfo[.targetStationID] as? String
        let top = try decoder.container(keyedBy: Top.self)
        let mid = try top.nestedContainer(keyedBy: Mid.self, forKey: .data)
        var stations = try mid.nestedUnkeyedContainer(forKey: .stations)

        var found: Row?
        while !stations.isAtEnd {
            // Each Row decodes leniently (never throws), so the container always
            // advances — no risk of an infinite loop on a malformed station.
            let row = try stations.decode(Row.self)
            if row.station_id == target {
                found = row
                break
            }
        }
        match = found
    }
}

// MARK: - Lenient wire models (only the fields we use)

/// Field-by-field optional decoding: a single bad/missing field in one station
/// can't blow up the decode of the whole feed and hide your station.
private struct StatusStation: StationRow {
    let station_id: String
    let num_bikes_available: Int
    let num_ebikes_available: Int
    let num_docks_available: Int
    let last_reported: Int

    private enum K: String, CodingKey {
        case station_id, num_bikes_available, num_ebikes_available, num_docks_available, last_reported
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        station_id           = (try? c.decode(String.self, forKey: .station_id)) ?? ""
        num_bikes_available  = (try? c.decode(Int.self, forKey: .num_bikes_available)) ?? 0
        num_ebikes_available = (try? c.decode(Int.self, forKey: .num_ebikes_available)) ?? 0
        num_docks_available  = (try? c.decode(Int.self, forKey: .num_docks_available)) ?? 0
        last_reported        = (try? c.decode(Int.self, forKey: .last_reported)) ?? 0
    }
}

private struct InfoStation: StationRow {
    let station_id: String
    let name: String

    private enum K: String, CodingKey { case station_id, name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        station_id = (try? c.decode(String.self, forKey: .station_id)) ?? ""
        name       = (try? c.decode(String.self, forKey: .name)) ?? ""
    }
}
