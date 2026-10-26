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

        /// The decoded fields in definition order, each carrying its field
        /// number, base type and decoded value. Preserving order and base
        /// type allows a lossless re-encode of the message.
        var orderedFields: [RawField] = []
    }

    /// A decoded field in definition order: field number, base type and value.
    struct RawField {
        var num: UInt8
        var baseType: UInt8
        var value: Any
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
    /// - Parameter verifyHeaderCRC: If `true`, validates a non-zero header CRC
    ///   in a 14-byte header (default).
    /// - Returns: All decoded data messages in file order.
    static func decode(
        data: Data,
        verifyCRC: Bool = true,
        verifyHeaderCRC: Bool = true
    ) throws -> [RawMessage] {
        var decoder = DecoderState(data: data)
        try decoder.parseHeader(verifyHeaderCRC: verifyHeaderCRC)
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

        try decoder.validateCRC(enabled: verifyCRC)

        return messages
    }

    // MARK: - Decoder state

    private struct DecoderState {
        let data: Data
        var position = 0
        var definitions: [Int: Definition] = [:]
        var dataEnd = 0
        var fileCrc: UInt16 = 0

        /// The last valid timestamp encountered. Compressed-timestamp
        /// messages store only the low 5 bits of their timestamp, which are
        /// resolved relative to this value.
        var lastTimestamp: UInt32?

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

        mutating func parseHeader(verifyHeaderCRC: Bool) throws {
            guard data.count >= 12 else { throw DecoderError.invalidFile }
            let headerSize = try readByte()
            guard headerSize == 12 || headerSize == 14 else {
                throw DecoderError.invalidHeaderSize(Int(headerSize))
            }
            let _ = try readByte()  // protocol version
            let _ = try readUInt16()  // profile version
            let dataSize = try readUInt32()
            let dataType = try readBytes(4)

            guard dataType == Data([0x2E, 0x46, 0x49, 0x54]) else {  // ".FIT"
                throw DecoderError.invalidFile
            }

            if headerSize == 14 {
                let stored = try readUInt16()
                // A zero header CRC is occasionally written by devices that
                // treat the field as optional. Do not reject such files.
                if verifyHeaderCRC, stored != 0 {
                    let computed = FITCRC.crc16(data, range: 0..<12)
                    if computed != stored {
                        throw DecoderError.headerCRCMismatch(computed: computed, stored: stored)
                    }
                }
            }

            dataEnd = position + Int(dataSize)
            guard dataEnd >= position, dataEnd + 2 <= data.count else { throw DecoderError.truncated }
        }

        // MARK: - Definition messages

        mutating func decodeDefinition() throws {
            let header = try readByte()  // 0x4X
            let localNum = Int(header & 0x0F)
            let hasDevData = (header & 0x20) != 0
            let _ = try readByte()  // reserved
            let architecture = try readByte()
            guard architecture == 0 || architecture == 1 else {
                throw DecoderError.invalidArchitecture(architecture)
            }
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

            // Read developer field definitions. The data itself is skipped
            // when decoding data messages; it is not exposed through the
            // typed API.
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

            let rawMsg = try decodeFields(def: def, compressedTimestampOffset: nil)
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
            let timeOffset = header & 0x1F

            guard let def = definitions[localNum] else {
                throw DecoderError.unknownDefinition(localNum: localNum)
            }

            let rawMsg = try decodeFields(def: def, compressedTimestampOffset: timeOffset)
            messages.append(rawMsg)
        }

        /// Decodes the fields of one data message.
        ///
        /// For compressed-timestamp messages the definition's first field must
        /// be the 4-byte timestamp field. Its bytes are *not* present in the
        /// data message; instead the timestamp is reconstructed from the last
        /// valid timestamp and the 5-bit time offset.
        private mutating func decodeFields(
            def: Definition,
            compressedTimestampOffset: UInt8?
        ) throws -> RawMessage {
            let isLE = (def.architecture == 0)
            var rawMsg = RawMessage(globalMessageNumber: def.globalMessageNumber)

            if let timeOffset = compressedTimestampOffset {
                guard let first = def.fieldDefs.first,
                      first.num == 253,
                      first.size == 4
                else {
                    throw DecoderError.compressedTimestampWithoutTimestamp
                }
                guard let reference = lastTimestamp else {
                    throw DecoderError.compressedTimestampWithoutReference
                }

                // The timestamp is the reference timestamp with its low five
                // bits replaced by the offset. If that wraps below the
                // reference, the timestamp belongs to the next 32-second
                // window.
                var timestamp = (reference & 0xFFFFFFE0) | UInt32(timeOffset)
                if timestamp < reference {
                    let (next, overflow) = timestamp.addingReportingOverflow(0x20)
                    timestamp = overflow ? UInt32.max : next
                }
                rawMsg.fields[253] = timestamp
                rawMsg.orderedFields.append(RawField(num: 253, baseType: first.baseType, value: timestamp))
                lastTimestamp = timestamp

                for fd in def.fieldDefs.dropFirst() {
                    let fieldBytes = try readBytes(Int(fd.size))
                    if let value = decodeField(fieldBytes, baseType: fd.baseType, le: isLE) {
                        rawMsg.fields[Int(fd.num)] = value
                        rawMsg.orderedFields.append(RawField(num: fd.num, baseType: fd.baseType, value: value))
                        trackTimestamp(fieldNum: fd.num, size: fd.size, value: value)
                    }
                }
            }
            else {
                for fd in def.fieldDefs {
                    let fieldBytes = try readBytes(Int(fd.size))
                    if let value = decodeField(fieldBytes, baseType: fd.baseType, le: isLE) {
                        rawMsg.fields[Int(fd.num)] = value
                        rawMsg.orderedFields.append(RawField(num: fd.num, baseType: fd.baseType, value: value))
                        trackTimestamp(fieldNum: fd.num, size: fd.size, value: value)
                    }
                }
            }

            // Read and skip developer field data.
            for fd in def.devFieldDefs {
                let _ = try readBytes(Int(fd.size))
            }

            return rawMsg
        }

        private mutating func trackTimestamp(fieldNum: UInt8, size: UInt8, value: Any) {
            guard fieldNum == 253, size == 4, let timestamp = value as? UInt32 else { return }
            lastTimestamp = timestamp
        }

        // MARK: - CRC validation

        mutating func validateCRC(enabled: Bool) throws {
            guard dataEnd + 2 <= data.count else { throw DecoderError.truncated }
            fileCrc = try readUInt16(le: true)

            guard enabled else { return }

            // The file CRC is computed over the header + data (everything before the CRC bytes).
            let calculated = FITCRC.crc16(data, range: 0..<dataEnd)
            if calculated != fileCrc {
                throw DecoderError.crcMismatch(computed: calculated, stored: fileCrc)
            }
        }

        // MARK: - Field value decoding

        private func decodeField(_ bytes: Data, baseType: UInt8, le: Bool) -> Any? {
            let bt = baseType & 0x1F  // lower 5 bits = actual base type

            guard !bytes.isEmpty else { return nil }

            // Strings are variable-length and are not split into elements.
            if bt == 7 {
                return decodeSingle(bytes, baseType: bt, le: le)
            }

            let baseSize = baseTypeSize(bt)
            guard baseSize > 0 else { return nil }

            if bytes.count > baseSize {
                var values: [Any] = []
                var offset = 0
                while offset + baseSize <= bytes.count {
                    let chunk = Data(bytes[offset..<offset + baseSize])
                    if let value = decodeSingle(chunk, baseType: bt, le: le) {
                        values.append(value)
                    }
                    offset += baseSize
                }
                return values.isEmpty ? nil : values
            }

            return decodeSingle(bytes, baseType: bt, le: le)
        }

        private func decodeSingle(_ bytes: Data, baseType: UInt8, le: Bool) -> Any? {
            switch baseType {
            case 0:  // enum
                let value = bytes.first ?? 0xFF
                return value == 0xFF ? nil : value
            case 1:  // sint8
                let value = Int8(bitPattern: bytes.first ?? 0x7F)
                return value == Int8(0x7F) ? nil : value
            case 2:  // uint8
                let value = bytes.first ?? 0xFF
                return value == 0xFF ? nil : value
            case 3:  // sint16
                let raw = readUInt16(bytes, le: le)
                let value = Int16(bitPattern: raw)
                return value == Int16(0x7FFF) ? nil : value
            case 4:  // uint16
                let value = readUInt16(bytes, le: le)
                return value == UInt16.max ? nil : value
            case 5:  // sint32
                let raw = readUInt32(bytes, le: le)
                let value = Int32(bitPattern: raw)
                return value == Int32(0x7FFF_FFFF) ? nil : value
            case 6:  // uint32
                let value = readUInt32(bytes, le: le)
                return value == UInt32.max ? nil : value
            case 7:  // string (null-terminated)
                var strBytes: [UInt8] = []
                for byte in bytes {
                    if byte == 0 { break }
                    strBytes.append(byte)
                }
                guard !strBytes.isEmpty else { return nil }
                return String(bytes: strBytes, encoding: .utf8) ?? ""
            case 8:  // float32
                let raw = readUInt32(bytes, le: le)
                guard raw != UInt32.max else { return nil }
                return Float32(bitPattern: raw)
            case 9:  // float64
                let raw = readUInt64(bytes, le: le)
                guard raw != UInt64.max else { return nil }
                return Float64(bitPattern: raw)
            case 10:  // uint8z
                let value = bytes.first ?? 0
                return value == 0 ? nil : value
            case 11:  // uint16z
                let value = readUInt16(bytes, le: le)
                return value == 0 ? nil : value
            case 12:  // uint32z
                let value = readUInt32(bytes, le: le)
                return value == 0 ? nil : value
            case 13:  // byte
                let value = bytes.first ?? 0xFF
                return value == 0xFF ? nil : value
            case 14:  // sint64
                let raw = readUInt64(bytes, le: le)
                let value = Int64(bitPattern: raw)
                return value == Int64.max ? nil : value
            case 15:  // uint64
                let value = readUInt64(bytes, le: le)
                return value == UInt64.max ? nil : value
            case 16:  // uint64z
                let value = readUInt64(bytes, le: le)
                return value == 0 ? nil : value
            default:
                return Int(bytes.first ?? 0)
            }
        }

        private func readUInt16(_ bytes: Data, le: Bool) -> UInt16 {
            let b0 = bytes[safe: 0] ?? 0
            let b1 = bytes[safe: 1] ?? 0
            return le
                ? UInt16(b0) | (UInt16(b1) << 8)
                : UInt16(b1) | (UInt16(b0) << 8)
        }

        private func readUInt32(_ bytes: Data, le: Bool) -> UInt32 {
            let b0 = UInt32(bytes[safe: 0] ?? 0)
            let b1 = UInt32(bytes[safe: 1] ?? 0)
            let b2 = UInt32(bytes[safe: 2] ?? 0)
            let b3 = UInt32(bytes[safe: 3] ?? 0)
            return le
                ? b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
                : b3 | (b2 << 8) | (b1 << 16) | (b0 << 24)
        }

        private func readUInt64(_ bytes: Data, le: Bool) -> UInt64 {
            if le {
                var value: UInt64 = 0
                for index in 0..<8 {
                    value |= UInt64(bytes[safe: index] ?? 0) << (UInt64(index) * 8)
                }
                return value
            }
            var value: UInt64 = 0
            for index in 0..<8 {
                value |= UInt64(bytes[safe: 7 - index] ?? 0) << (UInt64(index) * 8)
            }
            return value
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

    // MARK: - Error

    enum DecoderError: Swift.Error, LocalizedError {
        case invalidFile
        case invalidHeaderSize(Int)
        case invalidArchitecture(UInt8)
        case truncated
        case unknownDefinition(localNum: Int)
        case crcMismatch(computed: UInt16, stored: UInt16)
        case headerCRCMismatch(computed: UInt16, stored: UInt16)
        case compressedTimestampWithoutTimestamp
        case compressedTimestampWithoutReference

        var errorDescription: String? {
            switch self {
            case .invalidFile: "Not a valid FIT file"
            case .invalidHeaderSize(let size): "Invalid FIT header size \(size); expected 12 or 14 bytes"
            case .invalidArchitecture(let value): "Invalid FIT architecture byte \(value); expected 0 (little-endian) or 1 (big-endian)"
            case .truncated: "FIT file is truncated"
            case .unknownDefinition(let n): "No message definition found for local message type \(n)"
            case .crcMismatch(let c, let s): "CRC mismatch: computed \(c), stored \(s)"
            case .headerCRCMismatch(let c, let s): "Header CRC mismatch: computed \(c), stored \(s)"
            case .compressedTimestampWithoutTimestamp:
                "Compressed timestamp message requires the timestamp field (253) as the first field of its definition"
            case .compressedTimestampWithoutReference:
                "Compressed timestamp message has no preceding timestamp to resolve against"
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
