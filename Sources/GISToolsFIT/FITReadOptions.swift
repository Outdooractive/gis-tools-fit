import Foundation

// MARK: - FIT Read Options

/// Options that control how a FIT file is decoded.
public struct FITReadOptions: Sendable, Equatable {

    /// Whether to validate the file CRC.
    ///
    /// Defaults to `true`. Disable this only for known-corrupt files or while
    /// debugging a file that is still being written.
    public var verifyCRC: Bool

    /// Whether to validate the optional header CRC when a 14-byte header is
    /// present and its CRC field is non-zero.
    ///
    /// Defaults to `true`.
    public var verifyHeaderCRC: Bool

    /// Creates FIT read options.
    ///
    /// - Parameters:
    ///   - verifyCRC: Whether to validate the file CRC (default `true`).
    ///   - verifyHeaderCRC: Whether to validate the header CRC (default `true`).
    public init(
        verifyCRC: Bool = true,
        verifyHeaderCRC: Bool = true
    ) {
        self.verifyCRC = verifyCRC
        self.verifyHeaderCRC = verifyHeaderCRC
    }

}
