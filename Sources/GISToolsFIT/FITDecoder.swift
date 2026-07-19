import Foundation

/// Decodes binary FIT 2.0 files into raw messages.
/// This implementation follows the FIT Protocol specification and uses
/// no Garmin SDK code. It is a clean-room implementation based on the
/// public FIT protocol documentation.
enum FITDecoder {

    // MARK: - Decoded representation

    /// A single decoded FIT data message.
    struct RawMessage {

        /// The global message number (e.g. 20 for Record, 0 for FileId).
        var globalMessageNumber: UInt16

        /// Decoded field values keyed by field number.
        var fields: [Int: Any] = [:]
    }

    /// A decoded definition message describing the layout of subsequent data messages.
    struct Definition {
        var localMessageNum: Int
        var globalMessageNumber: UInt16
        var architecture: UInt8  // 0 = little-endian, 1 = big-endian
        var fieldDefs: [FieldDef]
        var devFieldDefs: [FieldDef]  // developer field definitions
    }

    struct FieldDef {
        var num: UInt8
        var size: UInt8
        var baseType: UInt8
    }

    // MARK: - Public API

    /// Decodes a FIT file from raw data.
    /// - Parameter data: The binary FIT data.
    /// - Parameter verifyCRC: If `true`, validates the file CRC (default).
    /// - Returns: All decoded data messages in file order.
    static func decode(data: Data, verifyCRC: Bool = true) throws -> [RawMessage] {
        var decoder = DecoderState(data: data)
        try decoder.parseHeader()
        var messages: [RawMessage] = []

        while decoder.position < decoder.dataEnd {
            let byte = try decoder.peekByte()
            if (byte & 0xC0) == 0xC0 {
                try decoder.decodeCompressedTimestampMessage(&messages)
            }
            else if (byte & 0x40) == 0x40 {
                try decoder.decodeDefinition()
            }
            else {
                try decoder.decodeDataMessage(&messages)
            }
        }

        // Validate CRC
        if verifyCRC {
            try decoder.validateCRC()
        }

        return messages
    }

    // MARK: - Decoder state

    private struct DecoderState {
        let data: Data
        var position = 0
        var definitions: [Int: Definition] = [:]
        var dataEnd = 0
        var fileCrc: UInt16 = 0

        init(data: Data) {
            self.data = data
        }

        mutating func advance(_ n: Int) {
            position += n
        }

        func peekByte() throws -> UInt8 {
            guard position < data.count else { throw DecoderError.truncated }
            return data[position]
        }

        mutating func readByte() throws -> UInt8 {
            guard position < data.count else { throw DecoderError.truncated }
            let b = data[position]
            position += 1
            return b
        }

        mutating func readBytes(_ n: Int) throws -> Data {
            guard n >= 0, position + n <= data.count else { throw DecoderError.truncated }
            let end = position + n
            var result = Data(capacity: n)
            for i in position..<end {
                result.append(data[i])
            }
            position += n
            return result
        }

        // Little-endian reads (FIT uses little-endian by default)
        mutating func readUInt16(le: Bool = true) throws -> UInt16 {
            let bytes = try readBytes(2)
            return le
                ? UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
                : UInt16(bytes[1]) | (UInt16(bytes[0]) << 8)
        }

