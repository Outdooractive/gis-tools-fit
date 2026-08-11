import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

/// Decodes the bundled `TestData/sample.fit` (generated with the Garmin FIT
/// Python SDK) and verifies that every value written into the file is decoded
/// back correctly by the library's clean-room decoder.
struct SampleFITDecodeTests {

    /// Loads the bundled sample FIT file.
    private func sampleData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "sample", withExtension: "fit", subdirectory: "TestData") else {
            throw TestError.missingResource
        }
        return try Data(contentsOf: url)
    }

    enum TestError: Error {
        case missingResource
    }

    // MARK: - Message counts

    @Test
    func decodesAllMessages() async throws {
        let data = try sampleData()
        let messages = try FITDecoder.decode(data: data, verifyCRC: true)

        let counts = Dictionary(grouping: messages, by: { $0.globalMessageNumber })
        #expect(counts[FITProfile.MesgNum.fileId.rawValue]?.count == 1)
        #expect(counts[FITProfile.MesgNum.activity.rawValue]?.count == 1)
        #expect(counts[FITProfile.MesgNum.session.rawValue]?.count == 1)
        #expect(counts[19]?.count == 3)  // lap (global 19)
        #expect(counts[FITProfile.MesgNum.record.rawValue]?.count == 30)
        #expect(counts[FITProfile.MesgNum.event.rawValue]?.count == 2)
        #expect(counts[FITProfile.MesgNum.deviceInfo.rawValue]?.count == 1)
    }

    // MARK: - File ID

    @Test
    func decodesFileId() async throws {
        let data = try sampleData()
        let messages = try FITDecoder.decode(data: data, verifyCRC: true)
        let fileId = try #require(messages.first { $0.globalMessageNumber == FITProfile.MesgNum.fileId.rawValue })

        // type = activity (4)
        #expect(fileId.fields[0] as? UInt8 == 4)
        // manufacturer = garmin (1)
        #expect(fileId.fields[1] as? UInt16 == 1)
        // serial_number = 0x0123456789ABCDEF truncated to uint32z
        #expect(fileId.fields[3] as? UInt32 == 0x89ABCDEF)
        // number = 1
        #expect(fileId.fields[5] as? UInt16 == 1)
        // product_name = "Garmin Forerunner 255"
        #expect(fileId.fields[8] as? String == "Garmin Forerunner 255")
    }

    // MARK: - Session

    @Test
    func decodesSession() async throws {
        let data = try sampleData()
        let messages = try FITDecoder.decode(data: data, verifyCRC: true)
        let session = try #require(messages.first { $0.globalMessageNumber == FITProfile.MesgNum.session.rawValue })

        // sport = running (1)
        #expect(session.fields[5] as? UInt8 == 1)
        // total_distance = 12000.0 m -> raw 1200000 (scale 100)
        #expect(session.fields[9] as? UInt32 == 1_200_000)
        // avg_heart_rate = 145
        #expect(session.fields[16] as? UInt8 == 145)
        // max_heart_rate = 175
        #expect(session.fields[17] as? UInt8 == 175)
        // total_calories = 800
        #expect(session.fields[11] as? UInt16 == 800)
        // num_laps = 3
        #expect(session.fields[26] as? UInt16 == 3)
    }

    // MARK: - Record

    @Test
    func decodesRecord() async throws {
        let data = try sampleData()
        let messages = try FITDecoder.decode(data: data, verifyCRC: true)
        let records = messages.filter { $0.globalMessageNumber == FITProfile.MesgNum.record.rawValue }
        #expect(records.count == 30)

        let first = try #require(records.first)
        // position_lat = 510000000
        #expect(first.fields[0] as? Int32 == 510_000_000)
        // position_long = 90000000
        #expect(first.fields[1] as? Int32 == 90_000_000)
        // altitude = 100.0 m -> raw 3000 (scale 5, offset 500)
        #expect(first.fields[2] as? UInt16 == 3000)
        // heart_rate = 140
        #expect(first.fields[3] as? UInt8 == 140)
        // cadence = 170
        #expect(first.fields[4] as? UInt8 == 170)
        // speed = 3.333 m/s -> raw 3333 (scale 1000)
        #expect(first.fields[6] as? UInt16 == 3333)
        // power = 250
        #expect(first.fields[7] as? UInt16 == 250)
        // temperature = 20 C
        #expect(first.fields[13] as? Int8 == 20)
        // enhanced_speed = 3.333 -> raw 3333
        #expect(first.fields[73] as? UInt32 == 3333)
        // enhanced_altitude = 100.0 -> raw 3000
        #expect(first.fields[78] as? UInt32 == 3000)
    }

    // MARK: - Device Info

    @Test
    func decodesDeviceInfo() async throws {
        let data = try sampleData()
        let messages = try FITDecoder.decode(data: data, verifyCRC: true)
        let device = try #require(messages.first { $0.globalMessageNumber == FITProfile.MesgNum.deviceInfo.rawValue })

        // device_index = 0
        #expect(device.fields[0] as? UInt8 == 0)
        // manufacturer = garmin (1)
        #expect(device.fields[2] as? UInt16 == 1)
        // software_version = 12.34 -> raw 1234 (scale 100)
        #expect(device.fields[5] as? UInt16 == 1234)
        // hardware_version = 1
        #expect(device.fields[6] as? UInt8 == 1)
        // battery_voltage = 4.1 V -> raw 1050 (scale 256)
        #expect(device.fields[10] as? UInt16 == 1050)
        // battery_status = good (2)
        #expect(device.fields[11] as? UInt8 == 2)
        // sensor_position = left_leg (0)
        #expect(device.fields[18] as? UInt8 == 0)
        // descriptor = "Forerunner 255"
        #expect(device.fields[19] as? String == "Forerunner 255")
        // product_name = "Garmin Forerunner 255"
        #expect(device.fields[27] as? String == "Garmin Forerunner 255")
    }

    // MARK: - FITCoder integration

    @Test
    func fitCoderReadsSample() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)

        let tracks = fc.features.filter { $0.properties["fit_type"] as? String == "record" }
        #expect(tracks.count == 1)
        guard let track = tracks.first else {
            #expect(Bool(false), "Missing record track")
            return
        }

        // 30 GPS-bearing records -> 30 coordinates
        let multiline = try #require(track.geometry as? MultiLineString)
        let coords = multiline.lineStrings.flatMap { $0.coordinates }
        #expect(coords.count == 30)

        // First point: lat 510000000 semicircles, lon 90000000 semicircles
        let first = try #require(coords.first)
        #expect(abs(first.latitude - FIT.degreesFromSemicircles(510_000_000)) < 0.0001)
        #expect(abs(first.longitude - FIT.degreesFromSemicircles(90_000_000)) < 0.0001)
        // altitude 100.0 m
        #expect(abs((first.altitude ?? 0) - 100.0) < 0.01)

        // Sensor arrays
        #expect(track.fitHeartRates?.first == 140)
        #expect(track.fitCadences?.first == 170)
        #expect(track.fitPowers?.first == 250)
        if let speed = track.fitSpeeds?.first ?? nil {
            #expect(abs(speed - 3.333) < 0.001)
        } else {
            #expect(Bool(false), "Missing speed")
        }
        if let temp = track.fitTemperatures?.first ?? nil {
            #expect(abs(temp - 20.0) < 0.001)
        } else {
            #expect(Bool(false), "Missing temperature")
        }
    }

    // MARK: - Session metadata mapping

    @Test
    func sessionMetadataMappedToTrack() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first(where: { $0.fitType == .record }) else {
            #expect(Bool(false), "Missing record track")
            return
        }

        // sport = running (1)
        #expect(track.properties["sport"] as? Int64 == 1)
        // total_distance = 12000.0 m
        #expect(track.properties["total_distance"] as? Double == 12000.0)
        // avg_heart_rate = 145
        #expect(track.properties["avg_heart_rate"] as? Int64 == 145)
        // num_laps = 3
        #expect(track.properties["num_laps"] as? Int64 == 3)
        // total_calories = 800
        #expect(track.properties["total_calories"] as? Int64 == 800)
    }

    @Test
    func fitSportFromSession() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)
        #expect(fc.fitSport == "running")  // sport = running (1)
    }

    // MARK: - Complete projection

    @Test
    func lapsAreEmittedAsFeatures() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)
        let laps = fc.features.filter { $0.fitType == .lap }
        #expect(laps.count == 3)
        // Each lap carries its metadata.
        #expect(laps[0].properties["total_distance"] != nil)
        #expect(laps[0].properties["avg_heart_rate"] != nil)
    }

    @Test
    func eventsAreEmittedAsFeatures() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)
        let events = fc.features.filter { $0.fitType == .event }
        #expect(events.count == 2)
        // First event: timer start.
        #expect(events[0].properties["event"] as? Int64 == 0)  // timer
        #expect(events[0].properties["event_type"] as? Int64 == 0)  // start
    }

    @Test
    func deviceInfoIsFullyWritten() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)
        let device = fc.fitDevice ?? [:]
        // device_info fields are now present (previously dropped).
        #expect(device["manufacturer"] != nil)
        #expect(device["serial_number"] != nil)
        #expect(device["software_version"] != nil)
        #expect(device["battery_voltage"] != nil)
        #expect(device["battery_status"] != nil)
        #expect(device["sensor_position"] != nil)
        #expect(device["descriptor"] as? String == "Forerunner 255")
        #expect(device["product_name"] as? String == "Garmin Forerunner 255")
    }

    @Test
    func fileIdIsFullyWritten() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)
        let device = fc.fitDevice ?? [:]
        #expect(device["type"] != nil)
        #expect(device["manufacturer"] != nil)
        #expect(device["serial_number"] != nil)
        #expect(device["time_created"] != nil)
        #expect(device["number"] != nil)
        #expect(device["product_name"] as? String == "Garmin Forerunner 255")
    }

    @Test
    func sessionFieldsAreFullyWritten() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first(where: { $0.fitType == .record }) else {
            #expect(Bool(false), "Missing record track")
            return
        }
        // A broad set of session fields should be present on the track.
        #expect(track.properties["sport"] != nil)
        #expect(track.properties["total_distance"] != nil)
        #expect(track.properties["avg_heart_rate"] != nil)
        #expect(track.properties["max_heart_rate"] != nil)
        #expect(track.properties["total_calories"] != nil)
        #expect(track.properties["total_ascent"] != nil)
        #expect(track.properties["total_descent"] != nil)
        #expect(track.properties["avg_power"] != nil)
        #expect(track.properties["max_power"] != nil)
        #expect(track.properties["avg_speed"] != nil)
        #expect(track.properties["max_speed"] != nil)
        #expect(track.properties["avg_cadence"] != nil)
        #expect(track.properties["num_laps"] != nil)
        #expect(track.properties["total_training_effect"] != nil)
        #expect(track.properties["training_stress_score"] != nil)
        #expect(track.properties["intensity_factor"] != nil)
        #expect(track.properties["normalized_power"] != nil)
        #expect(track.properties["avg_altitude"] != nil)
        #expect(track.properties["max_altitude"] != nil)
        #expect(track.properties["min_altitude"] != nil)
        #expect(track.properties["avg_grade"] != nil)
        #expect(track.properties["avg_temperature"] != nil)
        #expect(track.properties["max_temperature"] != nil)
        #expect(track.properties["total_moving_time"] != nil)
        #expect(track.properties["min_heart_rate"] != nil)
        #expect(track.properties["avg_spo2"] != nil)
        #expect(track.properties["avg_stress"] != nil)
        #expect(track.properties["metabolic_calories"] != nil)
        #expect(track.properties["sdrr_hrv"] != nil)
        #expect(track.properties["rmssd_hrv"] != nil)
        #expect(track.properties["avg_core_temperature"] != nil)
    }

    @Test
    func roundTripPreservesMessageCounts() async throws {
        let original = try sampleData()
        let fc = try FITCoder.read(from: original)
        let reencoded = try FITCoder.write(from: fc)

        let redecoded = try FITDecoder.decode(data: reencoded, verifyCRC: true)
        let originalMessages = try FITDecoder.decode(data: original, verifyCRC: true)

        // Same total message count.
        #expect(redecoded.count == originalMessages.count)

        // Same per-type counts.
        func count(_ msgs: [FITDecoder.RawMessage], _ num: UInt16) -> Int {
            msgs.filter { $0.globalMessageNumber == num }.count
        }
        #expect(count(redecoded, 0) == count(originalMessages, 0))  // file_id
        #expect(count(redecoded, 34) == count(originalMessages, 34))  // activity
        #expect(count(redecoded, 18) == count(originalMessages, 18))  // session
        #expect(count(redecoded, 19) == count(originalMessages, 19))  // lap
        #expect(count(redecoded, 20) == count(originalMessages, 20))  // record
        #expect(count(redecoded, 21) == count(originalMessages, 21))  // event
        #expect(count(redecoded, 23) == count(originalMessages, 23))  // device_info
    }

    // MARK: - Enum name mapping

    @Test
    func enumNamesAreMapped() async throws {
        let data = try sampleData()
        let fc = try FITCoder.read(from: data)

        // Direct lookup.
        #expect(FIT.name(for: "event", value: 9) == "lap")
        #expect(FIT.name(for: "event_type", value: 1) == "stop")
        #expect(FIT.name(for: "sport", value: 1) == "running")
        #expect(FIT.name(for: "event", value: 999) == nil)

        // Via a Feature's properties.
        let event = try #require(fc.features.first { $0.fitType == .event })
        #expect(event.fitEnumName(for: "event") == "timer")
        #expect(event.fitEnumName(for: "event_type") == "start")

        let lap = try #require(fc.features.first { $0.fitType == .lap })
        #expect(lap.fitEnumName(for: "sport") == "running")
    }

    @Test
    func enumNameFieldAliasesResolve() async throws {
        // Field names that differ from their enum type name resolve correctly.
        #expect(FIT.name(for: "trigger", value: 0) == "activity_end")
        #expect(FIT.name(for: "pool_length_unit", value: 0) == "metric")
        #expect(FIT.name(for: "sensor_position", value: 0) == "left_leg")
        #expect(FIT.name(for: "radar_threat_level_max", value: 1) == "threat_none")
        #expect(FIT.name(for: "type", value: 4) == "activity")
    }

    @Test
    func manufacturerNamesAreMapped() async throws {
        #expect(FIT.name(for: "manufacturer", value: 1) == "garmin")
        #expect(FIT.name(for: "manufacturer", value: 15) == "dynastream")
        #expect(FIT.name(for: "manufacturer", value: 32) == "wahoo_fitness")
        #expect(FIT.name(for: "manufacturer", value: 95) == "stryd")
        #expect(FIT.name(for: "manufacturer", value: 9999) == nil)
    }
}
