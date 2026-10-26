import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

/// Tests for the typed `Feature` and `FeatureCollection` convenience API.
struct FeaturePropertiesTests {

    @Test
    func pointPositionAndAltitudeComeFromGeometry() {
        let coordinate = Coordinate3D(latitude: 47.5, longitude: 11.5, altitude: 812.0)
        let feature = Feature(Point(coordinate))

        #expect(feature.fitPositionLat == 47.5)
        #expect(feature.fitPositionLon == 11.5)
        #expect(feature.fitAltitude == 812.0)
    }

    @Test
    func timestampPropertiesRoundTrip() throws {
        var feature = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        feature.fitTimestamp = date
        #expect(feature.fitTimestamp == date)

        feature.fitStartTime = date.addingTimeInterval(60)
        #expect(feature.fitStartTime == date.addingTimeInterval(60))
    }

    @Test
    func singleRecordPropertiesRoundTrip() {
        var feature = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        feature.fitHeartRate = 142
        feature.fitCadence = 88
        feature.fitPower = 250
        feature.fitSpeed = 3.5
        feature.fitTemperature = 21.5
        feature.fitDistance = 1_234.5
        feature.fitTotalDistance = 5_000.0
        feature.fitTotalElapsedTime = 3_600.0
        feature.fitTotalCalories = 800
        feature.fitAvgHeartRate = 145
        feature.fitMaxHeartRate = 175
        feature.fitAvgSpeed = 3.4
        feature.fitMaxSpeed = 5.2
        feature.fitTotalAscent = 150.0
        feature.fitTotalDescent = 120.0

        #expect(feature.fitHeartRate == 142)
        #expect(feature.fitCadence == 88)
        #expect(feature.fitPower == 250)
        #expect(feature.fitSpeed == 3.5)
        #expect(feature.fitTemperature == 21.5)
        #expect(feature.fitDistance == 1_234.5)
        #expect(feature.fitTotalDistance == 5_000.0)
        #expect(feature.fitTotalElapsedTime == 3_600.0)
        #expect(feature.fitTotalCalories == 800)
        #expect(feature.fitAvgHeartRate == 145)
        #expect(feature.fitMaxHeartRate == 175)
        #expect(feature.fitAvgSpeed == 3.4)
        #expect(feature.fitMaxSpeed == 5.2)
        #expect(feature.fitTotalAscent == 150.0)
        #expect(feature.fitTotalDescent == 120.0)
    }

    @Test
    func enhancedFieldsAreFallbacks() {
        var feature = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        feature.properties["enhanced_speed"] = 4.25
        feature.properties["enhanced_altitude"] = 321.0

        #expect(feature.fitSpeed == 4.25)
        #expect(feature.fitAltitude == 321.0)
    }

    @Test
    func fitTypeRoundTrips() {
        var feature = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        #expect(feature.fitType == nil)

        feature.fitType = .lap
        #expect(feature.fitType == .lap)
        #expect(feature.properties["fit_type"] as? String == "lap")

        feature.fitType = nil
        #expect(feature.fitType == nil)
    }

    @Test
    func enumNamesAreResolvedFromDifferentNumericTypes() {
        var feature = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        feature.properties["event"] = 9
        #expect(feature.fitEnumName(for: "event") == "lap")

        feature.properties["event"] = Int64(3)
        #expect(feature.fitEnumName(for: "event") == "workout")

        feature.properties["event"] = UInt8(26)
        #expect(feature.fitEnumName(for: "event") == "activity")

        feature.properties["event"] = "not an enum"
        #expect(feature.fitEnumName(for: "event") == nil)
    }

