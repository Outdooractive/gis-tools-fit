import Foundation
import Testing
@testable import GISToolsFIT

/// Regression tests for the FIT epoch and timestamp conversion.
///
/// The FIT epoch is `1989-12-31T00:00:00Z` (UTC). The Garmin FIT profile
/// defines timestamps as seconds since that instant. Because the epoch used
/// to be derived from `DateComponents` without pinning a time zone, the
/// resulting `Date` shifted by the system's local offset — for users in
/// `America/Los_Angeles` the epoch became `1989-12-31 08:00:00Z`, eight
/// hours ahead of the spec, corrupting every decoded timestamp.
struct FITEpochTests {

    @Test
    func epochIs19891231AtMidnightUTC() async throws {
        // 1989-12-31T00:00:00Z is exactly 631065600 seconds after the Unix epoch.
        #expect(FIT.epoch.timeIntervalSince1970 == 631065600.0)
    }

    @Test
    func dateFromTimestampRoundsToExpectedDate() async throws {
        // 1_000_000_000 seconds after the FIT epoch == 2021-09-08T01:46:40Z.
        let date = FIT.dateFromTimestamp(1_000_000_000)
        let expected = Date(timeIntervalSince1970: 631065600.0 + 1_000_000_000.0)
        #expect(abs(date.timeIntervalSince(expected)) < 0.001)
    }

    @Test
    func timestampZeroIsFITEpoch() async throws {
        #expect(FIT.dateFromTimestamp(0) == FIT.epoch)
    }
}