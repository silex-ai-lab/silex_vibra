import Foundation

/// One UTC day in the vendor's usage file.
public struct VendorDay: Sendable, Equatable {
    public let day: UTCDay
    public let tokens: Int

    public init(day: UTCDay, tokens: Int) {
        self.day = day
        self.tokens = tokens
    }
}

/// One UTC day of this Mac's own usage, already summed for one provider.
public struct LocalDay: Sendable, Equatable {
    public let day: UTCDay
    public let tokens: Int

    public init(day: UTCDay, tokens: Int) {
        self.day = day
        self.tokens = tokens
    }
}

/// A validated usage page: one provider, one API key, one entry per day.
public struct VendorUsageFile: Sendable, Equatable {
    public let provider: VendorProvider
    /// Empty when the page holds no usage at all.
    public let apiKeyID: String
    public let days: [VendorDay]

    public init(provider: VendorProvider, apiKeyID: String, days: [VendorDay]) {
        self.provider = provider
        self.apiKeyID = apiKeyID
        self.days = days
    }

    /// The oldest day in the page, or nil for a page with no buckets.
    public var oldestDay: UTCDay? { days.map(\.day).min() }
}

/// Why a page was refused. The text names the expected keys or the limit and
/// never echoes a key id or any value from the file.
public enum VendorImportError: Error, Equatable, CustomStringConvertible {
    case notJSON
    case unrecognisedShape(String)
    /// `has_more` is absent or true, so a partial page would misreport.
    case partialPage
    /// A result with usage has a null key, or the page mixes keys.
    case noSingleKey
    /// The oldest bucket is older than `VendorUsage.maxAgeDays`.
    case tooOld
    /// A bucket after the current UTC day has a result row.
    case futureDay
    /// A total cannot be represented, which no real usage page reaches.
    case countTooLarge

    public var description: String {
        switch self {
        case .notJSON:
            "This file is not JSON."
        case .unrecognisedShape(let expected):
            "This is not a usage page this build reads. Expected \(expected)."
        case .partialPage:
            "This is a partial page: has_more must be present and false. One page holds at most 31 days."
        case .noSingleKey:
            "Every result with usage must name one API key. Fetch the page grouped by api_key_id for your own key."
        case .tooOld:
            "The oldest day in this file is more than \(VendorUsage.maxAgeDays) days old."
        case .futureDay:
            "A day in this file is after today (UTC). Fetch a page that ends today or earlier."
        case .countTooLarge:
            "A total in this file is too large to be real usage."
        }
    }
}

public struct VendorReconciliation: Sendable, Equatable {
    public let incidents: [Incident]
    /// Days with no comparable local coverage, or the unfinished current day.
    public let unreconciled: [UTCDay]
    /// The id of every day the file covers, finding or not.
    public let scope: [IncidentID]

    public init(incidents: [Incident], unreconciled: [UTCDay], scope: [IncidentID] = []) {
        self.incidents = incidents
        self.unreconciled = unreconciled
        self.scope = scope
    }
}

/// The vendor usage importer and the pure reconcile.
///
/// Pure: it sees `Data` and `[UsageSample]` and returns values. It never reads a
/// file, a key or the network, and an incident it builds carries only the
/// provider, the day, the two token counts and a hashed id.
public enum VendorUsage {
    /// Older files would make the local read unbounded. The import help text
    /// states this limit.
    public static let maxAgeDays = 62

    private static let shape =
        "an Anthropic page (`data[].starting_at` with `data[].results[].{api_key_id, "
        + "uncached_input_tokens, cache_read_input_tokens, cache_creation, output_tokens}`) or an OpenAI page "
        + "(`object: page` with `data[].{start_time, results[].{api_key_id, input_tokens, "
        + "output_tokens, optional input_cached_tokens}}`)"

    // MARK: - Parse

    /// Validates one fetched page and sums each bucket into a UTC day.
    public static func parse(_ data: Data, now: Date) throws -> VendorUsageFile {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw VendorImportError.notJSON
        }
        guard let root = raw as? [String: Any],
              let buckets = root["data"] as? [[String: Any]]
        else {
            throw VendorImportError.unrecognisedShape(shape)
        }

        // Refuse a partial page before reading its results: the counts would
        // misreport, so nothing else about it is worth validating first.
        guard let hasMore = root["has_more"] as? Bool, hasMore == false else {
            throw VendorImportError.partialPage
        }

