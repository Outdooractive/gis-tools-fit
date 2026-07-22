import Foundation

/// Encodes typed FIT messages into binary FIT 2.0 file data.
///
/// This is the inverse of ``FITDecoder``: it takes a list of
/// ``FITEncoder/EncodedMessage``s and produces a complete FIT file
/// (header, definition messages, data messages and file CRC).
///
/// The caller is responsible for providing the correct base types and
/// pre-encoded little-endian field data. Use
/// ``FITCoder/write(from:to:)`` or ``FITCoder/write(to:)`` for the
/// high-level GeoJSON → FIT conversion.
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
    static func encode(
        messages: [EncodedMessage],
        protocolVersion: UInt8 = 0x20,
        profileVersion: UInt16 = 2100,
        includeHeaderCRC: Bool = false
    ) -> Data {
        var builder = BuilderState(
            protocolVersion: protocolVersion,
            profileVersion: profileVersion,
            includeHeaderCRC: includeHeaderCRC)

        for message in messages {
            builder.addMessage(message)
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

        /// The next local message number to assign.
        var nextLocalNum: UInt8 = 0

        mutating func addMessage(_ message: EncodedMessage) {
            let localNum: UInt8
            if let existing = localNumByGlobal[message.globalMessageNumber] {
                localNum = existing
            }
            else {
                localNum = nextLocalNum
                localNumByGlobal[message.globalMessageNumber] = localNum
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
                mesgData.append(field.baseType.rawValue)
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
                let headerCrc = crc16(fileData)
                fileData.append(UInt8(headerCrc & 0xFF))
                fileData.append(UInt8((headerCrc >> 8) & 0xFF))
            }

            // Data
            fileData.append(mesgData)

            // File CRC (over header + data)
            let fileCrc = crc16(fileData)
            fileData.append(UInt8(fileCrc & 0xFF))
            fileData.append(UInt8((fileCrc >> 8) & 0xFF))

            return fileData
        }
    }

    // MARK: - CRC-16/ARC (Dynastream CRC)

    /// Computes the FIT CRC-16/ARC (polynomial 0x8005, reflected, init 0).
    static func crc16(_ data: Data) -> UInt16 {
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
        case unsupportedValueType(String)

        var errorDescription: String? {
            switch self {
            case .noRecordFeature:
                "No track Feature with fit_type == \"record\" was found"
            case .tooManyMessageTypes(let n):
                "Too many distinct message types (\(n)); FIT supports at most 16 local message definitions"
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

}