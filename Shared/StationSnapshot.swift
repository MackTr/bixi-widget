import Foundation

struct StationSnapshot {
    let stationName: String
    let bikes: Int          // total bikes available (the feed includes e-bikes AND cargo in this count)
    let ebikes: Int         // of those, the electric ones
    let cargo: Int          // of those, the cargo/trailer ones
    let docks: Int
    let lastReported: Date
    let isPlaceholder: Bool

    /// Regular pedal bikes: total minus electric minus cargo/trailer.
    var mechanicalBikes: Int { max(0, bikes - ebikes - cargo) }

    static let placeholder = StationSnapshot(
        stationName: "Regina / de Verdun",
        bikes: 5, ebikes: 2, cargo: 0, docks: 12,
        lastReported: .now, isPlaceholder: true
    )
}