        // An OpenAI page names itself; an Anthropic page is recognised by its
        // bucket. An empty `data` array is still one provider's empty page.
        let isOpenAI = root["object"] as? String == "page"
        let provider: VendorProvider = isOpenAI ? .openai : .anthropic

        let today = UTCDay(date: now)
        var totals: [UTCDay: Int] = [:]
        var keys: Set<String> = []
        for bucket in buckets {
            let day: UTCDay
            if isOpenAI {
                guard let start = number(bucket["start_time"]) else {
                    throw VendorImportError.unrecognisedShape(shape)
                }
                day = UTCDay(date: Date(timeIntervalSince1970: TimeInterval(start)))
            } else {
                guard let text = bucket["starting_at"] as? String,
                      let date = parseISODate(text)
                else {
                    throw VendorImportError.unrecognisedShape(shape)
                }
                day = UTCDay(date: date)
            }
            guard let results = bucket["results"] as? [[String: Any]] else {
                throw VendorImportError.unrecognisedShape(shape)
            }
            // A page lists every interval, empty ones included, so an empty
            // bucket after today is padding. One with a row cannot have happened.
            if day > today {
                if results.isEmpty { continue }
                throw VendorImportError.futureDay
            }
            var tokens = 0
            for result in results {
                let key = try self.key(of: result)
                let sum = isOpenAI ? try openAITokens(result) : try anthropicTokens(result)
                tokens = try adding(tokens, sum)
                // A key on a zero row counts too, so a corrected re-import keeps
                // its identity. Under the shown filter a page holds one key.
                if let key, !key.isEmpty {
                    keys.insert(key)
                } else if sum > 0 {
                    throw VendorImportError.noSingleKey
                }
            }
            totals[day] = try adding(totals[day] ?? 0, tokens)
        }

        guard keys.count <= 1 else { throw VendorImportError.noSingleKey }

