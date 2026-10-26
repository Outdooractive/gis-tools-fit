import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

/// End-to-end tests for the FIT ↔ GeoJSON conversion, including edge cases
/// that are not covered by the bundled sample file.
struct CoderEdgeCaseTests {

    // MARK: - Enhanced fields

    @Test
    func enhancedSpeedAndAltitudeAreUsedAsFallbacks() throws {
        let data = makeRecordFile(
            fields: [
                (253, 4, 0x86),
                (0, 4, 0x85),
                (1, 4, 0x85),
                (73, 4, 0x86),
                (78, 4, 0x86),
                (3, 1, 0x02),
            ],
            records: [
                recordBytes(timestamp: 1_000_000_000, lat: 47.0, lon: 11.0, values: [
                    FITTestBuilder.le32(3_333),
                    FITTestBuilder.le32(3_000),
                    Data([140]),
                ]),
                recordBytes(timestamp: 1_000_000_100, lat: 48.0, lon: 12.0, values: [
                    FITTestBuilder.le32(4_000),
                    FITTestBuilder.le32(3_500),
                    Data([150]),
                ]),
            ])

        let fc = try FITCoder.read(from: data)
        let track = try #require(fc.features.first { $0.fitType == .record })
        #expect(track.fitSpeeds?.count == 2)
        #expect(abs((track.fitSpeeds?[0] ?? 0) - 3.333) < 0.000_001)
        #expect(abs((track.fitSpeeds?[1] ?? 0) - 4.0) < 0.000_001)
        #expect(track.fitHeartRates == [140, 150])
        #expect(track.properties["fit_record_enhanced_speed"] != nil)
        #expect(track.properties["fit_record_enhanced_altitude"] != nil)

        let multiLine = try #require(track.geometry as? MultiLineString)
        let coords = multiLine.lineStrings.flatMap(\.coordinates)
        #expect(coords.count == 2)
        #expect(coords[0].altitude == 100.0)
        #expect(coords[1].altitude == 200.0)

        // Round-trip keeps the values (the encoder may normalise the
        // representation to the legacy speed/altitude fields).
        let reencoded = try FITCoder.write(fc)
        let fc2 = try FITCoder.read(from: reencoded)
        let track2 = try #require(fc2.features.first { $0.fitType == .record })
        #expect(abs((track2.fitSpeeds?[0] ?? 0) - 3.333) < 0.000_001)
        #expect(abs((track2.fitSpeeds?[1] ?? 0) - 4.0) < 0.000_001)
        let multiLine2 = try #require(track2.geometry as? MultiLineString)
        #expect(multiLine2.lineStrings.flatMap(\.coordinates)[0].altitude == 100.0)
    }

    // MARK: - Per-field array alignment

    @Test
    func perFieldArraysKeepAlignmentWhenValuesAreMissing() throws {
        let data = makeRecordFile(
            fields: [
                (253, 4, 0x86),
                (0, 4, 0x85),
                (1, 4, 0x85),
                (5, 4, 0x86),
            ],
            records: [
                recordBytes(timestamp: 1_000_000_000, lat: 47.0, lon: 11.0, values: [
                    FITTestBuilder.le32(10_000),
                ]),
                recordBytes(timestamp: 1_000_000_100, lat: 48.0, lon: 12.0, values: [
                    FITTestBuilder.le32(UInt32.max),
                ]),
                recordBytes(timestamp: 1_000_000_200, lat: 49.0, lon: 13.0, values: [
                    FITTestBuilder.le32(30_000),
                ]),
            ])

        let fc = try FITCoder.read(from: data)
        let track = try #require(fc.features.first { $0.fitType == .record })
        let distances = try #require(track.properties["fit_record_distance"] as? [Sendable?])
        #expect(distances.count == 3)
        #expect(distances[0] as? Double == 100.0)
        #expect(distances[1] == nil)
        #expect(distances[2] as? Double == 300.0)

        let reencoded = try FITCoder.write(fc)
        let messages = try FITDecoder.decode(data: reencoded)
        let records = messages.filter { $0.globalMessageNumber == 20 }
        #expect(records.count == 3)
        #expect(records[0].fields[5] as? UInt32 == 10_000)
        #expect(records[1].fields[5] == nil)
        #expect(records[2].fields[5] as? UInt32 == 30_000)
    }

