import Foundation
import Testing
@testable import GISToolsFIT

/// Low-level decoder tests for FIT base types, endianness, invalid values and
/// malformed files.
struct DecoderEdgeCaseTests {

    // MARK: - Base types

    @Test
    func decodesAllBaseTypesLittleEndian() throws {
        let fields: [(num: UInt8, size: UInt8, baseType: UInt8)] = [
            (0, 1, 0x00),  // enum
            (1, 1, 0x01),  // sint8
            (2, 1, 0x02),  // uint8
            (3, 2, 0x83),  // sint16
            (4, 2, 0x84),  // uint16
            (5, 4, 0x85),  // sint32
            (6, 4, 0x86),  // uint32
            (7, 3, 0x07),  // string
            (8, 4, 0x88),  // float32
            (9, 8, 0x89),  // float64
            (10, 1, 0x0A),  // uint8z
            (11, 2, 0x8B),  // uint16z
            (12, 4, 0x8C),  // uint32z
            (13, 1, 0x0D),  // byte
            (14, 8, 0x8E),  // sint64
            (15, 8, 0x8F),  // uint64
            (16, 8, 0x90),  // uint64z
        ]

        var body = Data()
        body.append(FITTestBuilder.definition(local: 0, global: 100, fields: fields))
        body.append(FITTestBuilder.dataHeader(local: 0))
        body.append(4)
        body.append(contentsOf: [0xFB])
        body.append(200)
        body.append(FITTestBuilder.le16(UInt16(bitPattern: Int16(-12_345))))
        body.append(FITTestBuilder.le16(54_321))
        body.append(FITTestBuilder.le32(UInt32(bitPattern: Int32(-123_456_789))))
        body.append(FITTestBuilder.le32(3_000_000_000))
        body.append(contentsOf: Array("hi".utf8))
        body.append(0)
        body.append(FITTestBuilder.le32(Float(1.5).bitPattern))
        body.append(FITTestBuilder.le64(Double(-2.25).bitPattern))
        body.append(5)
        body.append(FITTestBuilder.le16(500))
        body.append(FITTestBuilder.le32(500_000))
        body.append(0x42)
        body.append(FITTestBuilder.le64(UInt64(bitPattern: Int64(-9_000_000_000))))
        body.append(FITTestBuilder.le64(9_000_000_000))
        body.append(FITTestBuilder.le64(1))

        let messages = try FITDecoder.decode(data: FITTestBuilder.file(body: body))
        let message = try #require(messages.first)
        #expect(message.fields.count == fields.count)
        #expect(message.fields[0] as? UInt8 == 4)
        #expect(message.fields[1] as? Int8 == -5)
        #expect(message.fields[2] as? UInt8 == 200)
        #expect(message.fields[3] as? Int16 == -12_345)
        #expect(message.fields[4] as? UInt16 == 54_321)
        #expect(message.fields[5] as? Int32 == -123_456_789)
        #expect(message.fields[6] as? UInt32 == 3_000_000_000)
        #expect(message.fields[7] as? String == "hi")
        #expect(message.fields[8] as? Float == 1.5)
        #expect(message.fields[9] as? Double == -2.25)
        #expect(message.fields[10] as? UInt8 == 5)
        #expect(message.fields[11] as? UInt16 == 500)
        #expect(message.fields[12] as? UInt32 == 500_000)
        #expect(message.fields[13] as? UInt8 == 0x42)
        #expect(message.fields[14] as? Int64 == -9_000_000_000)
        #expect(message.fields[15] as? UInt64 == 9_000_000_000)
        #expect(message.fields[16] as? UInt64 == 1)
    }

    @Test
    func decodesAllBaseTypesBigEndian() throws {
        let fields: [(num: UInt8, size: UInt8, baseType: UInt8)] = [
            (0, 2, 0x83),
            (1, 2, 0x84),
            (2, 4, 0x85),
            (3, 4, 0x86),
            (4, 4, 0x88),
            (5, 8, 0x89),
            (6, 8, 0x8E),
            (7, 8, 0x8F),
        ]

        var body = Data()
        body.append(FITTestBuilder.definition(local: 2, global: 100, fields: fields, architecture: 1))
        body.append(FITTestBuilder.dataHeader(local: 2))
        body.append(FITTestBuilder.be16(UInt16(bitPattern: Int16(-12_345))))
        body.append(FITTestBuilder.be16(54_321))
        body.append(FITTestBuilder.be32(UInt32(bitPattern: Int32(-123_456_789))))
        body.append(FITTestBuilder.be32(3_000_000_000))
        body.append(FITTestBuilder.be32(Float(1.5).bitPattern))
        body.append(FITTestBuilder.be64(Double(-2.25).bitPattern))
        body.append(FITTestBuilder.be64(UInt64(bitPattern: Int64(-9_000_000_000))))
        body.append(FITTestBuilder.be64(9_000_000_000))

        let messages = try FITDecoder.decode(data: FITTestBuilder.file(body: body))
        let message = try #require(messages.first)
        #expect(message.fields[0] as? Int16 == -12_345)
        #expect(message.fields[1] as? UInt16 == 54_321)
        #expect(message.fields[2] as? Int32 == -123_456_789)
        #expect(message.fields[3] as? UInt32 == 3_000_000_000)
        #expect(message.fields[4] as? Float == 1.5)
        #expect(message.fields[5] as? Double == -2.25)
        #expect(message.fields[6] as? Int64 == -9_000_000_000)
        #expect(message.fields[7] as? UInt64 == 9_000_000_000)
    }

