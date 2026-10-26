import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

/// Tests for FIT math helpers and the public error/enum helpers.
struct FITMathTests {

    @Test
    func semicircleConversionRoundsToNearestValue() {
        #expect(FIT.semicirclesFromDegrees(90.0) == 1_073_741_824)
        #expect(FIT.semicirclesFromDegrees(-90.0) == -1_073_741_824)
        #expect(FIT.semicirclesFromDegrees(47.5) == 566_697_074)
        #expect(abs(FIT.degreesFromSemicircles(566_697_074) - 47.5) < 0.000_001)
    }

    @Test
    func semicircleConversionClampsAtTheRepresentableRange() {
        #expect(FIT.semicirclesFromDegrees(180.0) == Int32.max)
        #expect(FIT.semicirclesFromDegrees(1_000.0) == Int32.max)
        #expect(FIT.semicirclesFromDegrees(-180.0) == Int32.min)
        #expect(FIT.semicirclesFromDegrees(-1_000.0) == Int32.min)
    }

    @Test
    func semicircleConversionHandlesNonFiniteValues() {
        #expect(FIT.semicirclesFromDegrees(.nan) == 0)
        #expect(FIT.semicirclesFromDegrees(.infinity) == 0)
        #expect(FIT.semicirclesFromDegrees(-.infinity) == 0)
    }

    @Test
    func timestampConversionRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let timestamp = FIT.timestamp(from: date)
        #expect(FIT.dateFromTimestamp(timestamp) == date)
    }

    @Test
    func timestampConversionClampsBeforeTheInvalidSentinel() {
        #expect(FIT.timestamp(from: FIT.epoch.addingTimeInterval(-1)) == 0)
        #expect(FIT.timestamp(from: Date(timeIntervalSince1970: 10_000_000_000)) == UInt32.max - 1)
    }

    @Test
    func iso8601ParsingAcceptsBothForms() {
        let expected = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(FIT.date(fromISO8601: "2023-11-14T22:13:20Z") == expected)
        #expect(FIT.date(fromISO8601: "2023-11-14T22:13:20.000Z") == expected)
        #expect(FIT.date(fromISO8601: "not a date") == nil)
    }

    @Test
    func fitErrorDescriptionsAreStable() {
        #expect(FITError.fileReadError(detail: "x").errorDescription == "Could not read FIT file: x")
        #expect(FITError.fileWriteError(detail: "x").errorDescription == "Could not write FIT file: x")
        #expect(FITError.invalidFile(detail: "x").errorDescription == "Invalid FIT file: x")
        #expect(FITError.parseError(detail: "x").errorDescription == "FIT parse error: x")
    }

    @Test
    func activityTypeEnumIsResolvable() {
        // `type` is shared by file_id and activity messages. File values win
        // when they are unambiguous; activity values are used as a fallback.
        #expect(FIT.name(for: "type", value: 4) == "activity")
        #expect(FIT.name(for: "type", value: 0) == "manual")
        #expect(FIT.name(for: "type", value: 1) == "device")
        #expect(FIT.name(for: "activity", value: 1) == "auto_multi_sport")
    }

    @Test
    func enumOverloadsAcceptNarrowIntegerTypes() {
        #expect(FIT.name(for: "sport", value: UInt8(1)) == "running")
        #expect(FIT.name(for: "sport", value: UInt16(2)) == "cycling")
        #expect(FIT.name(for: "sport", value: UInt8(255)) == nil)
    }

}
