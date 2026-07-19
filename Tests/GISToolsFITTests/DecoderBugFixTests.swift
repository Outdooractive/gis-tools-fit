import Foundation
import Testing
@testable import GISTools
@testable import GISToolsFIT

/// Tests for FIT decoder bug fixes:
/// - Developer field data in data messages
/// - Compressed timestamp message local message number extraction
/// - CRC-16/ARC (Dynastream CRC) algorithm
struct DecoderBugFixTests {

    // MARK: - Developer fields

    /// A definition with developer fields must include those field sizes in each
    /// subsequent data message. If the decoder doesn't read the dev field data,
    /// byte alignment is lost and all following messages are corrupted.
    @Test
    func developerFieldsAreReadInDataMessages() async throws {
        var headerData = Data()
        var mesgData = Data()

        // Definition: file_id (local 0, global 0), no dev fields
        mesgData.append(0x40)               // header: definition, local 0, no dev data
        mesgData.append(0x00)               // reserved
        mesgData.append(0x00)               // architecture (LE)
        mesgData.append(contentsOf: le16(0)) // global: file_id
        mesgData.append(1)                  // 1 field
        mesgData.append(contentsOf: [0, 1, 0])  // type (num=0, size=1, baseType=enum)

        // Data: file_id
        mesgData.append(0x00)               // data header, local 0
        mesgData.append(4)                  // type = activity

        // Definition: record (local 1, global 20) WITH developer fields
        mesgData.append(0x61)               // header: definition, local 1, has dev data (0x20 | 0x01)
        mesgData.append(0x00)               // reserved
        mesgData.append(0x00)               // architecture (LE)
        mesgData.append(contentsOf: le16(20)) // global: record
        mesgData.append(2)                  // 2 regular fields
        mesgData.append(contentsOf: [0, 4, 5])   // position_lat (num=0, size=4, sint32)
        mesgData.append(contentsOf: [1, 4, 5])   // position_long (num=1, size=4, sint32)
        // Developer fields
        mesgData.append(1)                  // 1 dev field
        mesgData.append(contentsOf: [200, 8, 0]) // dev field: num=200, size=8, devDataIndex=0

        // Data: record 1 — regular fields (8 bytes) + dev field (8 bytes) = 16 bytes total
        mesgData.append(0x01)               // data header, local 1
        mesgData.append(contentsOf: le32(semicircles(47.5)))  // lat
        mesgData.append(contentsOf: le32(semicircles(11.5)))  // lon
        mesgData.append(contentsOf: [0xAB, 0xCD, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC]) // 8 bytes dev data

        // Data: record 2 — must be correctly aligned
        mesgData.append(0x01)               // data header, local 1
        mesgData.append(contentsOf: le32(semicircles(48.0)))  // lat
        mesgData.append(contentsOf: le32(semicircles(12.0)))  // lon
        mesgData.append(contentsOf: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]) // 8 bytes dev data

        // Assemble header
        headerData.append(12)               // header size
        headerData.append(0x20)             // protocol version
        headerData.append(contentsOf: le16(2100)) // profile version
        headerData.append(contentsOf: le32(UInt32(mesgData.count))) // data size
        headerData.append(contentsOf: [0x2E, 0x46, 0x49, 0x54]) // ".FIT"

        var fileData = Data()
        fileData.append(headerData)
        fileData.append(mesgData)

        let crc = crc16(fileData)
        fileData.append(contentsOf: le16(crc))

        // Decode — should succeed without "truncated" or "unknownDefinition" errors
        let messages = try FITDecoder.decode(data: fileData, verifyCRC: true)

        // We expect: 1 file_id data + 2 record data = 3 messages
        #expect(messages.count == 3)

        // The last message should be a record (global=20)
        let lastMsg = messages.last
        #expect(lastMsg?.globalMessageNumber == 20)

        // Verify coordinates are correct (proving alignment wasn't lost)
        let fc = try FITCoder.read(from: fileData)
        let tracks = fc.features.filter { $0.properties["fit_type"] as? String == "record" }
        #expect(tracks.count == 1)

