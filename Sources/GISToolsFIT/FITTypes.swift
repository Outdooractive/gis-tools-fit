import Foundation
import GISTools

// MARK: - FIT Coder Error

/// Errors thrown by FIT reading and writing operations.
public enum FITError: LocalizedError, Equatable {

    /// The file could not be read.
    case fileReadError(detail: String)

    /// The file could not be written.
    case fileWriteError(detail: String)

    /// The file is not a valid FIT file.
    case invalidFile(detail: String)

    /// The FIT file could not be parsed.
    case parseError(detail: String)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .fileReadError(let d): "Could not read FIT file: \(d)"
        case .fileWriteError(let d): "Could not write FIT file: \(d)"
        case .invalidFile(let d): "Invalid FIT file: \(d)"
        case .parseError(let d): "FIT parse error: \(d)"
        }
    }
}

// MARK: - FIT Record Type

/// The kind of FIT record represented by a Feature.
public enum FITRecordType: String, Equatable, Sendable {

    /// A GPS track point (record message).
    case record

    /// A lap segment.
    case lap

    /// A session summary.
    case session

    /// A file-identifying message.
    case fileId

    /// An event marker.
    case event

    /// An activity summary.
    case activity

}

// MARK: - Semicircle conversion

/// FIT math and conversion helpers.
public enum FIT {

    /// The FIT epoch: 1989-12-31T00:00:00Z.
    /// FIT timestamps are seconds since this date.
    /// `631065600` is the number of seconds between 1970-01-01T00:00:00Z
    /// (the Unix epoch) and the FIT epoch. Hard-coding the interval (rather
    /// than building a `Date` from `DateComponents`) makes the value
    /// independent of the process's local time zone.
    public static let epoch: Date = Date(timeIntervalSince1970: 631065600)

    /// The number of semicircles in one degree: `2^31 / 180`.
    public static let semicirclesPerDegree: Double = 2147483648.0 / 180.0

    /// Converts a FIT timestamp (seconds since FIT epoch) to a Date.
    public static func dateFromTimestamp(_ timestamp: UInt32) -> Date {
        epoch.addingTimeInterval(TimeInterval(timestamp))
    }

    /// Converts a Date to a FIT timestamp (seconds since FIT epoch).
    ///
    /// Values outside the range of a `UInt32` are clamped.
    public static func timestamp(from date: Date) -> UInt32 {
        let seconds = (date.timeIntervalSince(epoch)).rounded()
        guard seconds > 0 else { return 0 }
        guard seconds < Double(UInt32.max) else { return UInt32.max - 1 }
        return UInt32(seconds)
    }

    /// Parses an ISO 8601 date string.
    ///
    /// Both fractional-second and whole-second representations are accepted,
    /// so values written by this package and by other tools can be read.
    ///
    /// - Parameter string: The ISO 8601 date string.
    /// - Returns: The parsed date, or `nil` when the string is invalid.
    public static func date(fromISO8601 string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Converts a Date to an ISO8601 string (with fractional seconds).
    public static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Converts a FIT semicircle value to decimal degrees.
    /// - Parameter semicircles: The raw semicircle value (sint32).
    /// - Returns: Degrees in WGS84.
    public static func degreesFromSemicircles(_ semicircles: Int32) -> Double {
        Double(semicircles) / semicirclesPerDegree
    }

    /// Converts decimal degrees to a FIT semicircle value.
    ///
    /// The value is rounded to the nearest semicircle and clamped to the
    /// representable `sint32` range.
    ///
    /// - Parameter degrees: The latitude or longitude in WGS84.
    /// - Returns: The raw semicircle value (sint32).
    public static func semicirclesFromDegrees(_ degrees: Double) -> Int32 {
        guard degrees.isFinite else { return 0 }
        let scaled = (degrees * semicirclesPerDegree).rounded()
        let clamped = max(Double(Int32.min), min(Double(Int32.max), scaled))
        return Int32(clamped)
    }

}
