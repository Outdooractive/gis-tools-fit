import Foundation
@testable import GISToolsFIT

/// Small builders for synthetic FIT files used by the tests.
enum FITTestBuilder {

    // MARK: - Primitive encoding

    static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    static func be16(_ value: UInt16) -> Data {
        Data([UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)])
    }

    static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ])
    }

    static func be32(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ])
    }

    static func le64(_ value: UInt64) -> Data {
        Data((0..<8).map { UInt8((value >> (UInt64($0) * 8)) & 0xFF) })
    }

    static func be64(_ value: UInt64) -> Data {
        Data((0..<8).map { UInt8((value >> (UInt64(7 - $0) * 8)) & 0xFF) })
    }

    static func sint32(_ value: Int32) -> Data {
        le32(UInt32(bitPattern: value))
    }

    static func semicircles(_ degrees: Double) -> Int32 {
        FIT.semicirclesFromDegrees(degrees)
    }

    static func crc16(_ data: Data) -> UInt16 {
        FITCRC.crc16(data)
    }

    // MARK: - Messages

    static func definition(
        local: Int,
        global: UInt16,
        fields: [(num: UInt8, size: UInt8, baseType: UInt8)],
        developerFields: [(num: UInt8, size: UInt8, devDataIndex: UInt8)] = [],
        architecture: UInt8 = 0
    ) -> Data {
        var data = Data()
        var header: UInt8 = 0x40 | UInt8(local & 0x0F)
        if !developerFields.isEmpty {
            header |= 0x20
        }
        data.append(header)
        data.append(0x00)  // reserved
        data.append(architecture)
        data.append(architecture == 0 ? le16(global) : be16(global))
        data.append(UInt8(fields.count))
        for field in fields {
            data.append(field.num)
            data.append(field.size)
            data.append(field.baseType)
        }
        if !developerFields.isEmpty {
            data.append(UInt8(developerFields.count))
            for field in developerFields {
                data.append(field.num)
                data.append(field.size)
                data.append(field.devDataIndex)
            }
        }
        return data
    }

    static func dataHeader(local: Int) -> UInt8 {
        UInt8(local & 0x0F)
    }

    static func compressedHeader(local: Int, offset: UInt8) -> UInt8 {
        0xC0 | (UInt8(local & 0x01) << 5) | (offset & 0x1F)
    }

    // MARK: - File assembly

    static func file(
        body: Data,
        includeHeaderCRC: Bool = false,
        protocolVersion: UInt8 = 0x20,
        profileVersion: UInt16 = 2100
    ) -> Data {
        var data = Data()
        data.append(includeHeaderCRC ? 14 : 12)
        data.append(protocolVersion)
        data.append(UInt8(profileVersion & 0xFF))
        data.append(UInt8((profileVersion >> 8) & 0xFF))
        data.append(le32(UInt32(body.count)))
        data.append(contentsOf: [0x2E, 0x46, 0x49, 0x54])
        if includeHeaderCRC {
            data.append(le16(crc16(data)))
        }
        data.append(body)
        data.append(le16(crc16(data)))
        return data
    }

}
