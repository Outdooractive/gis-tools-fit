import Foundation

// MARK: - FIT Write Options

/// Options that control how a FIT file is encoded.
public struct FITWriteOptions: Sendable, Equatable {

    /// The FIT protocol version written into the file header.
    ///
    /// Defaults to `0x20` (FIT 2.0).
    public var protocolVersion: UInt8

    /// The FIT profile version written into the file header.
    ///
    /// Defaults to `2100`.
    public var profileVersion: UInt16

    /// Whether to write a 14-byte header including a header CRC.
    ///
    /// Defaults to `false`, which writes a 12-byte header. The file CRC is
    /// always written.
    public var includeHeaderCRC: Bool

    /// Creates FIT write options.
    ///
    /// - Parameters:
    ///   - protocolVersion: The protocol version (default `0x20`).
    ///   - profileVersion: The profile version (default `2100`).
    ///   - includeHeaderCRC: Whether to include a header CRC (default `false`).
    public init(
        protocolVersion: UInt8 = 0x20,
        profileVersion: UInt16 = 2100,
        includeHeaderCRC: Bool = false
    ) {
        self.protocolVersion = protocolVersion
        self.profileVersion = profileVersion
        self.includeHeaderCRC = includeHeaderCRC
    }

}