    @Test
    func filtersInvalidSentinelValues() throws {
        let fields: [(num: UInt8, size: UInt8, baseType: UInt8)] = [
            (0, 1, 0x00),
            (1, 1, 0x01),
            (2, 1, 0x02),
            (3, 2, 0x83),
            (4, 2, 0x84),
            (5, 4, 0x85),
            (6, 4, 0x86),
            (7, 4, 0x88),
            (8, 8, 0x89),
            (9, 1, 0x0A),
            (10, 2, 0x8B),
            (11, 4, 0x8C),
            (12, 1, 0x0D),
            (13, 8, 0x8E),
            (14, 8, 0x8F),
            (15, 8, 0x90),
        ]

        var body = Data()
        body.append(FITTestBuilder.definition(local: 0, global: 100, fields: fields))
        body.append(FITTestBuilder.dataHeader(local: 0))
        body.append(0xFF)  // enum
        body.append(0x7F)  // sint8
        body.append(0xFF)  // uint8
        body.append(FITTestBuilder.le16(0x7FFF))
        body.append(FITTestBuilder.le16(0xFFFF))
        body.append(FITTestBuilder.le32(0x7FFF_FFFF))
        body.append(FITTestBuilder.le32(0xFFFF_FFFF))
        body.append(FITTestBuilder.le32(0xFFFF_FFFF))
        body.append(FITTestBuilder.le64(0xFFFF_FFFF_FFFF_FFFF))
        body.append(0)     // uint8z
        body.append(FITTestBuilder.le16(0))  // uint16z
        body.append(FITTestBuilder.le32(0))  // uint32z
        body.append(0xFF)  // byte
        body.append(FITTestBuilder.le64(0x7FFF_FFFF_FFFF_FFFF))
        body.append(FITTestBuilder.le64(0xFFFF_FFFF_FFFF_FFFF))
        body.append(FITTestBuilder.le64(0))

        let messages = try FITDecoder.decode(data: FITTestBuilder.file(body: body))
        let message = try #require(messages.first)
        #expect(message.fields.isEmpty)
    }

    @Test
    func keepsValidZeroValues() throws {
        var body = Data()
        body.append(FITTestBuilder.definition(
            local: 0,
            global: 100,
            fields: [
                (0, 1, 0x02),
                (1, 2, 0x84),
                (2, 4, 0x86),
            ]))
        body.append(FITTestBuilder.dataHeader(local: 0))
        body.append(0)
        body.append(FITTestBuilder.le16(0))
        body.append(FITTestBuilder.le32(0))

        let messages = try FITDecoder.decode(data: FITTestBuilder.file(body: body))
        let message = try #require(messages.first)
        #expect(message.fields[0] as? UInt8 == 0)
        #expect(message.fields[1] as? UInt16 == 0)
        #expect(message.fields[2] as? UInt32 == 0)
    }

    @Test
    func decodesNumericArrays() throws {
        var body = Data()
        body.append(FITTestBuilder.definition(
            local: 0,
            global: 100,
            fields: [(0, 6, 0x84)]))
        body.append(FITTestBuilder.dataHeader(local: 0))
        body.append(FITTestBuilder.le16(1))
        body.append(FITTestBuilder.le16(2))
        body.append(FITTestBuilder.le16(3))

        let messages = try FITDecoder.decode(data: FITTestBuilder.file(body: body))
        let values = try #require(messages.first?.fields[0] as? [Any])
        #expect(values.count == 3)
        #expect(values[0] as? UInt16 == 1)
        #expect(values[1] as? UInt16 == 2)
        #expect(values[2] as? UInt16 == 3)
    }

    @Test
    func stringStopsAtNullTerminator() throws {
        var body = Data()
        body.append(FITTestBuilder.definition(
            local: 0,
            global: 100,
            fields: [(0, 4, 0x07)]))
        body.append(FITTestBuilder.dataHeader(local: 0))
        body.append(contentsOf: Array("ab".utf8))
        body.append(0)
        body.append(contentsOf: Array("c".utf8))

        let messages = try FITDecoder.decode(data: FITTestBuilder.file(body: body))
        #expect(messages.first?.fields[0] as? String == "ab")
    }

