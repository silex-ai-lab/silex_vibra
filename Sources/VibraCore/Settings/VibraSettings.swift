import Foundation

/// Where settings are kept. A protocol so tests use a dictionary instead of
/// the developer's real preferences.
public protocol SettingsStore: Sendable {
    func value(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

/// The app's preferences domain, read through CFPreferences by application id.
///
/// Deliberately not `UserDefaults.standard`: for a bare binary (`make query`,
/// `swift run`) its domain is the process name, so the CLI and the installed
/// app would read different numbers and `--query` would misreport the app.
public struct PreferencesStore: SettingsStore {
    /// `VIBRA_PREFS_DOMAIN` overrides it, like `VIBRA_HOME` overrides the data
    /// root, so a diagnostic run can use preferences of its own.
    public static let domain: String = {
        if let override = ProcessInfo.processInfo.environment["VIBRA_PREFS_DOMAIN"], !override.isEmpty {
            return override
        }
        return "ai.silexlab.vibra"
    }()
    public let domain: String

    public init(domain: String = PreferencesStore.domain) {
        self.domain = domain
    }

    public func value(forKey key: String) -> Any? {
        // Picks up a `defaults write` made while the app is running.
        CFPreferencesAppSynchronize(domain as CFString)
        return CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    public func set(_ value: Any?, forKey key: String) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }
}

/// Whether the first-run window has been shown and closed.
public enum FirstRun {
    public static let key = "onboardingCompleted"

    public static func isComplete(in store: any SettingsStore = PreferencesStore()) -> Bool {
        store.value(forKey: key) as? Bool == true
    }

    public static func markComplete(in store: any SettingsStore = PreferencesStore()) {
        store.set(true, forKey: key)
    }
}

/// An in-memory store, for tests.
public final class DictionarySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any]

    public init(_ values: [String: Any] = [:]) {
        self.values = values
    }

    public func value(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
}

/// The user-tunable "needs attention" thresholds.
///
/// Defaults equal the constants Vibra shipped with, so an untouched install
/// behaves exactly as before. `workingWindow` is not here: it is a parsing
/// tolerance, not a preference.
public struct VibraSettings: Sendable, Equatable, Codable {
    public var stallThresholdSeconds: TimeInterval
    public var attentionDecaySeconds: TimeInterval
    public var activityWindowSeconds: TimeInterval

    public struct Limit: Sendable {
        public let key: String
        public let defaultValue: TimeInterval
        public let range: ClosedRange<TimeInterval>
    }

    public static let stallThreshold = Limit(
        key: "stallThresholdSeconds", defaultValue: 300, range: 60...7200)
    public static let attentionDecay = Limit(
        key: "attentionDecaySeconds", defaultValue: 2 * 3600, range: 3600...172_800)
    public static let activityWindow = Limit(
        key: "activityWindowSeconds", defaultValue: 12 * 3600, range: 3600...259_200)

    public static let defaults = VibraSettings(
        stallThresholdSeconds: stallThreshold.defaultValue,
        attentionDecaySeconds: attentionDecay.defaultValue,
        activityWindowSeconds: activityWindow.defaultValue
    )

    public init(
        stallThresholdSeconds: TimeInterval,
        attentionDecaySeconds: TimeInterval,
        activityWindowSeconds: TimeInterval
    ) {
        self.stallThresholdSeconds = stallThresholdSeconds
        self.attentionDecaySeconds = attentionDecaySeconds
        self.activityWindowSeconds = activityWindowSeconds
    }

    /// Reads the settings, clamping out-of-range numbers to their range and
    /// replacing anything non-numeric with the default, so a bad
    /// `defaults write` cannot break classification.
    public static func load(from store: any SettingsStore = PreferencesStore()) -> VibraSettings {
        func read(_ limit: Limit) -> TimeInterval {
            clampedSetting(store.value(forKey: limit.key), default: limit.defaultValue, range: limit.range)
        }
        return VibraSettings(
            stallThresholdSeconds: read(stallThreshold),
            attentionDecaySeconds: read(attentionDecay),
            activityWindowSeconds: read(activityWindow)
        )
    }

    public func save(to store: any SettingsStore = PreferencesStore()) {
        store.set(stallThresholdSeconds, forKey: Self.stallThreshold.key)
        store.set(attentionDecaySeconds, forKey: Self.attentionDecay.key)
        store.set(activityWindowSeconds, forKey: Self.activityWindow.key)
    }

    public static func reset(in store: any SettingsStore = PreferencesStore()) {
        for limit in [stallThreshold, attentionDecay, activityWindow] {
            store.set(nil, forKey: limit.key)
        }
    }

    /// The `StateEngine` configuration these settings describe. The stall
    /// threshold is kept above the working window, whatever was stored.
    public var stateEngineConfig: StateEngineConfig {
        let base = StateEngineConfig.default
        return StateEngineConfig(
            workingWindow: base.workingWindow,
            stallThreshold: max(stallThresholdSeconds, base.workingWindow + 1),
            attentionDecay: attentionDecaySeconds
        )
    }
}

/// One clamped numeric setting from the preferences domain.
///
/// Shared with the perf thresholds, whose keys are clamped the same way: a
/// value `defaults write` put there out of range is pinned to the range, and
/// anything that is not a finite number falls back to the default. A bad
/// preference must degrade one reading, never break a reader.
func clampedSetting(_ value: Any?, default defaultValue: Double, range: ClosedRange<Double>) -> Double {
    guard let number = numericSetting(value) else { return defaultValue }
    return min(max(number, range.lowerBound), range.upperBound)
}

/// A finite number, from whatever `defaults write` put there. A string is
/// accepted only when it parses completely ("600", not "600s").
private func numericSetting(_ value: Any?) -> Double? {
    let number: Double?
    switch value {
    case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): number = n.doubleValue
    case let s as String: number = Double(s.trimmingCharacters(in: .whitespaces))
    default: number = nil
    }
    guard let number, number.isFinite else { return nil }
    return number
}