    // MARK: - Laps and markers

    @Test
    func sampleFileIsSplitIntoOneLineStringPerLap() throws {
        let fc = try FITCoder.read(from: sampleData())
        let track = try #require(fc.features.first { $0.fitType == .record })
        let multiLine = try #require(track.geometry as? MultiLineString)
        #expect(multiLine.lineStrings.count == 3)
        #expect(multiLine.lineStrings.allSatisfy { $0.coordinates.count == 10 })
    }

    @Test
    func eventMarkersUseTheNearestRecord() throws {
        let fc = try FITCoder.read(from: sampleData())
        let track = try #require(fc.features.first { $0.fitType == .record })
        let multiLine = try #require(track.geometry as? MultiLineString)
        let coords = multiLine.lineStrings.flatMap(\.coordinates)

        let events = fc.features.filter { $0.fitType == .event }
        #expect(events.count == 2)
        let first = try #require(events[0].geometry as? Point)
        let last = try #require(events[1].geometry as? Point)
        #expect(abs(first.coordinate.latitude - coords[0].latitude) < 0.000_001)
        #expect(abs(first.coordinate.longitude - coords[0].longitude) < 0.000_001)
        #expect(abs(last.coordinate.latitude - coords[29].latitude) < 0.000_001)
        #expect(abs(last.coordinate.longitude - coords[29].longitude) < 0.000_001)
    }

    @Test
    func lapMarkersPreferTheLapStartPosition() throws {
        var body = Data()
        body.append(FITTestBuilder.definition(
            local: 0,
            global: 19,
            fields: [
                (253, 4, 0x86),
                (2, 4, 0x86),
                (3, 4, 0x85),
                (4, 4, 0x85),
            ]))
        body.append(FITTestBuilder.dataHeader(local: 0))
        body.append(FITTestBuilder.le32(1_000_000_000))
        body.append(FITTestBuilder.le32(1_000_000_000))
        body.append(FITTestBuilder.sint32(FITTestBuilder.semicircles(47.5)))
        body.append(FITTestBuilder.sint32(FITTestBuilder.semicircles(11.5)))

        let data = FITTestBuilder.file(body: body)
        let fc = try FITCoder.read(from: data)
        let lap = try #require(fc.features.first { $0.fitType == .lap })
        let point = try #require(lap.geometry as? Point)
        #expect(abs(point.coordinate.latitude - 47.5) < 0.000_001)
        #expect(abs(point.coordinate.longitude - 11.5) < 0.000_001)
        #expect(abs((lap.fitPositionLat ?? 0) - 47.5) < 0.000_001)
        #expect(abs((lap.fitPositionLon ?? 0) - 11.5) < 0.000_001)
    }

    // MARK: - Multiple device_info and session messages

    @Test
    func multipleDeviceInfoMessagesArePreserved() throws {
        let data = makeDeviceInfoFile()
        let fc = try FITCoder.read(from: data)
        #expect(fc.fitDevices?.count == 2)
        #expect(fc.fitDevices?[0]["descriptor"] as? String == "Primary")
        #expect(fc.fitDevices?[1]["descriptor"] as? String == "Sensor")
        #expect(fc.fitDevice?["descriptor"] as? String == "Primary")

        let reencoded = try FITCoder.write(fc)
        let messages = try FITDecoder.decode(data: reencoded)
        let devices = messages.filter { $0.globalMessageNumber == 23 }
        #expect(devices.count == 2)
        #expect(devices[0].fields[19] as? String == "Primary")
        #expect(devices[1].fields[19] as? String == "Sensor")
    }

    @Test
    func multipleSessionMessagesArePreserved() throws {
        let data = makeSessionFile()
        let fc = try FITCoder.read(from: data)
        #expect(fc.fitSessions?.count == 2)
        #expect(fc.fitSport == "cycling")

        let reencoded = try FITCoder.write(fc)
        let messages = try FITDecoder.decode(data: reencoded)
        let sessions = messages.filter { $0.globalMessageNumber == 18 }
        #expect(sessions.count == 2)
        #expect(sessions[0].fields[5] as? UInt8 == 1)
        #expect(sessions[1].fields[5] as? UInt8 == 2)
    }

    // MARK: - Message preservation

