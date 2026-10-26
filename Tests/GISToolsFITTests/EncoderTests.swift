import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

/// Tests for FIT writing / encoding (``FITCoder/write(from:)``).
struct EncoderTests {

    // MARK: - Round-trip read → write → read

    @Test
    func roundTripMinimalFIT() async throws {
        guard let original = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        // Decode the original file
        let fc1 = try FITCoder.read(from: original)

        // Encode it back to binary
        let encoded = try FITCoder.write(fc1)

        // Decode the encoded data
        let fc2 = try FITCoder.read(from: encoded)

        // The track should have the same coordinates
        guard let track1 = fc1.features.first(where: { $0.fitType == .record }),
              let track2 = fc2.features.first(where: { $0.fitType == .record })
        else {
            Issue.record("Missing track feature")
            return
        }

        guard let ml1 = track1.geometry as? MultiLineString,
              let ml2 = track2.geometry as? MultiLineString
        else {
            Issue.record("Missing MultiLineString")
            return
        }

        #expect(ml1.lineStrings.count == ml2.lineStrings.count)
        #expect(ml1.lineStrings[0].coordinates.count == ml2.lineStrings[0].coordinates.count)

        let coords1 = ml1.lineStrings[0].coordinates
        let coords2 = ml2.lineStrings[0].coordinates
        for i in 0..<coords1.count {
            #expect(abs(coords1[i].latitude - coords2[i].latitude) < 0.001)
            #expect(abs(coords1[i].longitude - coords2[i].longitude) < 0.001)
        }
    }

    @Test
    func roundTripSensorData() async throws {
        guard let original = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        let fc1 = try FITCoder.read(from: original)
        guard let track1 = fc1.features.first else {
            Issue.record("Missing track")
            return
        }

        let encoded = try FITCoder.write(fc1)
        let fc2 = try FITCoder.read(from: encoded)
        guard let track2 = fc2.features.first else {
            Issue.record("Missing encoded track")
            return
        }

        // Heart rates should match
        let hr1 = track1.fitHeartRates ?? []
        let hr2 = track2.fitHeartRates ?? []
        #expect(hr1.count == hr2.count)
        #expect(hr2[0] == 120)
        #expect(hr2[1] == 145)
        #expect(hr2[2] == 160)

        // Cadences
        let cad1 = track1.fitCadences ?? []
        let cad2 = track2.fitCadences ?? []
        #expect(cad1.count == cad2.count)
        #expect(cad2[0] == 80)
        #expect(cad2[1] == 90)
        #expect(cad2[2] == 95)

        // Powers
        let pw1 = track1.fitPowers ?? []
        let pw2 = track2.fitPowers ?? []
        #expect(pw1.count == pw2.count)
        #expect(pw2[0] == 150)
        #expect(pw2[1] == 220)
        #expect(pw2[2] == 280)

        // Timestamps
        let ts1 = track1.fitTimestamps ?? []
        let ts2 = track2.fitTimestamps ?? []
        #expect(ts1.count == ts2.count)
    }

    @Test
    func roundTripDeviceMetadata() async throws {
        guard let original = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        let fc1 = try FITCoder.read(from: original)
        let encoded = try FITCoder.write(fc1)
        let fc2 = try FITCoder.read(from: encoded)

        // Device metadata should be preserved
        #expect(fc2.fitDevice != nil)
        let device1 = fc1.fitDevice ?? [:]
        let device2 = fc2.fitDevice ?? [:]
        #expect(device2["manufacturer"] as? Int == device1["manufacturer"] as? Int)
    }

    // MARK: - CRC validation of encoded files

    @Test
    func encodedFilePassesCRCValidation() async throws {
        guard let original = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        let fc = try FITCoder.read(from: original)
        let encoded = try FITCoder.write(fc)

        // Decode with CRC validation enabled — should not throw
        let messages = try FITDecoder.decode(data: encoded, verifyCRC: true)
        #expect(messages.count > 0)
    }

