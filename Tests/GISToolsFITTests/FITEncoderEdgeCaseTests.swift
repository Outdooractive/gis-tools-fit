import Foundation
import Testing
@testable import GISToolsFIT

/// Tests for the low-level FIT encoder and its validation rules.
struct FITEncoderEdgeCaseTests {

    private func field(
        _ num: UInt8,
        _ baseType: FITBaseType,
        _ bytes: [UInt8]
    ) -> FITEncoder.EncodedField {
        FITEncoder.EncodedField(
            num: num,
            baseType: baseType,
            data: Data(bytes))
    }

    @Test
    func writesTheEndianAbilityBitInDefinitions() throws {
        let message = FITEncoder.EncodedMessage(
            globalMessageNumber: 20,
            fields: [field(3, .uint16, [0x2C, 0x01])])
        let data = try FITEncoder.encode(messages: [message])

        // 12-byte header, then definition header, reserved, architecture,
        // global message number, field count, field number, size, base type.
        #expect(data[12] == 0x40)
        #expect(data[18] == 0x03)  // field number
        #expect(data[19] == 0x02)  // field size
        #expect(data[20] == 0x84)  // uint16 with the endian-ability bit
    }

    @Test
    func reusesDefinitionsAndRewritesChangedLayouts() throws {
        let layoutA = FITEncoder.EncodedMessage(
            globalMessageNumber: 20,
            fields: [field(3, .uint8, [1])])
        let layoutB = FITEncoder.EncodedMessage(
            globalMessageNumber: 20,
            fields: [field(4, .uint8, [2])])

        let data = try FITEncoder.encode(messages: [layoutA, layoutA, layoutB])
        let messages = try FITDecoder.decode(data: data)
        #expect(messages.count == 3)
        #expect(messages[0].fields[3] as? UInt8 == 1)
        #expect(messages[1].fields[3] as? UInt8 == 1)
        #expect(messages[2].fields[4] as? UInt8 == 2)
    }