    @Test
    func reencodingDoesNotInventEmptyMessages() throws {
        let data = makeRecordFile(
            fields: [
                (253, 4, 0x86),
                (0, 4, 0x85),
                (1, 4, 0x85),
            ],
            records: [
                recordBytes(timestamp: 1_000_000_000, lat: 47.0, lon: 11.0, values: []),
            ])

        let fc = try FITCoder.read(from: data)
        let reencoded = try FITCoder.write(fc)
        let messages = try FITDecoder.decode(data: reencoded)
        let counts = Dictionary(grouping: messages, by: \.globalMessageNumber).mapValues(\.count)
        #expect(counts[20] == 1)
        #expect(counts[19] == nil)
        #expect(counts[18] == nil)
        #expect(counts[21] == nil)
        #expect(counts[23] == nil)
        #expect(counts[34] == nil)
    }

    // MARK: - Projections

    @Test
    func writingReprojectsCoordinatesToWGS84() throws {
        let coordinates = [
            Coordinate3D(latitude: 47.0, longitude: 11.0),
            Coordinate3D(latitude: 47.1, longitude: 11.1),
        ].map { $0.projected(to: .epsg3857) }

        let multiLine = MultiLineString(unchecked: [
            LineString(unchecked: coordinates),
        ])
        var track = Feature(multiLine)
        track.properties["fit_type"] = FITRecordType.record.rawValue

        let fc = FeatureCollection([track])
        let data = try FITCoder.write(fc)
        let decoded = try FITCoder.read(from: data)
        let decodedTrack = try #require(decoded.features.first { $0.fitType == .record })
        let decodedMultiLine = try #require(decodedTrack.geometry as? MultiLineString)
        let decodedCoordinates = decodedMultiLine.lineStrings.flatMap(\.coordinates)
        #expect(decodedCoordinates.count == 2)
        #expect(abs(decodedCoordinates[0].latitude - 47.0) < 0.000_001)
        #expect(abs(decodedCoordinates[0].longitude - 11.0) < 0.000_001)
        #expect(abs(decodedCoordinates[1].latitude - 47.1) < 0.000_001)
        #expect(abs(decodedCoordinates[1].longitude - 11.1) < 0.000_001)
    }

    // MARK: - Point features and slicing

    @Test
    func pointFeaturesCarryNonStandardRecordFields() throws {
        let fc = try FITCoder.read(from: sampleData())
        let track = try #require(fc.features.first { $0.fitType == .record })
        let points = track.fitPointFeatures()
        #expect(points.features.count == 30)

        let second = points.features[1]
        #expect(second.properties["distance"] as? Double == 400.0)
        #expect(second.properties["enhanced_speed"] as? Double == 3.333)
        #expect(second.properties["grade"] as? Double == 0.5)

        let rebuilt = try #require(points.fitTrackFromPointFeatures())
        let distances = try #require(rebuilt.properties["fit_record_distance"] as? [Sendable?])
        #expect(distances.count == 30)
        #expect(distances[0] as? Double == 0.0)
        #expect(distances[1] as? Double == 400.0)
        #expect(distances[29] as? Double == 11_600.0)

        // Unknown properties on point features are not invented as FIT
        // record fields.
        var namedFeatures = points.features
        namedFeatures[0].properties["name"] = "first"
        let pointsWithName = FeatureCollection(namedFeatures)
        let rebuiltWithName = try #require(pointsWithName.fitTrackFromPointFeatures())
        #expect(rebuiltWithName.properties["fit_record_name"] == nil)
    }

    @Test
    func distanceAndFractionSlicingAreAccurate() throws {
        let coordinates = (0..<5).map {
            Coordinate3D(latitude: 0.0, longitude: Double($0) * 0.001)
        }
        var track = Feature(MultiLineString(unchecked: [
            LineString(unchecked: coordinates),
        ]))
        let timestamps = (0..<5).map {
            FIT.iso8601String(from: FIT.epoch.addingTimeInterval(Double($0) * 100.0))
        }
        track.properties["fit_timestamps"] = timestamps as [String?]
        track.properties["fit_heart_rates"] = [1, 2, 3, 4, 5] as [Int?]

        let first250m = track.fitPointFeatures(from: 0.0, to: 250.0)
        #expect(first250m.features.count == 3)
        #expect(first250m.features.map { $0.properties["heart_rate"] as? Int } == [1, 2, 3])

        let middleHalf = track.fitPointFeatures(fraction: 0.0, to: 0.5)
        #expect(middleHalf.features.count == 3)

        let timeWindow = track.fitPointFeatures(
            from: FIT.epoch.addingTimeInterval(100.0),
            to: FIT.epoch.addingTimeInterval(300.0))
        #expect(timeWindow.features.count == 3)
        #expect(timeWindow.features.map { $0.properties["heart_rate"] as? Int } == [2, 3, 4])

        let empty = track.fitPointFeatures(
            from: FIT.epoch.addingTimeInterval(1_000.0),
            to: FIT.epoch.addingTimeInterval(2_000.0))
        #expect(empty.features.isEmpty)
    }