    // MARK: - File structure errors

    @Test
    func rejectsInvalidHeaderSize() {
        var data = Data([13, 0x20])
        data.append(FITTestBuilder.le16(2100))
        data.append(FITTestBuilder.le32(0))
        data.append(contentsOf: [0x2E, 0x46, 0x49, 0x54])
        data.append(contentsOf: [0, 0, 0, 0])

        #expect(throws: FITDecoder.DecoderError.self) {
            try FITDecoder.decode(data: data)
        }
    }

    @Test
    func rejectsInvalidMagic() {
        var data = Data([12, 0x20])
        data.append(FITTestBuilder.le16(2100))
        data.append(FITTestBuilder.le32(0))
        data.append(contentsOf: Array("NOPE".utf8))
        data.append(contentsOf: [0, 0])

        #expect(throws: FITDecoder.DecoderError.self) {
            try FITDecoder.decode(data: data)
        }
    }

    @Test
    func rejectsTruncatedFile() throws {
        let body = Data()
        let data = FITTestBuilder.file(body: body)
        #expect(throws: FITDecoder.DecoderError.self) {
            try FITDecoder.decode(data: data.dropLast())
        }
    }

    @Test
    func rejectsUnknownLocalMessageDefinition() {
        var body = Data()
        body.append(FITTestBuilder.dataHeader(local: 3))
        let data = FITTestBuilder.file(body: body)

        do {
            _ = try FITDecoder.decode(data: data)
            Issue.record("Expected an unknown-definition error")
        }
        catch let error as FITDecoder.DecoderError {
            guard case .unknownDefinition(let local) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(local == 3)
        }
        catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func rejectsInvalidArchitecture() {
        var body = Data()
        body.append(FITTestBuilder.definition(
            local: 0,
            global: 100,
            fields: [],
            architecture: 2))
        let data = FITTestBuilder.file(body: body)

        do {
            _ = try FITDecoder.decode(data: data)
            Issue.record("Expected an invalid-architecture error")
        }
        catch let error as FITDecoder.DecoderError {
            guard case .invalidArchitecture(let value) = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
            #expect(value == 2)
        }
        catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - CRC

    @Test
    func validatesHeaderCRC() throws {
        let body = Data()
        var data = FITTestBuilder.file(body: body, includeHeaderCRC: true)
        #expect(data.count == 16)

        // Corrupt only the header CRC and recompute the file CRC so that the
        // header CRC check is the one that fails.
        data[12] ^= 0xFF
        let fileCRC = FITTestBuilder.crc16(Data(data.prefix(data.count - 2)))
        data.replaceSubrange((data.count - 2)..<data.count, with: FITTestBuilder.le16(fileCRC))

        do {
            _ = try FITDecoder.decode(data: data)
            Issue.record("Expected a header CRC mismatch")
        }
        catch let error as FITDecoder.DecoderError {
            guard case .headerCRCMismatch = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }
        catch {
            Issue.record("Unexpected error: \(error)")
        }

        // The header CRC check can be disabled.
        _ = try FITDecoder.decode(data: data, verifyHeaderCRC: false)
    }

    @Test
    func acceptsZeroHeaderCRC() throws {
        let body = Data()
        var data = FITTestBuilder.file(body: body, includeHeaderCRC: true)
        data[12] = 0
        data[13] = 0
        let fileCRC = FITTestBuilder.crc16(Data(data.prefix(data.count - 2)))
        data.replaceSubrange((data.count - 2)..<data.count, with: FITTestBuilder.le16(fileCRC))

        let messages = try FITDecoder.decode(data: data)
        #expect(messages.isEmpty)
    }

    @Test
    func detectsFileCRCMismatch() {
        var body = Data()
        body.append(FITTestBuilder.definition(local: 0, global: 100, fields: []))
        body.append(FITTestBuilder.dataHeader(local: 0))
        var data = FITTestBuilder.file(body: body)

        // Flip a byte in the body without updating the CRC.
        data[13] ^= 0xFF
        #expect(throws: FITDecoder.DecoderError.self) {
            try FITDecoder.decode(data: data)
        }
    }

    // MARK: - Invalid values in arrays

    @Test
    func arrayDropsInvalidElements() throws {
        var body = Data()
        body.append(FITTestBuilder.definition(
            local: 0,
            global: 100,
            fields: [(0, 3, 0x02)]))
        body.append(FITTestBuilder.dataHeader(local: 0))
        body.append(contentsOf: [1, 0xFF, 3])

        let messages = try FITDecoder.decode(data: FITTestBuilder.file(body: body))
        let values = try #require(messages.first?.fields[0] as? [Any])
        #expect(values.count == 2)
        #expect(values[0] as? UInt8 == 1)
        #expect(values[1] as? UInt8 == 3)
    }

}
