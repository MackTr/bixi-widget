import Foundation

struct StationSnapshot {
    let stationName: String
    let bikes: Int
    let ebikes: Int
    let docks: Int
    let lastReported: Date
    let isPlaceholder: Bool

    static let placeholder = StationSnapshot(
        stationName: "Regina / de Verdun",
        bikes: 5, ebikes: 2, docks: 12,
        lastReported: .now, isPlaceholder: true
    )
}
