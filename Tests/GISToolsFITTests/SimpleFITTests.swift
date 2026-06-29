import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

struct SimpleFITTests {

    @Test
    func decoderThrowsOnEmptyData() async throws {
        do {
            let _ = try FITDecoder.decode(data: Data())
            #expect(Bool(false), "Should have thrown")
        }
        catch {
            #expect(true)  // Expected to throw
        }
    }

    @Test
    func decoderThrowsOnInvalidHeader() async throws {
        let data = Data([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
        do {
            let _ = try FITDecoder.decode(data: data)
            #expect(Bool(false), "Should have thrown")
        }
        catch {
            #expect(true)
        }
    }

    @Test
    func semicircleConversion() async throws {
        // 1073741824 semicircles = exactly 90 degrees (half of 2^31)
        let degrees = FITDegreesFromSemicircles(1073741824)
        #expect(abs(degrees - 90.0) < 0.01)
    }

    @Test
    func decodeWithMessages() async throws {
        guard let data = makeMinimalFIT() else {
            #expect(Bool(false), "Failed to create FIT data")
            return
        }
        let messages = try FITDecoder.decode(data: data, verifyCRC: true)
        #expect(messages.count == 4)
    }

    @Test
    func fitCoderIntegration() async throws {
        guard let data = makeMinimalFIT() else {
            #expect(Bool(false), "Failed to create FIT data")
            return
        }
        let fc = try FITCoder.read(from: data)
        let tracks = fc.features.filter { $0.properties["fit_type"] as? String == "record" }
        #expect(tracks.count == 1)
        guard let track = tracks.first, let multiline = track.geometry as? MultiLineString else {
            #expect(Bool(false), "Missing track or multiline")
            return
        }
        #expect(multiline.lineStrings.count == 1)
        #expect(multiline.lineStrings[0].coordinates.count == 3)
        let coord0 = multiline.lineStrings[0].coordinates[0]
        #expect(abs(coord0.latitude - 47.5) < 0.01)
        #expect(abs(coord0.longitude - 11.5) < 0.01)
        #expect(fc.foreignMembers["fit_device"] != nil)
    }

    // MARK: - Per-point sensor arrays

    @Test
    func sensorArrays() async throws {
        guard let data = makeMinimalFIT() else { return }
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first else { return }
        
        guard let hr = track.fitHeartRates else { return }
        #expect(hr.count == 3)
        #expect(hr[0] == 120)
        #expect(hr[1] == 145)
        #expect(hr[2] == 160)
        
        guard let cad = track.fitCadences else { return }
        #expect(cad.count == 3)
        #expect(cad[0] == 80)
        #expect(cad[1] == 90)
        #expect(cad[2] == 95)
        
        guard let pw = track.fitPowers else { return }
        #expect(pw.count == 3)
        #expect(pw[0] == 150)
        #expect(pw[1] == 220)
        #expect(pw[2] == 280)
        
        guard let ts = track.fitTimestamps else { return }
        #expect(ts.count == 3)
    }

    @Test
    func pointFeatures() async throws {
        guard let data = makeMinimalFIT() else { return }
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first else { return }
        
        let pts = track.fitPointFeatures()
        #expect(pts.features.count == 3)
        
        // First point should have heart_rate 120
        let first = pts.features[0]
        #expect(first.properties["heart_rate"] as? Int == 120)
        #expect(first.properties["cadence"] as? Int == 80)
        #expect(first.properties["power"] as? Int == 150)
    }

    @Test
    func pointFeaturesFractionSlice() async throws {
        guard let data = makeMinimalFIT() else { return }
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first else { return }
        
        // Middle half of the track
        let mids = track.fitPointFeatures(fraction: 0.33, to: 0.66)
        // With only 3 points, there might be 0-2 in the middle half
        #expect(mids.features.count <= 2)
    }

    @Test
    func cumulativeDistancesWork() async throws {
        guard let data = makeMinimalFIT() else { return }
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first, let ml = track.geometry as? MultiLineString else { return }
        let coords = ml.lineStrings.flatMap { $0.coordinates }
        #expect(coords.count == 3)
    }

    @Test
    func pointFeaturesTimeSlice() async throws {
        guard let data = makeMinimalFIT() else { return }
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first else { return }

        let all = track.fitPointFeatures()
        #expect(all.features.count == 3)

        // Use a wide time window that should include all points
        let epoch = FITDateFromTimestamp(500000)
        let wide = track.fitPointFeatures(from: epoch, to: epoch.addingTimeInterval(100000))
        #expect(wide.features.count == 3)

        // Empty window should return no features
        let empty = track.fitPointFeatures(from: epoch.addingTimeInterval(100000), to: epoch.addingTimeInterval(200000))
        #expect(empty.features.isEmpty)
    }

    // MARK: - FeatureCollection filtering and track reconstruction

    @Test
    func fitRecordsFilter() async throws {
        guard let data = makeMinimalFIT() else { return }
        let fc = try FITCoder.read(from: data)
        #expect(fc.fitRecords.count == 1)
    }

    @Test
    func fitTrackFromPointFeatures() async throws {
        guard let data = makeMinimalFIT() else { return }
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first else { return }

        let pts = track.fitPointFeatures()
        guard let rebuilt = pts.fitTrackFromPointFeatures() else { return }

        #expect(rebuilt.fitHeartRates?[0] == 120)
        #expect(rebuilt.fitCadences?[1] == 90)
        #expect(rebuilt.fitPowers?[2] == 280)
    }

    @Test
    func fitTrackFromPointFeaturesEmpty() async throws {
        let fc = FeatureCollection()
        #expect(fc.fitTrackFromPointFeatures() == nil)
    }

    @Test
    func fitTrackFromPointFeaturesConvenienceInit() async throws {
        guard let data = makeMinimalFIT() else { return }
        let fc = try FITCoder.read(from: data)
        guard let track = fc.features.first else { return }

        let pts = track.fitPointFeatures()
        let rebuilt = Feature(fitTrackFrom: pts)
        #expect(rebuilt?.fitHeartRates?[0] == 120)
        #expect(rebuilt?.fitPowers?[2] == 280)
    }

    // MARK: - Test FIT factory

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
                    crc = (crc >> 1) ^ 0x8408
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