    // MARK: - Array fields

    @Test
    func sessionArraysSurviveRoundTrip() throws {
        let fc = try FITCoder.read(from: sampleData())
        let session = try #require(fc.fitSessions?.first)
        let zones = try #require(session["time_in_hr_zone"] as? [Sendable])
        #expect(zones.count == 5)

        let reencoded = try FITCoder.write(fc)
        let messages = try FITDecoder.decode(data: reencoded)
        let sessionMessage = try #require(messages.first { $0.globalMessageNumber == 18 })
        let rawZones = try #require(sessionMessage.fields[65] as? [Any])
        #expect(rawZones.count == 5)
        #expect(rawZones[0] as? UInt32 == 600_000)
        #expect(rawZones[1] as? UInt32 == 900_000)
    }

    @Test
    func reencodedSampleKeepsLapSegments() throws {
        let fc = try FITCoder.read(from: sampleData())
        let reencoded = try FITCoder.write(fc)
        let decoded = try FITCoder.read(from: reencoded)
        let track = try #require(decoded.features.first { $0.fitType == .record })
        let multiLine = try #require(track.geometry as? MultiLineString)
        #expect(multiLine.lineStrings.count == 3)
        #expect(multiLine.lineStrings.allSatisfy { $0.coordinates.count == 10 })
    }

    // MARK: - Options and file errors

    @Test
    func headerCRCOptionIsWrittenAndReadable() throws {
        let fc = try FITCoder.read(from: makeRecordFile(
            fields: [
                (253, 4, 0x86),
                (0, 4, 0x85),
                (1, 4, 0x85),
            ],
            records: [
                recordBytes(timestamp: 1_000_000_000, lat: 47.0, lon: 11.0, values: []),
            ]))
        let data = try fc.fitData(options: FITWriteOptions(includeHeaderCRC: true))
        #expect(data[0] == 14)
        let decoded = try FITCoder.read(from: data)
        #expect(decoded.features.isEmpty == false)
    }

