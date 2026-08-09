import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

/// Tests for indoor/trainer FIT files that contain per-record sensor data
/// but no GPS positions. The track is emitted as an empty `MultiLineString`
/// while per-point sensor arrays (heart rate, cadence, power, speed,
/// altitude, timestamps) are preserved, allowing these activities to round
/// trip through the encoder without losing data.
struct IndoorActivityTests {

    // MARK: - Sensor data is preserved without GPS

    @Test
    func indoorFileProducesRecordFeatureWithSensorData() async throws {
        guard let data = makeGPSlessFIT() else {
            Issue.record("Failed to create GPSless FIT")
            return
        }
        let fc = try FITCoder.read(from: data)

        // One record Feature should exist even though the activity has no GPS.
        let tracks = fc.features.filter { $0.properties["fit_type"] as? String == "record" }
        #expect(tracks.count == 1)
        guard let track = tracks.first, let ml = track.geometry as? MultiLineString else {
            Issue.record("Missing track or MultiLineString")
            return
        }

        // Empty MultiLineString — there are no coordinates to draw.
        #expect(ml.lineStrings.isEmpty)

        // Per-point sensor arrays should cover all three records.
        guard let hr = track.fitHeartRates else {
            Issue.record("Missing fit_heart_rates")
            return
        }
        #expect(hr.count == 3)
        #expect(hr[0] == 130)
        #expect(hr[1] == 145)
        #expect(hr[2] == 160)

        guard let cad = track.fitCadences else {
            Issue.record("Missing fit_cadences")
            return
        }
        #expect(cad == [85, 90, 95])

        guard let pw = track.fitPowers else {
            Issue.record("Missing fit_powers")
            return
        }
        #expect(pw == [180, 220, 280])

        guard let ts = track.fitTimestamps else {
            Issue.record("Missing fit_timestamps")
            return
        }
        #expect(ts.count == 3)
        // Round-trip dates back to the FIT epoch-relative seconds.
        #expect(ts[0] == FIT.dateFromTimestamp(2_100_000_100))
    }

    @Test
    func indoorFileRoundTripsThroughEncoder() async throws {
        guard let data = makeGPSlessFIT() else {
            Issue.record("Failed to create GPSless FIT")
            return
        }
        let fc1 = try FITCoder.read(from: data)
        let encoded = try FITCoder.write(from: fc1)
        let fc2 = try FITCoder.read(from: encoded)

        guard let track = fc2.features.first else {
            Issue.record("Round-tripped feature collection is empty")
            return
        }

        // Sensor arrays should survive the round trip.
        let hr = track.fitHeartRates ?? []
        #expect(hr.count == 3)
        #expect(hr[0] == 130)
        #expect(hr[1] == 145)
        #expect(hr[2] == 160)

        let cad = track.fitCadences ?? []
        #expect(cad == [85, 90, 95])

        let pw = track.fitPowers ?? []
        #expect(pw == [180, 220, 280])

        let ts = track.fitTimestamps ?? []
        #expect(ts.count == 3)
        #expect(ts[0] == FIT.dateFromTimestamp(2_100_000_100))
    }

    // MARK: - Helper

    /// Builds a minimal FIT activity file whose `record` messages contain
    /// heart rate, cadence, power and a timestamp but no GPS position.
    private func makeGPSlessFIT() -> Data? {
        var headerData = Data()
        var mesgData = Data()

        // Definition: file_id (local 0, global 0)
        mesgData.append(0x40)
        mesgData.append(0x00)
        mesgData.append(0x00)
        mesgData.append(contentsOf: le16(0))
        mesgData.append(2)
        mesgData.append(contentsOf: [0, 1, 0])    // type
        mesgData.append(contentsOf: [253, 4, 6])  // time_created

        // Data: file_id
        mesgData.append(0x00)
        mesgData.append(4)                         // type = activity
        mesgData.append(contentsOf: le32(UInt32(2_100_000_000)))  // time_created

        // Definition: record (local 1, global 20) — no position_lat/long
        mesgData.append(0x41)
        mesgData.append(0x00)
        mesgData.append(0x00)
        mesgData.append(contentsOf: le16(20))
        mesgData.append(4)
        mesgData.append(contentsOf: [3, 1, 2])    // heart_rate (uint8)
        mesgData.append(contentsOf: [4, 1, 2])    // cadence   (uint8)
        mesgData.append(contentsOf: [7, 2, 4])    // power     (uint16)
        mesgData.append(contentsOf: [253, 4, 6])  // timestamp (uint32)

        // Record 1: hr=130, cad=85, pw=180, ts=2_100_000_100
        mesgData.append(0x01)
        mesgData.append(130)
        mesgData.append(85)
        mesgData.append(contentsOf: le16(180))
        mesgData.append(contentsOf: le32(UInt32(2_100_000_100)))

        // Record 2: hr=145, cad=90, pw=220, ts=2_100_000_200
        mesgData.append(0x01)
        mesgData.append(145)
        mesgData.append(90)
        mesgData.append(contentsOf: le16(220))
        mesgData.append(contentsOf: le32(UInt32(2_100_000_200)))

        // Record 3: hr=160, cad=95, pw=280, ts=2_100_000_300
        mesgData.append(0x01)
        mesgData.append(160)
        mesgData.append(95)
        mesgData.append(contentsOf: le16(280))
        mesgData.append(contentsOf: le32(UInt32(2_100_000_300)))

        // 12-byte header
        headerData.append(12)
        headerData.append(0x20)
        headerData.append(contentsOf: le16(2100))
        headerData.append(contentsOf: le32(UInt32(mesgData.count)))
        headerData.append(contentsOf: [0x2E, 0x46, 0x49, 0x54])

        var fileData = Data()
        fileData.append(headerData)
        fileData.append(mesgData)

        let crc = crc16(fileData)
        fileData.append(contentsOf: le16(crc))

        return fileData
    }

    private func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if (crc & 0x0001) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                }
                else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    private func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private func le32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }
}