import Foundation

/// Encodes typed FIT messages into binary FIT 2.0 file data.
///
/// This is the inverse of ``FITDecoder``: it takes a list of
/// ``FITEncoder/EncodedMessage``s and produces a complete FIT file
/// (header, definition messages, data messages and file CRC).
///
/// The caller is responsible for providing the correct base types and
/// pre-encoded little-endian field data. Use
/// ``FITCoder/write(_:options:)`` or ``FITCoder/write(_:to:options:)`` for
/// the high-level GeoJSON → FIT conversion.
enum FITEncoder {

    // MARK: - Encoded representation

    /// A single field ready to be written to the binary stream.
    struct EncodedField {

        /// The field number (e.g. 0 for `position_lat`).
        let num: UInt8

        /// The FIT base type (see ``FITBaseType``).
        let baseType: FITBaseType

        /// The pre-encoded little-endian field data, already padded to
        /// the size declared in the definition.
        let data: Data
    }

    /// A message ready to be written to the binary stream.
    struct EncodedMessage {

        /// The global message number (e.g. 20 for `record`).
        let globalMessageNumber: UInt16

        /// The fields in definition order.
        let fields: [EncodedField]

        /// Creates an encoded message from a global message number and fields.
        init(globalMessageNumber: UInt16, fields: [EncodedField]) {
            self.globalMessageNumber = globalMessageNumber
            self.fields = fields
        }
    }

    // MARK: - String encoding

    static func encodeString(_ s: String) -> Data {
        var data = Data(s.utf8)
        data.append(0)  // null terminator
        return data
    }

    // MARK: - Raw value encoding

    /// Encodes a raw value (as produced by ``FITProfile/FieldMeta/rawValue(from:)``)
    /// into the little-endian bytes for a base type.
    ///
    /// - Parameters:
    ///   - raw: The raw value. Arrays are encoded element-wise.
    ///   - baseType: The FIT base type of the field.
    /// - Returns: The little-endian field bytes.
    /// - Throws: ``EncoderError/unsupportedValueType(_:)`` when the value
    ///   cannot be represented by the base type.
    static func encode(raw: Any, baseType: FITBaseType) throws -> Data {
        if let array = raw as? [Any] {
            guard !array.isEmpty else {
                throw EncoderError.unsupportedValueType("empty array")
            }
            var data = Data()
            for element in array {
                data.append(try encode(raw: element, baseType: baseType))
            }
            return data
        }
        if let s = raw as? String {
            return encodeString(s)
        }
        if let d = raw as? Double {
            return try encodeDouble(d, baseType: baseType)
        }
        if let f = raw as? Float {
            return try encodeDouble(Double(f), baseType: baseType)
        }
        if let i = raw as? Int64 {
            return try encodeInt64(i, baseType: baseType)
        }
        if let i = raw as? Int {
            return try encodeInt64(Int64(i), baseType: baseType)
        }
        if let u = raw as? UInt64 {
            return try encodeUInt64(u, baseType: baseType)
        }
        if let u = raw as? UInt32 {
            return try encodeInt64(Int64(u), baseType: baseType)
        }
        if let u = raw as? UInt16 {
            return try encodeInt64(Int64(u), baseType: baseType)
        }
        if let u = raw as? UInt8 {
            return try encodeInt64(Int64(u), baseType: baseType)
        }
        if let i = raw as? Int32 {
            return try encodeInt64(Int64(i), baseType: baseType)
        }
        if let i = raw as? Int16 {
            return try encodeInt64(Int64(i), baseType: baseType)
        }
        if let i = raw as? Int8 {
            return try encodeInt64(Int64(i), baseType: baseType)
        }
        if let b = raw as? Bool {
            return try encodeInt64(b ? 1 : 0, baseType: baseType)
        }
        throw EncoderError.unsupportedValueType(String(describing: type(of: raw)))
    }

