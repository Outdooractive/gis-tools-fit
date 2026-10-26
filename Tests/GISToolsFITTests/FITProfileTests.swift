import Foundation
import Testing
@testable import GISToolsFIT

/// Tests for the FIT profile metadata and its value conversions.
struct FITProfileTests {

    @Test
    func altitudeScaleAndOffset() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 2))
        let formatted = try #require(meta.formatValue(UInt16(3_000)) as? Double)
        #expect(abs(formatted - 100.0) < 0.000_001)

        let raw = try #require(meta.rawValue(from: 100.0) as? Int64)
        #expect(raw == 3_000)
    }

    @Test
    func speedScale() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 6))
        let formatted = try #require(meta.formatValue(UInt16(3_333)) as? Double)
        #expect(abs(formatted - 3.333) < 0.000_001)

        let raw = try #require(meta.rawValue(from: 3.333) as? Int64)
        #expect(raw == 3_333)
    }

    @Test
    func positionSemicirclesConvertToDegrees() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 0))
        let raw = FIT.semicirclesFromDegrees(47.5)
        let degrees = try #require(meta.formatValue(raw) as? Double)
        #expect(abs(degrees - 47.5) < 0.000_001)

        let roundTripped = try #require(meta.rawValue(from: degrees) as? Int64)
        #expect(roundTripped == Int64(raw))
    }

    @Test
    func dateFieldsConvertToISO8601AndBack() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 253))
        let timestamp = UInt32(1_000_000_000)
        let string = try #require(meta.formatValue(timestamp) as? String)
        #expect(FIT.date(fromISO8601: string) == FIT.dateFromTimestamp(timestamp))

        let raw = try #require(meta.rawValue(from: string) as? Int64)
        #expect(raw == Int64(timestamp))
    }

    @Test
    func dateFieldsAcceptWholeSecondISO8601() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 253))
        let string = "2021-09-08T01:46:40Z"
        let raw = try #require(meta.rawValue(from: string) as? Int64)
        #expect(raw == 1_000_000_000)
    }

    @Test
    func invalidDateSentinelIsIgnored() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 253))
        #expect(meta.formatValue(UInt32.max) == nil)
    }

    @Test
    func invalidDateStringIsIgnored() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 253))
        #expect(meta.rawValue(from: "not a date") == nil)
    }

    @Test
    func arraysAreConvertedElementWise() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 18, fieldNum: 65))
        let formatted = try #require(meta.formatValue([UInt32(1_000), UInt32(2_500)] as [Any]) as? [Any])
        #expect(formatted.count == 2)
        #expect(formatted[0] as? Double == 1.0)
        #expect(formatted[1] as? Double == 2.5)

        let raw = try #require(meta.rawValue(from: formatted) as? [Any])
        #expect(raw.count == 2)
        #expect(raw[0] as? Int64 == 1_000)
        #expect(raw[1] as? Int64 == 2_500)
    }

    @Test
    func stringsPassThrough() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 0, fieldNum: 8))
        #expect(meta.formatValue("Garmin") as? String == "Garmin")
        #expect(meta.rawValue(from: "Garmin") as? String == "Garmin")
    }

    @Test
    func floatFieldsKeepFractionalValues() throws {
        let meta = try #require(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 114))
        #expect(meta.formatValue(Float(5.5)) as? Double == 5.5)
        #expect(meta.rawValue(from: 5.5) as? Double == 5.5)
    }

    @Test
    func unknownMessageAndFieldReturnNil() {
        #expect(FITProfile.fieldMetadata(mesgNum: 999, fieldNum: 0) == nil)
        #expect(FITProfile.fieldMetadata(mesgNum: 20, fieldNum: 250) == nil)
        #expect(FITProfile.fields(for: 999).isEmpty)
    }

    @Test
    func messageNamesAreStable() {
        #expect(FITProfile.messageName(mesgNum: 0) == "file_id")
        #expect(FITProfile.messageName(mesgNum: 20) == "record")
        #expect(FITProfile.messageName(mesgNum: 19) == "lap")
        #expect(FITProfile.messageName(mesgNum: 18) == "session")
        #expect(FITProfile.messageName(mesgNum: 21) == "event")
        #expect(FITProfile.messageName(mesgNum: 34) == "activity")
        #expect(FITProfile.messageName(mesgNum: 23) == "device_info")
        #expect(FITProfile.messageName(mesgNum: 999) == "unknown")
    }

}