        let days = totals.keys.sorted().map { VendorDay(day: $0, tokens: totals[$0] ?? 0) }
        if let oldest = days.first?.day, ageDays(oldest, now: now) > maxAgeDays {
            throw VendorImportError.tooOld
        }
        return VendorUsageFile(provider: provider, apiKeyID: keys.first ?? "", days: days)
    }

    /// The key a result names, or nil when the documented `api_key_id` is null.
    /// An absent or non-string field is not the documented shape.
    private static func key(of result: [String: Any]) throws -> String? {
        guard let value = result["api_key_id"] else {
            throw VendorImportError.unrecognisedShape(shape)
        }
        if value is NSNull { return nil }
        guard let text = value as? String else { throw VendorImportError.unrecognisedShape(shape) }
        return text
    }

    /// `uncached_input + cache_read_input + ephemeral_1h + ephemeral_5m + output`.
    /// Cache reads and both cache-creation tiers are billed, so all are summed.
    private static func anthropicTokens(_ result: [String: Any]) throws -> Int {
        guard let cache = result["cache_creation"] as? [String: Any],
              let input = number(result["uncached_input_tokens"]),
              let read = number(result["cache_read_input_tokens"]),
              let oneHour = number(cache["ephemeral_1h_input_tokens"]),
              let fiveMinute = number(cache["ephemeral_5m_input_tokens"]),
              let output = number(result["output_tokens"])
        else {
            throw VendorImportError.unrecognisedShape(shape)
        }
        return input + read + oneHour + fiveMinute + output
    }

    /// `input_tokens + output_tokens`. `input_cached_tokens` is a subset of
    /// `input_tokens`, so adding it would double-count the cached share.
    private static func openAITokens(_ result: [String: Any]) throws -> Int {
        guard let input = number(result["input_tokens"]),
              let output = number(result["output_tokens"])
        else {
            throw VendorImportError.unrecognisedShape(shape)
        }
        return input + output
    }

    /// A file is untrusted, so a count must be a whole number in this range.
    /// Several capped fields can then be summed without overflow.
    private static let maxCount = 1_000_000_000_000_000.0

    private static func number(_ value: Any?) -> Int? {
        guard let value, let number = value as? NSNumber else { return nil }
        // A JSON boolean bridges to NSNumber; a token count is never a flag.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let exact = number.doubleValue
        guard exact >= 0, exact <= maxCount, exact.rounded(.down) == exact else { return nil }
        return number.intValue
    }

    private static func adding(_ first: Int, _ second: Int) throws -> Int {
        let (sum, overflow) = first.addingReportingOverflow(second)
        if overflow { throw VendorImportError.countTooLarge }
        return sum
    }

    /// Local counts come from transcripts, so they saturate instead of trapping.
    private static func saturating(_ first: Int, _ second: Int) -> Int {
        let (sum, overflow) = max(0, first).addingReportingOverflow(max(0, second))
        return overflow ? Int.max : sum
    }

    // MARK: - Window

    /// Whole UTC days from the oldest bucket's midnight to today, plus two.
    /// Only the report's file cutoff uses it.
    public static func windowDays(oldest: UTCDay, now: Date) -> Int {
        let today = UTCDay(date: now).start
        let whole = Int((today.timeIntervalSince(oldest.start) / 86_400).rounded(.down))
        return max(0, whole) + 2
    }

    private static func ageDays(_ oldest: UTCDay, now: Date) -> Int {
        let today = UTCDay(date: now).start
        return Int((today.timeIntervalSince(oldest.start) / 86_400).rounded(.down))
    }

    // MARK: - Local days

    /// Buckets samples by their own UTC day and sums them with the provider's
    /// own formula. Undated samples are skipped, never guessed onto a day.
    public static func localDays(from samples: [UsageSample], provider: VendorProvider) -> [LocalDay] {
        var totals: [UTCDay: Int] = [:]
        for sample in samples {
            guard let timestamp = sample.timestamp else { continue }
            let usage = sample.usage
            let parts = switch provider {
            case .anthropic:
                // `input`, not `TokenUsage.total`, is the uncached input.
                [usage.input, usage.cacheRead, usage.cacheCreation, usage.output]
            case .openai:
                // OpenAI's `input` already includes the cached share.
                [usage.input, usage.output]
            }
            let day = UTCDay(date: timestamp)
            totals[day] = parts.reduce(totals[day] ?? 0, saturating)
        }
        return totals.keys.sorted().map { LocalDay(day: $0, tokens: totals[$0] ?? 0) }
    }

    // MARK: - Reconcile

    public static func reconcile(_ file: VendorUsageFile, local: [LocalDay], now: Date) -> VendorReconciliation {
        var localTokens: [UTCDay: Int] = [:]
        for entry in local {
            localTokens[entry.day] = saturating(localTokens[entry.day] ?? 0, entry.tokens)
        }
        let earliest = local.map(\.day).min()
        let today = UTCDay(date: now)

        var incidents: [Incident] = []
        var unreconciled: [UTCDay] = []
        let scope = file.days.map { incidentID(file, $0.day) }
        for entry in file.days.sorted(by: { $0.day < $1.day }) {
            // No local coverage at all, a day before it starts, or a day still
            // in progress cannot be compared with one Mac.
            guard let earliest, entry.day >= earliest, entry.day != today else {
                unreconciled.append(entry.day)
                continue
            }
            let localValue = localTokens[entry.day] ?? 0
            let excess = entry.tokens - localValue
            // Both thresholds are a starting guess, not a measured line.
            let threshold = max(0.10 * Double(entry.tokens), 100_000)
            if Double(excess) > threshold {
                incidents.append(incident(file, entry, localTokens: localValue))
            }
        }
        return VendorReconciliation(incidents: incidents, unreconciled: unreconciled, scope: scope)
    }

    /// The key id appears only inside this hash: two keys never share an
    /// answer, and a re-import keeps the user's answer.
    private static func incidentID(_ file: VendorUsageFile, _ day: UTCDay) -> IncidentID {
        IncidentID(
            agent: nil, session: nil, kind: .unexplainedVendorUsage,
            anchor: "\(file.provider.rawValue)|\(day.iso)|\(file.apiKeyID)")
    }

    private static func incident(_ file: VendorUsageFile, _ entry: VendorDay, localTokens: Int) -> Incident {
        return Incident(
            id: incidentID(file, entry.day),
            kind: .unexplainedVendorUsage,
            agent: nil,
            evidence: .vendorFile,
            at: entry.day.start,
            completedAt: entry.day.start,
            posture: .unknown,
            detail: .vendorExcess(VendorExcess(
                provider: file.provider,
                day: entry.day,
                vendorTokens: entry.tokens,
                localTokens: localTokens)))
    }
}