    private static func encodeInt64(_ v: Int64, baseType: FITBaseType) throws -> Data {
        switch baseType {
        case .sint8:
            guard v >= Int64(Int8.min), v <= Int64(Int8.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for sint8")
            }
            return Data([UInt8(bitPattern: Int8(v))])
        case .sint16:
            guard v >= Int64(Int16.min), v <= Int64(Int16.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for sint16")
            }
            return le16(UInt16(bitPattern: Int16(v)))
        case .sint32:
            guard v >= Int64(Int32.min), v <= Int64(Int32.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for sint32")
            }
            return le32(Int32(v))
        case .sint64: return le64(UInt64(bitPattern: v))
        case .enumType, .uint8, .uint8z, .byte:
            guard v >= 0, v <= Int64(UInt8.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint8")
            }
            return Data([UInt8(v)])
        case .uint16, .uint16z:
            guard v >= 0, v <= Int64(UInt16.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint16")
            }
            return le16(UInt16(v))
        case .uint32, .uint32z:
            guard v >= 0, v <= Int64(UInt32.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint32")
            }
            return le32(UInt32(v))
        case .uint64, .uint64z:
            guard v >= 0 else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint64")
            }
            return le64(UInt64(v))
        case .float32: return le32(Float(v).bitPattern)
        case .float64: return le64(Float64(v).bitPattern)
        case .string: return encodeString("\(v)")
        }
    }

    private static func encodeUInt64(_ v: UInt64, baseType: FITBaseType) throws -> Data {
        switch baseType {
        case .uint64, .uint64z: return le64(v)
        case .uint32, .uint32z:
            guard v <= UInt64(UInt32.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint32")
            }
            return le32(UInt32(v))
        case .uint16, .uint16z:
            guard v <= UInt64(UInt16.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint16")
            }
            return le16(UInt16(v))
        case .uint8, .uint8z, .enumType, .byte:
            guard v <= UInt64(UInt8.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint8")
            }
            return Data([UInt8(v)])
        case .sint64:
            guard v <= UInt64(Int64.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for sint64")
            }
            return le64(v)
        case .sint32, .sint16, .sint8:
            guard v <= UInt64(Int64.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for a signed base type")
            }
            return try encodeInt64(Int64(v), baseType: baseType)
        case .float32: return le32(Float(v).bitPattern)
        case .float64: return le64(Double(v).bitPattern)
        case .string: return encodeString("\(v)")
        }
    }

    private static func encodeDouble(_ v: Double, baseType: FITBaseType) throws -> Data {
        switch baseType {
        case .float32: return le32(Float(v).bitPattern)
        case .float64: return le64(Float64(v).bitPattern)
        case .uint64, .uint64z:
            guard v.isFinite, v >= 0, v <= Double(UInt64.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint64")
            }
            return le64(UInt64(v.rounded()))
        case .uint32, .uint32z:
            guard v.isFinite, v >= 0, v <= Double(UInt32.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint32")
            }
            return le32(UInt32(v.rounded()))
        case .uint16, .uint16z:
            guard v.isFinite, v >= 0, v <= Double(UInt16.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint16")
            }
            return le16(UInt16(v.rounded()))
        case .uint8, .uint8z, .enumType, .byte:
            guard v.isFinite, v >= 0, v <= Double(UInt8.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for uint8")
            }
            return Data([UInt8(v.rounded())])
        case .sint8:
            guard v.isFinite, v >= Double(Int8.min), v <= Double(Int8.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for sint8")
            }
            return Data([UInt8(bitPattern: Int8(v.rounded()))])
        case .sint16:
            guard v.isFinite, v >= Double(Int16.min), v <= Double(Int16.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for sint16")
            }
            return le16(UInt16(bitPattern: Int16(v.rounded())))
        case .sint32:
            guard v.isFinite, v >= Double(Int32.min), v <= Double(Int32.max) else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for sint32")
            }
            return le32(Int32(v.rounded()))
        case .sint64:
            guard v.isFinite,
                  v >= Double(Int64.min),
                  v <= Double(Int64.max)
            else {
                throw EncoderError.unsupportedValueType("value \(v) out of range for sint64")
            }
            return try encodeInt64(Int64(v.rounded()), baseType: baseType)
        case .string: return encodeString("\(v)")
        }
    }

    // MARK: - Public API

    /// Encodes a list of messages into a complete FIT file.
    ///
    /// - Parameters:
    ///    - messages: The messages to encode, in file order.
    ///    - protocolVersion: The FIT protocol version (default `0x20` = 2.0).
    ///    - profileVersion: The FIT profile version (default `2100`).
    ///    - includeHeaderCRC: If `true`, a 14-byte header with a header CRC
    ///      is written (default `false`, 12-byte header).
    /// - Returns: The binary FIT file data.
    /// - Throws: ``EncoderError`` when the messages exceed the FIT limits or
    ///   contain values that cannot be encoded.
    static func encode(
        messages: [EncodedMessage],
        protocolVersion: UInt8 = 0x20,
        profileVersion: UInt16 = 2100,
        includeHeaderCRC: Bool = false
    ) throws -> Data {
        let distinctMessageTypes = Set(messages.map(\.globalMessageNumber)).count
        guard distinctMessageTypes <= 16 else {
            throw EncoderError.tooManyMessageTypes(distinctMessageTypes)
        }

        for message in messages {
            guard message.fields.count <= Int(UInt8.max) else {
                throw EncoderError.tooManyFields(message.fields.count)
            }
            for field in message.fields {
                guard !field.data.isEmpty else {
                    throw EncoderError.emptyField(field.num)
                }
                guard field.data.count <= Int(UInt8.max) else {
                    throw EncoderError.fieldTooLarge(field.num, field.data.count)
                }
            }
        }

        var builder = BuilderState(
            protocolVersion: protocolVersion,
            profileVersion: profileVersion,
            includeHeaderCRC: includeHeaderCRC)

        for message in messages {
            try builder.addMessage(message)
        }

        return builder.finalize()
    }

    // MARK: - Builder state

    private struct BuilderState {

        let protocolVersion: UInt8
        let profileVersion: UInt16
        let includeHeaderCRC: Bool

        /// The accumulated message data (everything after the header).
        var mesgData = Data()

        /// Maps global message number -> assigned local message number.
        var localNumByGlobal: [UInt16: UInt8] = [:]

        /// Maps global message number -> field signature of last written definition.
        var definitionSignature: [UInt16: String] = [:]

        /// The next local message number to assign.
        var nextLocalNum: UInt8 = 0

        mutating func addMessage(_ message: EncodedMessage) throws {
            let fieldSignature = message.fields.map { "\($0.num):\($0.data.count):\($0.baseType.wireValue)" }.joined(separator: ",")

            let localNum: UInt8
            if let existing = localNumByGlobal[message.globalMessageNumber] {
                localNum = existing
                if fieldSignature != definitionSignature[message.globalMessageNumber] {
                    // Field layout changed — write a new definition reusing
                    // the existing local message number.
                    writeDefinition(for: message, localNum: localNum)
                    definitionSignature[message.globalMessageNumber] = fieldSignature
                }
            }
            else {
                guard nextLocalNum <= 0x0F else {
                    throw EncoderError.tooManyMessageTypes(localNumByGlobal.count + 1)
                }
                localNum = nextLocalNum
                localNumByGlobal[message.globalMessageNumber] = localNum
                definitionSignature[message.globalMessageNumber] = fieldSignature
                nextLocalNum += 1
                writeDefinition(for: message, localNum: localNum)
            }
            writeData(message, localNum: localNum)
        }

        // MARK: - Definition messages

        private mutating func writeDefinition(
            for message: EncodedMessage,
            localNum: UInt8
        ) {
            // Definition header: 0x40 | localMesgNum
            mesgData.append(0x40 | localNum)
            mesgData.append(0x00)  // reserved
            mesgData.append(0x00)  // architecture (little-endian)

            // Global message number (LE)
            mesgData.append(UInt8(message.globalMessageNumber & 0xFF))
            mesgData.append(UInt8((message.globalMessageNumber >> 8) & 0xFF))

            // Field count
            mesgData.append(UInt8(message.fields.count))

            // Field definitions: num, size, baseType
            for field in message.fields {
                mesgData.append(field.num)
                mesgData.append(UInt8(field.data.count))
                mesgData.append(field.baseType.wireValue)
            }
        }

        // MARK: - Data messages

        private mutating func writeData(
            _ message: EncodedMessage,
            localNum: UInt8
        ) {
            // Data header: 0x00 | localMesgNum
            mesgData.append(localNum)

            for field in message.fields {
                mesgData.append(field.data)
            }
        }

        // MARK: - Finalize

        mutating func finalize() -> Data {
            var fileData = Data()

            // Header
            let headerSize: UInt8 = includeHeaderCRC ? 14 : 12
            fileData.append(headerSize)
            fileData.append(protocolVersion)
            fileData.append(UInt8(profileVersion & 0xFF))
            fileData.append(UInt8((profileVersion >> 8) & 0xFF))
            fileData.append(UInt8(UInt32(mesgData.count) & 0xFF))
            fileData.append(UInt8((UInt32(mesgData.count) >> 8) & 0xFF))
            fileData.append(UInt8((UInt32(mesgData.count) >> 16) & 0xFF))
            fileData.append(UInt8((UInt32(mesgData.count) >> 24) & 0xFF))
            fileData.append(0x2E)  // "."
            fileData.append(0x46)  // "F"
            fileData.append(0x49)  // "I"
            fileData.append(0x54)  // "T"

            if includeHeaderCRC {
                let headerCrc = FITCRC.crc16(fileData)
                fileData.append(UInt8(headerCrc & 0xFF))
                fileData.append(UInt8((headerCrc >> 8) & 0xFF))
            }

            // Data
            fileData.append(mesgData)

            // File CRC (over header + data)
            let fileCrc = FITCRC.crc16(fileData)
            fileData.append(UInt8(fileCrc & 0xFF))
            fileData.append(UInt8((fileCrc >> 8) & 0xFF))

            return fileData
        }
    }

    // MARK: - CRC-16/ARC (Dynastream CRC)

    /// Computes the FIT CRC-16/ARC (polynomial 0x8005, reflected, init 0).
    static func crc16(_ data: Data) -> UInt16 {
        FITCRC.crc16(data)
    }

    // MARK: - Little-endian encoding helpers

    /// Encodes a `UInt16` as little-endian bytes.
    static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    /// Encodes a `UInt32` as little-endian bytes.
    static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    /// Encodes an `Int32` as little-endian bytes.
    static func le32(_ value: Int32) -> Data {
        le32(UInt32(bitPattern: value))
    }

    /// Encodes a `UInt64` as little-endian bytes.
    static func le64(_ value: UInt64) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 32) & 0xFF),
            UInt8((value >> 40) & 0xFF),
            UInt8((value >> 48) & 0xFF),
            UInt8((value >> 56) & 0xFF),
        ])
    }

    // MARK: - Errors

    enum EncoderError: Swift.Error, LocalizedError {

        case noRecordFeature
        case tooManyMessageTypes(Int)
        case tooManyFields(Int)
        case fieldTooLarge(UInt8, Int)
        case emptyField(UInt8)
        case unsupportedValueType(String)

        var errorDescription: String? {
            switch self {
            case .noRecordFeature:
                "No track Feature with fit_type == \"record\" was found"
            case .tooManyMessageTypes(let n):
                "Too many distinct message types (\(n)); FIT supports at most 16 local message definitions"
            case .tooManyFields(let n):
                "Too many fields (\(n)); FIT supports at most 255 fields per definition"
            case .fieldTooLarge(let num, let size):
                "Field \(num) is \(size) bytes; FIT supports at most 255 bytes per field"
            case .emptyField(let num):
                "Field \(num) has no data"
            case .unsupportedValueType(let d):
                "Unsupported value type for FIT encoding: \(d)"
            }
        }
    }

}

