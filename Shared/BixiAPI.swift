import Foundation

// MARK: - Public results

/// Live numbers for one station, straight from the status feed.
struct StationStatus {
    let stationID: String
    let bikes: Int          // total bikes (the feed includes e-bikes in this)
    let ebikes: Int
    let docks: Int
    let lastReported: Date

    /// Non-electric bikes. The public feed can't isolate cargo/trailer bikes,
    /// so this lumps mechanical + trailer together (= total − electric).
    var mechanical: Int { max(0, bikes - ebikes) }
}

/// Directory entry for the in-app station picker.
struct StationListItem: Identifiable, Equatable {
    let id: String          // GBFS station_id
    let name: String
}

// MARK: - Service

enum BixiAPI {
    static let statusURL = URL(string: "https://gbfs.velobixi.com/gbfs/en/station_status.json")!
    static let infoURL   = URL(string: "https://gbfs.velobixi.com/gbfs/en/station_information.json")!

    /// One pass over the city-wide status feed, returning the rows for `ids`.
    ///
    /// Widget extensions get only ~30 MB of memory, and the BIXI feed is the
    /// *whole city* (~1,000 stations) — there is no per-station endpoint. So we
    /// stream-decode: keep the rows we were asked for, discard everything else
    /// as we walk the array, and stop as soon as all targets are found.
    static func statuses(for ids: [String]) async throws -> [String: StationStatus] {
        let decoder = JSONDecoder()
        decoder.userInfo[.targetStationIDs] = Set(ids)
        let rows = try decoder.decode(StationFeed<StatusRow>.self, from: await fetch(statusURL)).matches
        let statuses = rows.map { row in
            StationStatus(
                stationID: row.station_id,
                bikes: row.num_bikes_available,
                ebikes: row.num_ebikes_available,
                docks: row.num_docks_available,
                lastReported: Date(timeIntervalSince1970: TimeInterval(row.last_reported))
            )
        }
        return Dictionary(statuses.map { ($0.stationID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Single-station convenience used by the widget's pre-config fallback.
    static func snapshot(for stationId: String) async throws -> StationSnapshot {
        guard let st = try await statuses(for: [stationId])[stationId] else {
            throw BixiError.stationNotFound(stationId)
        }
        return StationSnapshot(
            stationName: "Station \(stationId)",
            bikes: st.bikes, ebikes: st.ebikes, docks: st.docks,
            lastReported: st.lastReported, isPlaceholder: false
        )
    }

    /// Full station directory for the in-app picker (app side, not the widget).
    static func allStations() async throws -> [StationListItem] {
        let decoder = JSONDecoder()   // no target set = keep every row
        let rows = try decoder.decode(StationFeed<InfoRow>.self, from: await fetch(infoURL)).matches
        return rows
            .filter { !$0.station_id.isEmpty && !$0.name.isEmpty }
            .map { StationListItem(id: $0.station_id, name: $0.name) }
    }

    private static func fetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        return try await URLSession.shared.data(for: req).0
    }

    enum BixiError: Error { case stationNotFound(String) }
}

// MARK: - Streaming decode

private extension CodingUserInfoKey {
    static let targetStationIDs = CodingUserInfoKey(rawValue: "targetStationIDs")!
}

private protocol StationRow: Decodable { var station_id: String { get } }

/// Walks `data.stations` one element at a time. With a target set in
/// `userInfo`, keeps only matching rows and stops once all are found;
/// without one, keeps everything (used for the picker directory).
private struct StationFeed<Row: StationRow>: Decodable {
    let matches: [Row]

    private enum Top: String, CodingKey { case data }
    private enum Mid: String, CodingKey { case stations }

    init(from decoder: Decoder) throws {
        let targets = decoder.userInfo[.targetStationIDs] as? Set<String>
        let top = try decoder.container(keyedBy: Top.self)
        let mid = try top.nestedContainer(keyedBy: Mid.self, forKey: .data)
        var stations = try mid.nestedUnkeyedContainer(forKey: .stations)

        var found: [Row] = []
        while !stations.isAtEnd {
            // Each Row decodes leniently (never throws), so the container always
            // advances — no risk of an infinite loop on a malformed station.
            let row = try stations.decode(Row.self)
            if let targets {
                if targets.contains(row.station_id) {
                    found.append(row)
                    if found.count == targets.count { break }
                }
            } else {
                found.append(row)
            }
        }
        matches = found
    }
}

// MARK: - Lenient wire models (only the fields we use)

/// Field-by-field optional decoding: a single bad/missing field in one station
/// can't blow up the decode of the whole feed and hide the stations we want.
private struct StatusRow: StationRow {
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

private struct InfoRow: StationRow {
    let station_id: String
    let name: String

    private enum K: String, CodingKey { case station_id, name }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        station_id = (try? c.decode(String.self, forKey: .station_id)) ?? ""
        name       = (try? c.decode(String.self, forKey: .name)) ?? ""
    }
}
