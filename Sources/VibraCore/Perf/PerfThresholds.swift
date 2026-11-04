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

    /// Reads the `perf.*` keys, clamping each to its range and replacing
    /// anything non-numeric with the default, so a bad `defaults write` cannot
    /// break the report. Integer keys are clamped, then rounded to the nearest
    /// integer.
    public static func load(from store: any SettingsStore = PreferencesStore()) -> PerfThresholds {
        func int(_ key: String, _ defaultValue: Int, _ range: ClosedRange<Int>) -> Int {
            let value = clampedSetting(
                store.value(forKey: key),
                default: Double(defaultValue),
                range: Double(range.lowerBound)...Double(range.upperBound)
            )
            return Int(value.rounded())
        }
        func double(_ key: String, _ defaultValue: Double, _ range: ClosedRange<Double>) -> Double {
            clampedSetting(store.value(forKey: key), default: defaultValue, range: range)
        }
        return PerfThresholds(
            minTurns: int("perf.minTurns", defaults.minTurns, 3...1000),
            d1MinTurnsAboveFloor: int("perf.d1MinTurnsAboveFloor", defaults.d1MinTurnsAboveFloor, 5...5000),
            d1CarryFloorTokens: int("perf.d1CarryFloorTokens", defaults.d1CarryFloorTokens, 20_000...2_000_000),
            d2MinRewriteTokens: int("perf.d2MinRewriteTokens", defaults.d2MinRewriteTokens, 5_000...2_000_000),
            d3MinBurstTurns: int("perf.d3MinBurstTurns", defaults.d3MinBurstTurns, 2...50),
            leadMinUSD: double("perf.leadMinUSD", defaults.leadMinUSD, 0...100),
            leadMinShare: double("perf.leadMinShare", defaults.leadMinShare, 0...1)
        )
    }
}
