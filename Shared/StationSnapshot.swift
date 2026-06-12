import Foundation

struct StationSnapshot {
    let stationName: String
    let bikes: Int          // total bikes available (the feed includes e-bikes in this count)
    let ebikes: Int         // of those, the electric ones
    let docks: Int
    let lastReported: Date
    let isPlaceholder: Bool

    /// Non-electric bikes. The public feed can't isolate cargo/trailer bikes,
    /// so this lumps mechanical + trailer together (= total − electric).
    var mechanicalBikes: Int { max(0, bikes - ebikes) }

    static let placeholder = StationSnapshot(
        stationName: "Regina / de Verdun",
        bikes: 5, ebikes: 2, docks: 12,
        lastReported: .now, isPlaceholder: true
    )
}
