import Foundation

// MARK: - GBFS wire models (only the fields we use)

private struct GBFSResponse<T: Decodable>: Decodable {
    let data: DataWrapper
    struct DataWrapper: Decodable { let stations: [T] }
}

private struct StatusStation: Decodable {
    let station_id: String
    let num_bikes_available: Int
    let num_ebikes_available: Int
    let num_docks_available: Int
    let last_reported: Int
}

private struct InfoStation: Decodable {
    let station_id: String
    let name: String
    let capacity: Int
}

// MARK: - Service

enum BixiAPI {
    static let statusURL = URL(string: "https://gbfs.velobixi.com/gbfs/en/station_status.json")!
    static let infoURL   = URL(string: "https://gbfs.velobixi.com/gbfs/en/station_information.json")!

    /// Fetch both feeds, join on station_id, return the snapshot for `stationId`.
    static func snapshot(for stationId: String) async throws -> StationSnapshot {
        async let statusData = URLSession.shared.data(from: statusURL).0
        async let infoData   = URLSession.shared.data(from: infoURL).0

        let status = try JSONDecoder().decode(GBFSResponse<StatusStation>.self, from: try await statusData)
        let info   = try JSONDecoder().decode(GBFSResponse<InfoStation>.self,   from: try await infoData)

        guard let s = status.data.stations.first(where: { $0.station_id == stationId }) else {
            throw BixiError.stationNotFound(stationId)
        }
        let name = info.data.stations.first(where: { $0.station_id == stationId })?.name ?? "Station \(stationId)"

        return StationSnapshot(
            stationName: name,
            bikes: s.num_bikes_available,
            ebikes: s.num_ebikes_available,
            docks: s.num_docks_available,
            lastReported: Date(timeIntervalSince1970: TimeInterval(s.last_reported)),
            isPlaceholder: false
        )
    }

    enum BixiError: Error { case stationNotFound(String) }
}