        guard let track = tracks.first, let ml = track.geometry as? MultiLineString else {
            Issue.record("Missing track or MultiLineString")
            return
        }
        #expect(ml.lineStrings[0].coordinates.count == 2)
        #expect(abs(ml.lineStrings[0].coordinates[0].latitude - 47.5) < 0.01)
        #expect(abs(ml.lineStrings[0].coordinates[0].longitude - 11.5) < 0.01)
        #expect(abs(ml.lineStrings[0].coordinates[1].latitude - 48.0) < 0.01)
        #expect(abs(ml.lineStrings[0].coordinates[1].longitude - 12.0) < 0.01)
    }

    // MARK: - Compressed timestamp messages

    /// Compressed timestamp headers use bit 5 as the local message number (0 or 1).
    /// The decoder must not read an extra byte — the local message number is just
    /// `(header >> 5) & 0x01`.
    @Test
    func compressedTimestampUsesLocalMessageNumber1() async throws {
        var headerData = Data()
        var mesgData = Data()

        // Definition: file_id (local 0, global 0)
        mesgData.append(0x40)
        mesgData.append(0x00)
        mesgData.append(0x00)
        mesgData.append(contentsOf: le16(0))
        mesgData.append(1)
        mesgData.append(contentsOf: [0, 1, 0])

        // Data: file_id
        mesgData.append(0x00)
        mesgData.append(4)

        // Definition: record (local 1, global 20)
        mesgData.append(0x41)
        mesgData.append(0x00)
        mesgData.append(0x00)
        mesgData.append(contentsOf: le16(20))
        mesgData.append(2)
        mesgData.append(contentsOf: [0, 4, 5])   // lat
        mesgData.append(contentsOf: [1, 4, 5])   // lon

        // Compressed timestamp message with local message number 1
        // Header: bit 7=1, bit 6=1, bit 5=1 (local=1), bits 4-0=time offset
        // = 0b11100000 = 0xE0
        mesgData.append(0xE0)  // compressed header, local=1, time_offset=0
        mesgData.append(contentsOf: le32(semicircles(47.0)))  // lat
        mesgData.append(contentsOf: le32(semicircles(11.0)))  // lon

        // Another compressed timestamp message with local message number 0
        // This should fail if local=0 is used (no definition for local=0 that has
        // position fields). But we defined file_id as local=0, so this will
        // read 1 byte (the enum field). Let's test local=1 instead.
        mesgData.append(0xE0)  // another compressed, local=1, time_offset=0
        mesgData.append(contentsOf: le32(semicircles(48.0)))
        mesgData.append(contentsOf: le32(semicircles(12.0)))

        // Assemble
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

        // Decode
        let messages = try FITDecoder.decode(data: fileData, verifyCRC: true)

        // 1 file_id data + 2 compressed record messages = 3 messages
        #expect(messages.count == 3)

        // The compressed messages should use local=1 (record, global=20)
        let recordMessages = messages.filter { $0.globalMessageNumber == 20 }
        #expect(recordMessages.count == 2)
    }

    /// A compressed timestamp header with bit 5 = 0 should use local message number 0.
    @Test
    func compressedTimestampUsesLocalMessageNumber0() async throws {
        var headerData = Data()
        var mesgData = Data()

        // Definition: a simple message (local 0, global 0 = file_id) with 1 field
        mesgData.append(0x40)
        mesgData.append(0x00)
        mesgData.append(0x00)
        mesgData.append(contentsOf: le16(0))
        mesgData.append(1)
        mesgData.append(contentsOf: [0, 1, 0])  // type: enum, 1 byte

        // Regular data message: file_id
        mesgData.append(0x00)
        mesgData.append(4)  // type = activity

        // Compressed timestamp message with local message number 0
        // Header: bit 7=1, bit 6=1, bit 5=0 (local=0), bits 4-0=time offset
        // = 0b11000000 = 0xC0
        mesgData.append(0xC0)  // compressed header, local=0, time_offset=0
        mesgData.append(5)     // type = workout (1 byte, matching the file_id definition)

        // Assemble
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

        // Decode
        let messages = try FITDecoder.decode(data: fileData, verifyCRC: true)

        // 1 regular data + 1 compressed = 2 messages
        #expect(messages.count == 2)

        // Both should be file_id (global=0)
        #expect(messages.allSatisfy { $0.globalMessageNumber == 0 })
    }

    // MARK: - CRC-16/ARC (Dynastream CRC)

    /// The FIT protocol uses the Dynastream CRC-16 (identical to CRC-16/ARC:
    /// polynomial 0x8005, reflected, init=0, xorout=0).
    /// This is NOT CRC-16/CCITT (polynomial 0x1021) which was previously used.
    @Test
    func crcMatchesDynastreamSpec() async throws {
        // Known CRC values for the Dynastream CRC-16 algorithm
        // CRC-16/ARC of empty data = 0
        #expect(crc16(Data()) == 0)

        // CRC-16/ARC of "123456789" = 0xBB3D
        let testString = "123456789".data(using: .ascii)!
        #expect(crc16(testString) == 0xBB3D)

        // Verify that a FIT file with a correct CRC passes validation
        guard let data = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        // Should not throw a CRC mismatch error
        let messages = try FITDecoder.decode(data: data, verifyCRC: true)
        #expect(messages.count > 0)
    }

    /// A FIT file with an incorrect CRC should fail validation.
    @Test
    func crcMismatchThrowsError() async throws {
        guard var data = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        // Corrupt the last 2 bytes (the CRC)
        let crcOffset = data.count - 2
        data[crcOffset] = 0xFF
        data[crcOffset + 1] = 0xFF

        do {
            _ = try FITDecoder.decode(data: data, verifyCRC: true)
            Issue.record("Should have thrown CRC mismatch error")
        }
        catch {
            // Expected
        }
    }

    /// CRC validation can be skipped with verifyCRC: false.
    @Test
    func crcSkippable() async throws {
        guard var data = makeMinimalFIT() else {
            Issue.record("Failed to create minimal FIT")
            return
        }

        // Corrupt the CRC
        let crcOffset = data.count - 2
        data[crcOffset] = 0xFF
        data[crcOffset + 1] = 0xFF

        // Should succeed with verifyCRC: false
        let messages = try FITDecoder.decode(data: data, verifyCRC: false)
        #expect(messages.count > 0)
    }

    // MARK: - Helpers

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

    /// Creates a minimal valid FIT file with a 14-byte header (including header CRC).
    private func makeMinimalFIT() -> Data? {
        var headerData = Data()
        var mesgData = Data()

        // Definition: file_id (local 0, global 0)
        mesgData.append(0x40)
        mesgData.append(0x00)
        mesgData.append(0x00)
        mesgData.append(contentsOf: le16(0))
        mesgData.append(1)
        mesgData.append(contentsOf: [0, 1, 0])

        // Data: file_id
        mesgData.append(0x00)
        mesgData.append(4)

        // Definition: record (local 1, global 20)
        mesgData.append(0x41)
        mesgData.append(0x00)
        mesgData.append(0x00)
        mesgData.append(contentsOf: le16(20))
        mesgData.append(2)
        mesgData.append(contentsOf: [0, 4, 5])
        mesgData.append(contentsOf: [1, 4, 5])

        // Data: record
        mesgData.append(0x01)
        mesgData.append(contentsOf: le32(semicircles(47.5)))
        mesgData.append(contentsOf: le32(semicircles(11.5)))

        // 14-byte header (with CRC)
        headerData.append(14)                       // header size
        headerData.append(0x20)                     // protocol version
        headerData.append(contentsOf: le16(2100))   // profile version
        headerData.append(contentsOf: le32(UInt32(mesgData.count))) // data size
        headerData.append(contentsOf: [0x2E, 0x46, 0x49, 0x54]) // ".FIT"
        // Header CRC
        let headerCrc = crc16(headerData)
        headerData.append(contentsOf: le16(headerCrc))

        var fileData = Data()
        fileData.append(headerData)
        fileData.append(mesgData)

        // File CRC (over header + data)
        let fileCrc = crc16(fileData)
        fileData.append(contentsOf: le16(fileCrc))

        return fileData
    }

}