    @Test
    func perPointArraysAreExposed() {
        var feature = Feature(MultiLineString(unchecked: [
            LineString(unchecked: [
                Coordinate3D(latitude: 47.0, longitude: 11.0, altitude: 100.0),
                Coordinate3D(latitude: 47.1, longitude: 11.1, altitude: 200.0),
            ]),
        ]))
        feature.properties["fit_heart_rates"] = [120, 130] as [Int?]
        feature.properties["fit_cadences"] = [80, 90] as [Int?]
        feature.properties["fit_powers"] = [200, 250] as [Int?]
        feature.properties["fit_speeds"] = [3.0, 4.0] as [Double?]
        feature.properties["fit_temperatures"] = [20.0, 21.0] as [Double?]
        feature.properties["fit_timestamps"] = [
            FIT.iso8601String(from: FIT.epoch),
            FIT.iso8601String(from: FIT.epoch.addingTimeInterval(10)),
        ] as [String?]

        #expect(feature.fitHeartRates == [120, 130])
        #expect(feature.fitCadences == [80, 90])
        #expect(feature.fitPowers == [200, 250])
        #expect(feature.fitSpeeds == [3.0, 4.0])
        #expect(feature.fitTemperatures == [20.0, 21.0])
        #expect(feature.fitAltitudes == [100.0, 200.0])
        #expect(feature.fitTimestamps?.count == 2)
        #expect(feature.fitTimestamps?[0] == FIT.epoch)
        #expect(feature.fitTimestamps?[1] == FIT.epoch.addingTimeInterval(10))
    }

    @Test
    func pointFeaturesPreserveAltitudesInCoordinates() {
        var feature = Feature(MultiLineString(unchecked: [
            LineString(unchecked: [
                Coordinate3D(latitude: 47.0, longitude: 11.0, altitude: 100.0),
                Coordinate3D(latitude: 47.1, longitude: 11.1, altitude: 200.0),
            ]),
        ]))
        feature.properties["fit_heart_rates"] = [120, 130] as [Int?]

        let points = feature.fitPointFeatures()
        #expect(points.features.count == 2)
        #expect(points.features[0].properties["heart_rate"] as? Int == 120)
        #expect((points.features[0].geometry as? Point)?.coordinate.altitude == 100.0)
        #expect((points.features[1].geometry as? Point)?.coordinate.altitude == 200.0)
        #expect(points.features[0].properties["altitude"] == nil)
    }

    @Test
    func emptyTrackProducesNoPointFeatures() {
        let feature = Feature(MultiLineString())
        #expect(feature.fitPointFeatures().features.isEmpty)
        #expect(feature.fitAltitudes == nil)
    }

    @Test
    func trackReconstructionReturnsNilWithoutPoints() {
        #expect(FeatureCollection().fitTrackFromPointFeatures() == nil)
        #expect(Feature(fitTrackFrom: FeatureCollection()) == nil)
    }

    @Test
    func trackReconstructionAcceptsDateTimestamps() throws {
        var first = Feature(Point(Coordinate3D(latitude: 47.0, longitude: 11.0)))
        first.properties["timestamp"] = FIT.epoch
        first.properties["heart_rate"] = Int64(120)

        var second = Feature(Point(Coordinate3D(latitude: 47.1, longitude: 11.1)))
        second.properties["timestamp"] = FIT.epoch.addingTimeInterval(5)
        second.properties["heart_rate"] = 130

        let collection = FeatureCollection([first, second])
        let track = try #require(collection.fitTrackFromPointFeatures())
        #expect(track.fitHeartRates == [120, 130])
        #expect(track.fitTimestamps?.count == 2)
        #expect(track.fitTimestamps?[0] == FIT.epoch)
    }

    @Test
    func collectionMetadataPropertiesRoundTrip() {
        let collection = FeatureCollection()
        var copy = collection
        copy.fitDevice = ["manufacturer": 1, "product_name": "Edge"]
        copy.fitDevices = [["device_index": 0], ["device_index": 1]]
        copy.fitSessions = [["sport": 1], ["sport": 2]]
        copy.fitActivity = ["type": 0, "num_sessions": 2]

        #expect(copy.fitDevice?["product_name"] as? String == "Edge")
        #expect(copy.fitDevices?.count == 2)
        #expect(copy.fitSessions?.count == 2)
        #expect(copy.fitActivity?["num_sessions"] as? Int == 2)
    }

}