    @Test
    func rejectsMoreThanSixteenMessageTypes() {
        let messages = (0..<17).map {
            FITEncoder.EncodedMessage(globalMessageNumber: UInt16($0), fields: [])
        }
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(messages: messages)
        }
    }

    @Test
    func acceptsSixteenMessageTypes() throws {
        let messages = (0..<16).map {
            FITEncoder.EncodedMessage(globalMessageNumber: UInt16($0), fields: [])
        }
        let data = try FITEncoder.encode(messages: messages)
        let decoded = try FITDecoder.decode(data: data)
        #expect(decoded.count == 16)
    }

    @Test
    func rejectsTooManyFields() {
        let fields = (0..<256).map { field(UInt8($0), .uint8, [0]) }
        let message = FITEncoder.EncodedMessage(globalMessageNumber: 20, fields: fields)
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(messages: [message])
        }
    }

    @Test
    func rejectsEmptyFields() {
        let message = FITEncoder.EncodedMessage(
            globalMessageNumber: 20,
            fields: [FITEncoder.EncodedField(num: 0, baseType: .uint8, data: Data())])
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(messages: [message])
        }
    }

    @Test
    func rejectsOversizedFields() {
        let message = FITEncoder.EncodedMessage(
            globalMessageNumber: 20,
            fields: [field(0, .byte, Array(repeating: 0, count: 256))])
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(messages: [message])
        }
    }

    @Test
    func encodesSignedUnsignedAndFloatingPointValues() throws {
        #expect(try FITEncoder.encode(raw: Int64(-1), baseType: .sint8) == Data([0xFF]))
        #expect(try FITEncoder.encode(raw: Int64(-2), baseType: .sint16) == Data([0xFE, 0xFF]))
        #expect(try FITEncoder.encode(raw: Int64(-3), baseType: .sint32) == Data([0xFD, 0xFF, 0xFF, 0xFF]))
        #expect(try FITEncoder.encode(raw: Int64(-4), baseType: .sint64) == Data([
            0xFC, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ]))
        #expect(try FITEncoder.encode(raw: UInt64.max, baseType: .uint64) == Data([
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        ]))
        #expect(try FITEncoder.encode(raw: Float(1.5), baseType: .float32) == FITEncoder.le32(Float(1.5).bitPattern))
        #expect(try FITEncoder.encode(raw: Double(-2.25), baseType: .float64) == FITEncoder.le64(Double(-2.25).bitPattern))
        #expect(try FITEncoder.encode(raw: true, baseType: .uint8) == Data([1]))
    }

    @Test
    func encodesEveryBaseTypeFromIntegerValues() throws {
        #expect(try FITEncoder.encode(raw: Int64(0xAB), baseType: .enumType) == Data([0xAB]))
        #expect(try FITEncoder.encode(raw: Int64(0xCD), baseType: .uint8) == Data([0xCD]))
        #expect(try FITEncoder.encode(raw: Int64(0xEF), baseType: .uint8z) == Data([0xEF]))
        #expect(try FITEncoder.encode(raw: Int64(0x12), baseType: .byte) == Data([0x12]))
        #expect(try FITEncoder.encode(raw: Int64(0x1234), baseType: .uint16) == Data([0x34, 0x12]))
        #expect(try FITEncoder.encode(raw: Int64(0x1234), baseType: .uint16z) == Data([0x34, 0x12]))
        #expect(try FITEncoder.encode(raw: Int64(0x1234_5678), baseType: .uint32) == Data([
            0x78, 0x56, 0x34, 0x12,
        ]))
        #expect(try FITEncoder.encode(raw: Int64(0x1234_5678), baseType: .uint32z) == Data([
            0x78, 0x56, 0x34, 0x12,
        ]))
        #expect(try FITEncoder.encode(raw: Int64(5), baseType: .float32) == FITEncoder.le32(Float(5).bitPattern))
        #expect(try FITEncoder.encode(raw: Int64(5), baseType: .float64) == FITEncoder.le64(Double(5).bitPattern))
        #expect(try FITEncoder.encode(raw: Int64(5), baseType: .uint64z) == FITEncoder.le64(5))
        #expect(try FITEncoder.encode(raw: Int64(5), baseType: .string) == Data([0x35, 0x00]))
    }

    @Test
    func encodesEveryBaseTypeFromUnsignedValues() throws {
        #expect(try FITEncoder.encode(raw: UInt64(0xAB), baseType: .uint8) == Data([0xAB]))
        #expect(try FITEncoder.encode(raw: UInt64(0x1234), baseType: .uint16) == Data([0x34, 0x12]))
        #expect(try FITEncoder.encode(raw: UInt64(0x1234_5678), baseType: .uint32) == Data([
            0x78, 0x56, 0x34, 0x12,
        ]))
        #expect(try FITEncoder.encode(raw: UInt64(5), baseType: .sint8) == Data([5]))
        #expect(try FITEncoder.encode(raw: UInt64(5), baseType: .sint16) == Data([5, 0]))
        #expect(try FITEncoder.encode(raw: UInt64(5), baseType: .sint32) == Data([5, 0, 0, 0]))
        #expect(try FITEncoder.encode(raw: UInt64(5), baseType: .sint64) == FITEncoder.le64(5))
        #expect(try FITEncoder.encode(raw: UInt64(5), baseType: .float32) == FITEncoder.le32(Float(5).bitPattern))
        #expect(try FITEncoder.encode(raw: UInt64(5), baseType: .float64) == FITEncoder.le64(Double(5).bitPattern))
        #expect(try FITEncoder.encode(raw: UInt64(5), baseType: .string) == Data([0x35, 0x00]))
    }

    @Test
    func roundsNumericValuesForIntegerBaseTypes() throws {
        #expect(try FITEncoder.encode(raw: 3.6, baseType: .uint8) == Data([4]))
        #expect(try FITEncoder.encode(raw: -3.6, baseType: .sint8) == Data([0xFC]))
    }

    @Test
    func rejectsNonFiniteValuesForIntegerBaseTypes() {
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: Double.nan, baseType: .uint8)
        }
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: Double.infinity, baseType: .sint16)
        }
    }

    @Test
    func rejectsOutOfRangeValuesForIntegerBaseTypes() {
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: 256.0, baseType: .uint8)
        }
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: -1.0, baseType: .uint16)
        }
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: 128.0, baseType: .sint8)
        }
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: Double(UInt32.max) + 1.0, baseType: .uint32)
        }
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: Int64(256), baseType: .uint8)
        }
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: UInt64.max, baseType: .uint32)
        }
    }

    @Test
    func rejectsUnsupportedValueTypes() {
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: NSNull(), baseType: .uint8)
        }
        #expect(throws: FITEncoder.EncoderError.self) {
            try FITEncoder.encode(raw: [Any](), baseType: .uint8)
        }
    }

    @Test
    func encodesStringsWithANullTerminator() {
        #expect(FITEncoder.encodeString("ab") == Data([0x61, 0x62, 0x00]))
        #expect(FITEncoder.encodeString("") == Data([0x00]))
    }

    @Test
    func encodesArraysElementWise() throws {
        let data = try FITEncoder.encode(
            raw: [Int64(1), Int64(2), Int64(3)] as [Any],
            baseType: .uint16)
        #expect(data == Data([0x01, 0x00, 0x02, 0x00, 0x03, 0x00]))
    }

}