// MARK: - FIT base types

/// FIT protocol base type identifiers.
///
/// These are the low 5 bits of the base type byte stored in definition
/// messages. The high bits are reserved (0 for non-array fields).
public enum FITBaseType: UInt8, Sendable {

    /// An enum or single byte enumeration (1 byte).
    case enumType = 0x00
    /// A signed 8-bit integer (1 byte).
    case sint8 = 0x01
    /// An unsigned 8-bit integer (1 byte).
    case uint8 = 0x02
    /// A signed 16-bit integer (2 bytes).
    case sint16 = 0x03
    /// An unsigned 16-bit integer (2 bytes).
    case uint16 = 0x04
    /// A signed 32-bit integer (4 bytes).
    case sint32 = 0x05
    /// An unsigned 32-bit integer (4 bytes).
    case uint32 = 0x06
    /// A null-terminated string (variable length, 1 byte per char).
    case string = 0x07
    /// A 32-bit floating point number (4 bytes).
    case float32 = 0x08
    /// A 64-bit floating point number (8 bytes).
    case float64 = 0x09
    /// An unsigned 8-bit integer where 0 is invalid (1 byte).
    case uint8z = 0x0A
    /// An unsigned 16-bit integer where 0 is invalid (2 bytes).
    case uint16z = 0x0B
    /// An unsigned 32-bit integer where 0 is invalid (4 bytes).
    case uint32z = 0x0C
    /// A raw byte (1 byte).
    case byte = 0x0D
    /// A signed 64-bit integer (8 bytes).
    case sint64 = 0x0E
    /// An unsigned 64-bit integer (8 bytes).
    case uint64 = 0x0F
    /// An unsigned 64-bit integer where 0 is invalid (8 bytes).
    case uint64z = 0x10

    /// The fixed size in bytes for this base type.
    var size: Int {
        switch self {
        case .enumType, .sint8, .uint8, .uint8z, .byte, .string: return 1
        case .sint16, .uint16, .uint16z: return 2
        case .sint32, .uint32, .uint32z, .float32: return 4
        case .float64, .sint64, .uint64, .uint64z: return 8
        }
    }

    /// The byte written into definition messages for this base type.
    ///
    /// FIT sets bit 7 ("endian ability") for every multi-byte base type.
    /// Decoders mask the low five bits, so writing the bit makes the output
    /// conformant with the FIT profile.
    var wireValue: UInt8 {
        size > 1 ? rawValue | 0x80 : rawValue
    }

}
