import Foundation
import Testing
@testable import VibraCore

/// `--wait-stats` argument and timestamp parsing at their edges, matching the
/// Python oracle (`tools/wait-oracle/oracle_selftest.py`).
struct WaitWindowTests {
    private func days(_ text: String?) -> Result<WaitWindow, WaitWindowError> {
        WaitWindow.parse(days: .some(text), from: nil, to: nil, now: 10_000_000_000_000, timeZone: TimeZone(identifier: "UTC")!)
    }

    @Test func daysIsBoundedSoTheWindowCannotOverflow() throws {
        #expect(try days("36500").get() == WaitWindow(lo: 10_000_000_000_000 - 36_500 * 86_400_000, hi: 10_000_000_000_001))
        for bad in ["36501", "106751991168", "999999999999999999", "99999999999999999999999"] {
            #expect(throws: WaitWindowError.self) { try days(bad).get() }
        }
    }

    @Test func onlyASCIIDigitsCount() {
        #expect(throws: WaitWindowError.self) { try days("\u{0663}").get() }
        let arabicDate = WaitWindow.parse(
            days: nil, from: .some("2026-11-\u{0660}\u{0661}"), to: .some("2026-11-02"), now: 0,
            timeZone: TimeZone(identifier: "UTC")!)
        #expect(throws: WaitWindowError.self) { try arabicDate.get() }
        #expect(epochMs(fromTimestamp: "2026-11-1\u{0660}T00:00:00Z") == nil)
    }

    @Test func fromAndToStayWithinTheSharedYearRange() {
        func range(_ from: String, _ to: String) -> Result<WaitWindow, WaitWindowError> {
            WaitWindow.parse(days: nil, from: .some(from), to: .some(to), now: 0, timeZone: TimeZone(identifier: "UTC")!)
        }
        #expect((try? range("9998-12-31", "9998-12-31").get()) != nil)
        #expect((try? range("1970-01-01", "1970-01-01").get()) == WaitWindow(lo: 0, hi: 86_400_000))
        #expect(throws: WaitWindowError.self) { try range("9999-12-31", "9999-12-31").get() }
        #expect(throws: WaitWindowError.self) { try range("1969-12-31", "1970-01-01").get() }
    }

    @Test func eachEndIsItsOwnLocalMidnight() throws {
        func range(_ tz: String, _ from: String, _ to: String) -> Result<WaitWindow, WaitWindowError> {
            WaitWindow.parse(days: nil, from: .some(from), to: .some(to), now: 0, timeZone: TimeZone(identifier: tz)!)
        }
        // Midnight is skipped on 2018-11-04 in Sao Paulo: the day starts at 01:00 (-02:00), and the next
        // midnight is resolved on its own, not as 01:00 plus a day.
        #expect(try range("America/Sao_Paulo", "2018-11-04", "2018-11-04").get()
            == WaitWindow(lo: 1_541_300_400_000, hi: 1_541_383_200_000))
        // 2011-12-30 does not exist in Apia, as a day or as the day after --to.
        #expect(throws: WaitWindowError.self) { try range("Pacific/Apia", "2011-12-30", "2011-12-30").get() }
        #expect(throws: WaitWindowError.self) { try range("Pacific/Apia", "2011-12-29", "2011-12-29").get() }
        #expect((try? range("Pacific/Apia", "2011-12-31", "2011-12-31").get()) != nil)
    }

    @Test func yearZeroIsNotATimestamp() {
        #expect(epochMs(fromTimestamp: "0000-01-01T00:00:00Z") == nil)
        #expect(epochMs(fromTimestamp: "0001-01-01T00:00:00Z") == -62_135_596_800_000)
        #expect(epochMs(fromTimestamp: "2026-11-10T00:00:00Z") == 1_794_268_800_000)
    }
}