        mutating func readUInt32(le: Bool = true) throws -> UInt32 {
            let bytes = try readBytes(4)
            if le {
                return UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            }
            return UInt32(bytes[3]) | (UInt32(bytes[2]) << 8) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[0]) << 24)
        }

        mutating func readUInt64(le: Bool = true) throws -> UInt64 {
            let bytes = try readBytes(8)
            if le {
                return UInt64(bytes[0]) | (UInt64(bytes[1]) << 8) | (UInt64(bytes[2]) << 16) | (UInt64(bytes[3]) << 24)
                    | (UInt64(bytes[4]) << 32) | (UInt64(bytes[5]) << 40) | (UInt64(bytes[6]) << 48) | (UInt64(bytes[7]) << 56)
            }
            return UInt64(bytes[7]) | (UInt64(bytes[6]) << 8) | (UInt64(bytes[5]) << 16) | (UInt64(bytes[4]) << 24)
                | (UInt64(bytes[3]) << 32) | (UInt64(bytes[2]) << 40) | (UInt64(bytes[1]) << 48) | (UInt64(bytes[0]) << 56)
        }

        // MARK: - File header

        mutating func parseHeader() throws {
            guard data.count >= 12 else { throw DecoderError.invalidFile }
            let headerSize = try readByte()
            let _ = try readByte()  // protocol version
            let _ = try readUInt16()  // profile version
            let dataSize = try readUInt32()
            let dataType = try readBytes(4)

            guard dataType == Data([0x2E, 0x46, 0x49, 0x54]) else {  // ".FIT"
                throw DecoderError.invalidFile
            }

            // Skip optional CRC in header
            if headerSize == 14 {
                let _ = try readUInt16()
            }

            dataEnd = position + Int(dataSize)
            guard dataEnd + 2 <= data.count else { throw DecoderError.truncated }
        }

        // MARK: - Definition messages

        mutating func decodeDefinition() throws {
            let header = try readByte()  // 0x4X
            let localNum = Int(header & 0x0F)
            let hasDevData = (header & 0x20) != 0
            let _ = try readByte()  // reserved
            let architecture = try readByte()
            let isLE = (architecture == 0)
            let globalNum = try readUInt16(le: isLE)
            let numFields = Int(try readByte())

            var fieldDefs: [FieldDef] = []
            for _ in 0..<numFields {
                let fn = try readByte()
                let fs = try readByte()
                let bt = try readByte()
                fieldDefs.append(FieldDef(num: fn, size: fs, baseType: bt))
            }

            // Skip developer fields if present
            var devFieldDefs: [FieldDef] = []
            if hasDevData {
                let numDevFields = Int(try readByte())
                for _ in 0..<numDevFields {
                    let fn = try readByte()
                    let fs = try readByte()
                    let _ = try readByte()  // dev data index
                    devFieldDefs.append(FieldDef(num: fn, size: fs, baseType: 0))
                }
            }

            definitions[localNum] = Definition(
                localMessageNum: localNum,
                globalMessageNumber: globalNum,
                architecture: isLE ? 0 : 1,
                fieldDefs: fieldDefs,
                devFieldDefs: devFieldDefs)
        }

        // MARK: - Data messages

        mutating func decodeDataMessage(_ messages: inout [RawMessage]) throws {
            let header = try readByte()
            let localNum = Int(header & 0x0F)

            guard let def = definitions[localNum] else {
                throw DecoderError.unknownDefinition(localNum: localNum)
            }

            let isLE = (def.architecture == 0)
            var rawMsg = RawMessage(globalMessageNumber: def.globalMessageNumber)

            for fd in def.fieldDefs {
                let fieldBytes = try readBytes(Int(fd.size))
                let value = decodeField(fieldBytes, baseType: fd.baseType, le: isLE)
                rawMsg.fields[Int(fd.num)] = value
            }

            // Read and skip developer field data
            for fd in def.devFieldDefs {
                let _ = try readBytes(Int(fd.size))
            }

            messages.append(rawMsg)
        }

        // MARK: - Compressed timestamp messages

        mutating func decodeCompressedTimestampMessage(_ messages: inout [RawMessage]) throws {
            // Compressed timestamp header:
            // bits 7-6 = 11 (compressed timestamp marker)
            // bit 5 = local_mesg_num (only 1 bit, so 0 or 1)
            // bits 4-0 = time_offset
            let header = try readByte()
            let localNum = Int((header >> 5) & 0x01)
            let _ = (header & 0x1F)  // time offset 5 bits

            guard let def = definitions[localNum] else {
                throw DecoderError.unknownDefinition(localNum: localNum)
            }

            let isLE = (def.architecture == 0)
            var rawMsg = RawMessage(globalMessageNumber: def.globalMessageNumber)

            for fd in def.fieldDefs {
                let fieldBytes = try readBytes(Int(fd.size))
                let value = decodeField(fieldBytes, baseType: fd.baseType, le: isLE)
                rawMsg.fields[Int(fd.num)] = value
            }

            // Read and skip developer field data
            for fd in def.devFieldDefs {
                let _ = try readBytes(Int(fd.size))
            }

            messages.append(rawMsg)
        }

        // MARK: - CRC validation

        mutating func validateCRC() throws {
            guard dataEnd + 2 <= data.count else { throw DecoderError.truncated }
            fileCrc = try readUInt16(le: true)

            // The file CRC is computed over the header + data (everything before the CRC bytes)
            var crcData = Data(capacity: dataEnd)
            for i in 0..<dataEnd {
                crcData.append(data[i])
            }
            let calculated = crcCalculator(data: crcData)
            if calculated != fileCrc {
                throw DecoderError.crcMismatch(computed: calculated, stored: fileCrc)
            }
        }

        // MARK: - Field value decoding

        private func decodeField(_ bytes: Data, baseType: UInt8, le: Bool) -> Any {
            let bt = baseType & 0x1F  // lower 5 bits = actual base type

            // Handle arrays by checking if size > base type size
            let baseSize = baseTypeSize(bt)
            let isArray = bytes.count > baseSize && baseSize > 0

            if isArray {
                var values: [Any] = []
                var offset = 0
                while offset + baseSize <= bytes.count {
                    let chunk = bytes[offset..<offset + baseSize]
                    values.append(decodeSingle(chunk, baseType: bt, le: le))
                    offset += baseSize
                }
                // For strings, join into one string
                if bt == 7 {
                    var str = ""
                    for v in values {
                        if let s = v as? String { str += s }
                    }
                    return str
                }
                return values
            }

            return decodeSingle(bytes, baseType: bt, le: le)
        }

        private func decodeSingle(_ bytes: Data, baseType: UInt8, le: Bool) -> Any {
            switch baseType {
            case 0:  // enum
                return bytes.first ?? 0
            case 1:  // sint8
                let val = Int8(bitPattern: bytes.first ?? 0)
                if val == Int8(0x7F) { return val }
                return val
            case 2:  // uint8
                return bytes.first ?? 0
            case 3:  // sint16
                let val = le
                    ? Int16(bytes[safe: 0] ?? 0) | (Int16(bytes[safe: 1] ?? 0) << 8)
                    : Int16(bytes[safe: 1] ?? 0) | (Int16(bytes[safe: 0] ?? 0) << 8)
                if val == Int16(0x7FFF) { return val }
                return val
            case 4:  // uint16
                let val = le
                    ? UInt16(bytes[safe: 0] ?? 0) | (UInt16(bytes[safe: 1] ?? 0) << 8)
                    : UInt16(bytes[safe: 1] ?? 0) | (UInt16(bytes[safe: 0] ?? 0) << 8)
                return val
            case 5:  // sint32
                let val: Int32
                if le {
                    val = Int32(bytes[safe: 0] ?? 0) | (Int32(bytes[safe: 1] ?? 0) << 8)
                        | (Int32(bytes[safe: 2] ?? 0) << 16) | (Int32(bytes[safe: 3] ?? 0) << 24)
                }
                else {
                    val = Int32(bytes[safe: 3] ?? 0) | (Int32(bytes[safe: 2] ?? 0) << 8)
                        | (Int32(bytes[safe: 1] ?? 0) << 16) | (Int32(bytes[safe: 0] ?? 0) << 24)
                }
                return val
            case 6:  // uint32
                let val: UInt32
                if le {
                    val = UInt32(bytes[safe: 0] ?? 0) | (UInt32(bytes[safe: 1] ?? 0) << 8)
                        | (UInt32(bytes[safe: 2] ?? 0) << 16) | (UInt32(bytes[safe: 3] ?? 0) << 24)
                }
                else {
                    val = UInt32(bytes[safe: 3] ?? 0) | (UInt32(bytes[safe: 2] ?? 0) << 8)
                        | (UInt32(bytes[safe: 1] ?? 0) << 16) | (UInt32(bytes[safe: 0] ?? 0) << 24)
                }
                return val
            case 7:  // string (null-terminated)
                // Find null terminator
                var strBytes: [UInt8] = []
                for byte in bytes {
                    if byte == 0 { break }
                    strBytes.append(byte)
                }
                return String(bytes: strBytes, encoding: .utf8) ?? ""
            case 8:  // float32
                let raw: UInt32
                if le {
                    raw = UInt32(bytes[safe: 0] ?? 0) | (UInt32(bytes[safe: 1] ?? 0) << 8)
                        | (UInt32(bytes[safe: 2] ?? 0) << 16) | (UInt32(bytes[safe: 3] ?? 0) << 24)
                }
                else {
                    raw = UInt32(bytes[safe: 3] ?? 0) | (UInt32(bytes[safe: 2] ?? 0) << 8)
                        | (UInt32(bytes[safe: 1] ?? 0) << 16) | (UInt32(bytes[safe: 0] ?? 0) << 24)
                }
                return Float32(bitPattern: raw)
            case 9:  // float64
                let raw: UInt64
                if le {
                    raw = UInt64(bytes[safe: 0] ?? 0) | (UInt64(bytes[safe: 1] ?? 0) << 8)
                        | (UInt64(bytes[safe: 2] ?? 0) << 16) | (UInt64(bytes[safe: 3] ?? 0) << 24)
                        | (UInt64(bytes[safe: 4] ?? 0) << 32) | (UInt64(bytes[safe: 5] ?? 0) << 40)
                        | (UInt64(bytes[safe: 6] ?? 0) << 48) | (UInt64(bytes[safe: 7] ?? 0) << 56)
                }
                else {
                    raw = UInt64(bytes[safe: 7] ?? 0) | (UInt64(bytes[safe: 6] ?? 0) << 8)
                        | (UInt64(bytes[safe: 5] ?? 0) << 16) | (UInt64(bytes[safe: 4] ?? 0) << 24)
                        | (UInt64(bytes[safe: 3] ?? 0) << 32) | (UInt64(bytes[safe: 2] ?? 0) << 40)
                        | (UInt64(bytes[safe: 1] ?? 0) << 48) | (UInt64(bytes[safe: 0] ?? 0) << 56)
                }
                return Float64(bitPattern: raw)
            default:
                return Int(bytes.first ?? 0)
            }
        }

        private func baseTypeSize(_ baseType: UInt8) -> Int {
            switch baseType {
            case 0, 1, 2, 10, 13: return 1
            case 3, 4, 11: return 2
            case 5, 6, 8, 12: return 4
            case 7: return 1  // string, each char is 1 byte
            case 9, 14, 15, 16: return 8
            default: return 1
            }
        }
    }

    // MARK: - CRC16 (CRC-16/ARC: poly=0x8005, reflected, init=0)

    private static func crcCalculator(data: Data) -> UInt16 {
        var crc: UInt16 = 0
        for i in 0..<data.count {
            crc ^= UInt16(data[i])
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

    // MARK: - Error

    enum DecoderError: Swift.Error, LocalizedError {
        case invalidFile
        case truncated
        case unknownDefinition(localNum: Int)
        case crcMismatch(computed: UInt16, stored: UInt16)

        var errorDescription: String? {
            switch self {
            case .invalidFile: "Not a valid FIT file"
            case .truncated: "FIT file is truncated"
            case .unknownDefinition(let n): "No message definition found for local message type \(n)"
            case .crcMismatch(let c, let s): "CRC mismatch: computed \(c), stored \(s)"
            }
        }
    }

}

// MARK: - Safe array access

private extension Data {
    subscript(safe index: Int) -> UInt8? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
