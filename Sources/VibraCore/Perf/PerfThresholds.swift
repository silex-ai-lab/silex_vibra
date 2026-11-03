import Foundation

/// The values the perf detectors fire on. Encoded with exactly these bare
/// names, which are the oracle's keys; the `perf.` prefix belongs only to the
/// `defaults write` keys that load them.
public struct PerfThresholds: Sendable, Equatable, Codable {
    public let minTurns: Int
    public let d1MinTurnsAboveFloor: Int
    public let d1CarryFloorTokens: Int
    public let d2MinRewriteTokens: Int
    public let d3MinBurstTurns: Int
    public let leadMinUSD: Double
    public let leadMinShare: Double

    init(
        minTurns: Int,
        d1MinTurnsAboveFloor: Int,
        d1CarryFloorTokens: Int,
        d2MinRewriteTokens: Int,
        d3MinBurstTurns: Int,
        leadMinUSD: Double,
        leadMinShare: Double
    ) {
        self.minTurns = minTurns
        self.d1MinTurnsAboveFloor = d1MinTurnsAboveFloor
        self.d1CarryFloorTokens = d1CarryFloorTokens
        self.d2MinRewriteTokens = d2MinRewriteTokens
        self.d3MinBurstTurns = d3MinBurstTurns
        self.leadMinUSD = leadMinUSD
        self.leadMinShare = leadMinShare
    }

    public static let defaults = PerfThresholds(
        minTurns: 10,
        d1MinTurnsAboveFloor: 50,
        d1CarryFloorTokens: 200_000,
        d2MinRewriteTokens: 30_000,
        d3MinBurstTurns: 3,
        leadMinUSD: 0.25,
        leadMinShare: 0.10
    )
}