    @Test
    func encodedFileHasValidHeader() async throws {
        guard let original = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        let fc = try FITCoder.read(from: original)
        let encoded = try FITCoder.write(fc)

        // Verify ".FIT" magic
        #expect(encoded[8] == 0x2E)  // .
        #expect(encoded[9] == 0x46)  // F
        #expect(encoded[10] == 0x49) // I
        #expect(encoded[11] == 0x54) // T

        // Data size (bytes 4-7) should match actual mesg data
        let dataSize = UInt32(encoded[4])
            | (UInt32(encoded[5]) << 8)
            | (UInt32(encoded[6]) << 16)
            | (UInt32(encoded[7]) << 24)
        let expectedDataSize = UInt32(encoded.count - 12 - 2)  // header (12) + CRC (2)
        #expect(dataSize == expectedDataSize)
    }

    // MARK: - Empty and error cases

    @Test
    func writeThrowsOnEmptyCollection() async throws {
        let fc = FeatureCollection()
        #expect(throws: FITError.self) {
            try FITCoder.write(fc)
        }
    }

    @Test
    func writeThrowsOnMissingRecordFeature() async throws {
        // A FeatureCollection with a non-record feature
        let point = Point(Coordinate3D(latitude: 47.0, longitude: 11.0))
        let fc = FeatureCollection([Feature(point)])
        #expect(throws: FITError.self) {
            try FITCoder.write(fc)
        }
    }

    // MARK: - Point features round-trip

    @Test
    func roundTripPointFeatures() async throws {
        guard let original = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        let fc = try FITCoder.read(from: original)
        guard let track = fc.features.first else { return }

        let pts = track.fitPointFeatures()
        #expect(pts.features.count == 3)

        // Reconstruct a track from points and encode it
        guard let rebuilt = pts.fitTrackFromPointFeatures() else {
            Issue.record("Failed to rebuild track")
            return
        }

        let newFC = FeatureCollection([rebuilt])
        let encoded = try FITCoder.write(newFC)
        let fc2 = try FITCoder.read(from: encoded)

        guard let track2 = fc2.features.first else {
            Issue.record("Missing track in encoded data")
            return
        }

        #expect(track2.fitHeartRates?[0] == 120)
        #expect(track2.fitPowers?[2] == 280)
        #expect(track2.fitCadences?[1] == 90)
    }

    // MARK: - FITEncoder direct tests

    @Test
    func encoderProducesValidEmptyFile() async throws {
        let data = try FITEncoder.encode(messages: [])
        // Header (12) + CRC (2) = 14
        #expect(data.count == 14)
        // ".FIT" magic
        #expect(data[8] == 0x2E)
        #expect(data[9] == 0x46)
        #expect(data[10] == 0x49)
        #expect(data[11] == 0x54)
        // Data size should be 0
        #expect(data[4] == 0)
        #expect(data[5] == 0)
        #expect(data[6] == 0)
        #expect(data[7] == 0)
    }

    @Test
    func encoderWithHeaderCRC() async throws {
        let data = try FITEncoder.encode(messages: [], includeHeaderCRC: true)
        // Header (14) + CRC (2) = 16
        #expect(data.count == 16)
        // Header size byte
        #expect(data[0] == 14)
        // Validate header CRC
        let headerCrc = FITEncoder.crc16(data.prefix(12))
        let storedCrc = UInt16(data[12]) | (UInt16(data[13]) << 8)
        #expect(headerCrc == storedCrc)
    }

    // MARK: - Semicircle conversion

    @Test
    func semicircleRoundTrip() async throws {
        let lat = 47.5
        let lon = 11.5
        let semisLat = FIT.semicirclesFromDegrees(lat)
        let semisLon = FIT.semicirclesFromDegrees(lon)
        let backLat = FIT.degreesFromSemicircles(semisLat)
        let backLon = FIT.degreesFromSemicircles(semisLon)
        #expect(abs(backLat - lat) < 0.001)
        #expect(abs(backLon - lon) < 0.001)
    }

    // MARK: - Helpers

    /// Creates a minimal valid FIT file.
    private func makeMinimalFIT() -> Data? {
        var headerData = Data()
        var mesgData = Data()

        // --- Definition: file_id (local mesg 0, global mesg 0) ---
        mesgData.append(0x40)               // header: definition, local 0
        mesgData.append(0x00)               // reserved
        mesgData.append(0x00)               // architecture (little-endian)
        mesgData.append(contentsOf: le16(0)) // global: file_id
        mesgData.append(5)                  // number of fields
        mesgData.append(contentsOf: [0, 1, 0])    // type     (num=0, size=1, type=enum)
        mesgData.append(contentsOf: [1, 2, 4])    // manuf    (num=1, size=2, type=uint16)
        mesgData.append(contentsOf: [2, 2, 4])    // product  (num=2, size=2, type=uint16)
        mesgData.append(contentsOf: [3, 4, 12])   // serial   (num=3, size=4, type=uint32z)
        mesgData.append(contentsOf: [253, 4, 6])  // time     (num=253, size=4, type=uint32)

        // --- Data: file_id ---
        mesgData.append(0x00)               // header: data, local 0
        mesgData.append(4)                  // type = activity
        mesgData.append(contentsOf: le16(1)) // manufacturer = garmin
        mesgData.append(contentsOf: le16(0)) // product
        mesgData.append(contentsOf: le32(UInt32(0))) // serial_number
        mesgData.append(contentsOf: le32(UInt32(500000))) // time_created

        // --- Definition: record (local mesg 1, global mesg 20) ---
        mesgData.append(0x41)               // header: definition, local 1
        mesgData.append(0x00)               // reserved
        mesgData.append(0x00)               // architecture
        mesgData.append(contentsOf: le16(20)) // global: record
        mesgData.append(6)                  // number of fields
        mesgData.append(contentsOf: [0, 4, 5])    // position_lat  (num=0, size=4, type=sint32)
        mesgData.append(contentsOf: [1, 4, 5])    // position_long (num=1, size=4, type=sint32)
        mesgData.append(contentsOf: [3, 1, 2])    // heart_rate    (num=3, size=1, type=uint8)
        mesgData.append(contentsOf: [4, 1, 2])    // cadence       (num=4, size=1, type=uint8)
        mesgData.append(contentsOf: [7, 2, 4])    // power         (num=7, size=2, type=uint16)
        mesgData.append(contentsOf: [253, 4, 6])  // timestamp     (num=253, size=4, type=uint32)

        // --- Data: record 1 (47.5, 11.5, HR=120, cad=80, power=150, ts=500100) ---
        mesgData.append(0x01)
        mesgData.append(contentsOf: le32(semicircles(47.5)))
        mesgData.append(contentsOf: le32(semicircles(11.5)))
        mesgData.append(120)                     // heart_rate
        mesgData.append(80)                      // cadence
        mesgData.append(contentsOf: le16(150))   // power
        mesgData.append(contentsOf: le32(UInt32(500100))) // timestamp

        // --- Data: record 2 (48.0, 12.0, HR=145, cad=90, power=220, ts=500200) ---
        mesgData.append(0x01)
        mesgData.append(contentsOf: le32(semicircles(48.0)))
        mesgData.append(contentsOf: le32(semicircles(12.0)))
        mesgData.append(145)                     // heart_rate
        mesgData.append(90)                      // cadence
        mesgData.append(contentsOf: le16(220))   // power
        mesgData.append(contentsOf: le32(UInt32(500200))) // timestamp

        // --- Data: record 3 (49.0, 13.0, HR=160, cad=95, power=280, ts=500300) ---
        mesgData.append(0x01)
        mesgData.append(contentsOf: le32(semicircles(49.0)))
        mesgData.append(contentsOf: le32(semicircles(13.0)))
        mesgData.append(160)                     // heart_rate
        mesgData.append(95)                      // cadence
        mesgData.append(contentsOf: le16(280))   // power
        mesgData.append(contentsOf: le32(UInt32(500300))) // timestamp

        // --- Header ---
        headerData.append(12)
        headerData.append(0x20)
        headerData.append(contentsOf: le16(2100))
        headerData.append(contentsOf: le32(UInt32(mesgData.count)))
        headerData.append(contentsOf: [0x2E, 0x46, 0x49, 0x54])

        // --- Assemble ---
        var fileData = Data()
        fileData.append(headerData)
        fileData.append(mesgData)

        // --- CRC ---
        let crc = crc16(fileData)
        fileData.append(contentsOf: le16(crc))

        return fileData
    }

    private func semicircles(_ degrees: Double) -> Int32 {
        Int32(degrees / (180.0 / 2147483648.0))
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

    private func le32(_ value: Int32) -> [UInt8] {
        let u = UInt32(bitPattern: value)
        return [UInt8(u & 0xFF), UInt8((u >> 8) & 0xFF),
                UInt8((u >> 16) & 0xFF), UInt8((u >> 24) & 0xFF)]
    }

}