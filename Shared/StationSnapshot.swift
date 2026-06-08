import Foundation

struct StationSnapshot {
    let stationName: String
    let bikes: Int
    let ebikes: Int
    let docks: Int
    let lastReported: Date
    let isPlaceholder: Bool

    static let placeholder = StationSnapshot(
        stationName: "Drummond / de Maisonneuve",
        bikes: 5, ebikes: 2, docks: 17,
        lastReported: .now, isPlaceholder: true
    )
}
