import Foundation

// MARK: - FIT CRC

/// CRC-16/ARC as used by the FIT protocol.
///
/// The algorithm is the Dynastream CRC-16: polynomial `0x8005`, reflected,
/// initial value `0`, no final XOR. The same checksum is used for the optional
/// header CRC and for the file CRC.
enum FITCRC {

    /// Computes the CRC-16/ARC checksum of a data buffer.
    ///
    /// - Parameter data: The bytes to checksum.
    /// - Returns: The 16-bit checksum.
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

    /// Computes the CRC-16/ARC checksum over a range of a data buffer.
    ///
    /// - Parameters:
    ///   - data: The bytes to checksum.
    ///   - range: The byte range to include.
    /// - Returns: The 16-bit checksum.
    static func crc16(_ data: Data, range: Range<Int>) -> UInt16 {
        var crc: UInt16 = 0
        for index in range {
            crc ^= UInt16(data[index])
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

}