    @Test
    func crcVerificationCanBeDisabled() throws {
        let fc = try FITCoder.read(from: makeRecordFile(
            fields: [
                (253, 4, 0x86),
                (0, 4, 0x85),
                (1, 4, 0x85),
            ],
            records: [
                recordBytes(timestamp: 1_000_000_000, lat: 47.0, lon: 11.0, values: []),
            ]))
        var data = try FITCoder.write(fc)
        data[data.count - 1] ^= 0xFF

        do {
            _ = try FITCoder.read(from: data)
            Issue.record("Expected CRC verification to fail")
        }
        catch let error as FITError {
            guard case .parseError = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        let decoded = try FITCoder.read(from: data, options: FITReadOptions(verifyCRC: false))
        #expect(decoded.features.isEmpty == false)
    }

    @Test
    func fileReadAndWriteErrorsAreWrapped() throws {
        do {
            _ = try FITCoder.read(from: URL(fileURLWithPath: "/nonexistent/activity.fit"))
            Issue.record("Expected a read error")
        }
        catch let error as FITError {
            guard case .fileReadError = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        let fc = try FITCoder.read(from: makeRecordFile(
            fields: [
                (253, 4, 0x86),
                (0, 4, 0x85),
                (1, 4, 0x85),
            ],
            records: [
                recordBytes(timestamp: 1_000_000_000, lat: 47.0, lon: 11.0, values: []),
            ]))
        do {
            try fc.writeFIT(to: URL(fileURLWithPath: "/nonexistent/directory/activity.fit"))
            Issue.record("Expected a write error")
        }
        catch let error as FITError {
            guard case .fileWriteError = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        #expect(FeatureCollection(fitData: Data()) == nil)
    }

    // MARK: - Helpers

    private func sampleData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "fit", subdirectory: "TestData") else {
            throw TestError.missingResource
        }
        return try Data(contentsOf: url)
    }

    private enum TestError: Error {
        case missingResource
    }

    /// Builds a FIT file containing a single record definition and records.
    private func makeRecordFile(
        fields: [(num: UInt8, size: UInt8, baseType: UInt8)],
        records: [Data]
    ) -> Data {
        var body = Data()
        body.append(FITTestBuilder.definition(local: 0, global: 20, fields: fields))
        for record in records {
            body.append(FITTestBuilder.dataHeader(local: 0))
            body.append(record)
        }
        return FITTestBuilder.file(body: body)
    }

    /// Encodes a record message body. Timestamp, position and any additional
    /// values must be supplied in definition order.
    private func recordBytes(
        timestamp: UInt32,
        lat: Double,
        lon: Double,
        values: [Data]
    ) -> Data {
        var data = Data()
        data.append(FITTestBuilder.le32(timestamp))
        data.append(FITTestBuilder.sint32(FITTestBuilder.semicircles(lat)))
        data.append(FITTestBuilder.sint32(FITTestBuilder.semicircles(lon)))
        for value in values {
            data.append(value)
        }
        return data
    }

    private func makeDeviceInfoFile() -> Data {
        var body = Data()
        body.append(FITTestBuilder.definition(
            local: 0,
            global: 0,
            fields: [
                (0, 1, 0x00),
                (1, 2, 0x84),
                (3, 4, 0x8C),
            ]))
        body.append(FITTestBuilder.dataHeader(local: 0))
        body.append(4)  // activity
        body.append(FITTestBuilder.le16(1))  // garmin
        body.append(FITTestBuilder.le32(123))

        body.append(FITTestBuilder.definition(
            local: 1,
            global: 20,
            fields: [
                (253, 4, 0x86),
                (0, 4, 0x85),
                (1, 4, 0x85),
            ]))
        body.append(FITTestBuilder.dataHeader(local: 1))
        body.append(recordBytes(timestamp: 1_000_000_000, lat: 47.0, lon: 11.0, values: []))

        body.append(FITTestBuilder.definition(
            local: 2,
            global: 23,
            fields: [
                (0, 1, 0x02),   // device_index
                (2, 2, 0x84),   // manufacturer
                (19, 8, 0x07),  // descriptor
            ]))
        body.append(deviceInfo(index: 0, descriptor: "Primary"))
        body.append(deviceInfo(index: 1, descriptor: "Sensor"))

        return FITTestBuilder.file(body: body)
    }

    private func deviceInfo(index: UInt8, descriptor: String) -> Data {
        var data = Data()
        data.append(FITTestBuilder.dataHeader(local: 2))
        data.append(index)
        data.append(FITTestBuilder.le16(1))
        var name = Data(descriptor.utf8)
        name.append(0)
        while name.count < 8 { name.append(0) }
        data.append(name.prefix(8))
        return data
    }

    private func makeSessionFile() -> Data {
        var body = Data()
        body.append(FITTestBuilder.definition(
            local: 0,
            global: 18,
            fields: [
                (254, 2, 0x84),  // message_index
                (5, 1, 0x00),    // sport
                (9, 4, 0x86),    // total_distance
                (253, 4, 0x86),  // timestamp
            ]))
        body.append(session(index: 0, sport: 1, distance: 5_000))
        body.append(session(index: 1, sport: 2, distance: 10_000))

        body.append(FITTestBuilder.definition(
            local: 1,
            global: 20,
            fields: [
                (253, 4, 0x86),
                (0, 4, 0x85),
                (1, 4, 0x85),
            ]))
        body.append(FITTestBuilder.dataHeader(local: 1))
        body.append(recordBytes(timestamp: 1_000_000_000, lat: 47.0, lon: 11.0, values: []))

        return FITTestBuilder.file(body: body)
    }

    private func session(index: UInt16, sport: UInt8, distance: UInt32) -> Data {
        var data = Data()
        data.append(FITTestBuilder.dataHeader(local: 0))
        data.append(FITTestBuilder.le16(index))
        data.append(sport)
        data.append(FITTestBuilder.le32(distance))
        data.append(FITTestBuilder.le32(1_000_000_000))
        return data
    }

}
