import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

/// Tests for the `FeatureCollection` FIT conveniences.
struct FITFeatureCollectionTests {

    private func sampleData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "fit", subdirectory: "TestData") else {
            throw TestError.missingResource
        }
        return try Data(contentsOf: url)
    }

    private enum TestError: Error {
        case missingResource
    }

    @Test
    func convenienceInitializersReadTheSample() throws {
        let data = try sampleData()
        let fromData = try #require(FeatureCollection(fitData: data))
        #expect(fromData.fitRecords.count == 1)

        let sampleURL = try #require(Bundle.module.url(
            forResource: "sample",
            withExtension: "fit",
            subdirectory: "TestData"))
        let fromURL = try #require(FeatureCollection(fit: sampleURL))
        #expect(fromURL.fitRecords.count == 1)

        #expect(FeatureCollection(fit: URL(fileURLWithPath: "/nonexistent.fit")) == nil)
        #expect(FeatureCollection(fitData: Data()) == nil)
    }

    @Test
    func writeFITWritesAReadableFile() throws {
        let collection = try #require(FeatureCollection(fitData: try sampleData()))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gis-tools-fit-\(UUID().uuidString).fit")
        defer { try? FileManager.default.removeItem(at: url) }

        try collection.writeFIT(to: url)
        let written = try Data(contentsOf: url)
        let readBack = try FITCoder.read(from: written)
        #expect(readBack.fitRecords.count == 1)
        #expect(readBack.features.count == collection.features.count)
    }

    @Test
    func fitSportFallsBackToActivityMetadata() {
        let track = Feature(MultiLineString())
        var collection = FeatureCollection([track])
        collection.fitActivity = ["sub_sport": 1]
        #expect(collection.fitSport == "treadmill")

        collection.fitActivity = ["sport": 2]
        #expect(collection.fitSport == "cycling")

        collection.fitActivity = [:]
        #expect(collection.fitSport == nil)
    }

    @Test
    func fitSportPrefersTheTrackSession() {
        var track = Feature(MultiLineString())
        track.fitType = .record
        track.properties["sport"] = 1
        var collection = FeatureCollection([track])
        collection.fitActivity = ["sport": 2]
        #expect(collection.fitSport == "running")
    }

    @Test
    func fitSportUsesTrackSubSportWhenSportIsMissing() {
        var track = Feature(MultiLineString())
        track.fitType = .record
        track.properties["sub_sport"] = 1
        let collection = FeatureCollection([track])
        #expect(collection.fitSport == "treadmill")
    }

    @Test
    func fitPointFeaturesWithoutTimestampsReturnsAllPoints() {
        let track = Feature(MultiLineString(unchecked: [
            LineString(unchecked: [
                Coordinate3D(latitude: 47.0, longitude: 11.0),
                Coordinate3D(latitude: 47.1, longitude: 11.1),
            ]),
        ]))
        let points = track.fitPointFeatures(
            from: FIT.epoch,
            to: FIT.epoch.addingTimeInterval(10))
        #expect(points.features.count == 2)
    }

    @Test
    func fractionalSlicingHandlesAnEmptyGeometry() {
        let track = Feature(MultiLineString())
        #expect(track.fitPointFeatures(fraction: 0.0, to: 1.0).features.isEmpty)
    }

    @Test
    func numericPropertyConversionsHandleAllStoredTypes() {
        var feature = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        feature.properties["heart_rate"] = UInt32(150)
        #expect(feature.fitHeartRate == 150)

        feature.properties["heart_rate"] = Int32(151)
        #expect(feature.fitHeartRate == 151)

        feature.properties["heart_rate"] = UInt64(152)
        #expect(feature.fitHeartRate == 152)

        feature.properties["heart_rate"] = Float(153.5)
        #expect(feature.fitHeartRate == 153)

        feature.properties["speed"] = Int32(4)
        #expect(feature.fitSpeed == 4.0)

        feature.properties["speed"] = UInt32(5)
        #expect(feature.fitSpeed == 5.0)

        feature.properties["speed"] = UInt64(6)
        #expect(feature.fitSpeed == 6.0)

        feature.properties["speed"] = Int16(7)
        #expect(feature.fitSpeed == 7.0)

        feature.properties["speed"] = Int8(8)
        #expect(feature.fitSpeed == 8.0)
    }

    @Test
    func nonPointPositionsUseProperties() {
        var feature = Feature(MultiLineString())
        feature.properties["position_lat"] = 48.5
        feature.properties["position_long"] = 12.5
        #expect(feature.fitPositionLat == 48.5)
        #expect(feature.fitPositionLon == 12.5)

        feature.properties["position_lat"] = nil
        feature.properties["position_long"] = nil
        feature.properties["start_position_lat"] = 49.5
        feature.properties["start_position_long"] = 13.5
        #expect(feature.fitPositionLat == 49.5)
        #expect(feature.fitPositionLon == 13.5)
    }

    @Test
    func enumNamesHandleRemainingIntegerWidths() {
        var feature = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        feature.properties["event"] = UInt16(9)
        #expect(feature.fitEnumName(for: "event") == "lap")

        feature.properties["event"] = UInt32(9)
        #expect(feature.fitEnumName(for: "event") == "lap")

        #expect(feature.fitEnumName(for: "missing") == nil)
    }

    @Test
    func timestampsIgnoreInvalidProperties() {
        var feature = Feature(MultiLineString())
        feature.properties["fit_timestamps"] = ["not a date", nil, FIT.iso8601String(from: FIT.epoch)] as [String?]
        let dates = feature.fitTimestamps
        #expect(dates?.count == 3)
        #expect(dates?[0] == nil)
        #expect(dates?[1] == nil)
        #expect(dates?[2] == FIT.epoch)
    }

    @Test
    func datePropertiesIgnoreMissingAndInvalidStrings() {
        var feature = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        #expect(feature.fitTimestamp == nil)
        feature.properties["fit_timestamp"] = "not a date"
        #expect(feature.fitTimestamp == nil)
    }

}
