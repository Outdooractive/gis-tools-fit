import Foundation
import GISTools

// MARK: - FIT Coder Error

/// Errors thrown by FIT reading operations.
public enum FITError: LocalizedError {

    /// The file could not be read.
    case fileReadError(detail: String)

    /// The file is not a valid FIT file.
    case invalidFile(detail: String)

    /// The FIT file could not be parsed.
    case parseError(detail: String)

    /// A human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .fileReadError(let d): "Could not read FIT file: \(d)"
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

// MARK: - Known manufacturer and sport types

/// Manufacturer identifiers from the FIT Profile.
public enum FITManufacturer: UInt16, Equatable, Sendable {
    case garmin = 1
    case garminFr405 = 2
    case garminFr305 = 3
    case garminFr310xt = 4
    case garminFr405mx = 5
    case garminFr50 = 6
    case garminFr10 = 7
    case garminFr110 = 8
    case dynastream = 9
    case dynastreamOem = 10
    case polar = 12
    case suunto = 17
    case bryton = 20
    case wahooFitness = 26
    case stryd = 44
    case unknown = 0xFFFF

    public init(_ value: UInt16) {
        self = FITManufacturer(rawValue: value) ?? .unknown
    }
}

/// Sport types from the FIT Profile.
public enum FITSportType: UInt8, Equatable, Sendable {
    case generic = 0
    case running = 1
    case cycling = 2
    case swimming = 4
    case hiking = 7
    case walking = 9
    case unknown = 0xFF

    public init(_ value: UInt8) {
        self = FITSportType(rawValue: value) ?? .unknown
    }
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

    /// Converts a FIT timestamp (seconds since FIT epoch) to a Date.
    public static func dateFromTimestamp(_ timestamp: UInt32) -> Date {
        epoch.addingTimeInterval(TimeInterval(timestamp))
    }

    /// Converts a FIT semicircle value to decimal degrees.
    /// - Parameter semicircles: The raw semicircle value (sint32).
    /// - Returns: Degrees in WGS84.
    public static func degreesFromSemicircles(_ semicircles: Int32) -> Double {
        Double(semicircles) * (180.0 / 2147483648.0)
    }

    /// Converts decimal degrees to a FIT semicircle value.
    /// - Parameter degrees: The latitude or longitude in WGS84.
    /// - Returns: The raw semicircle value (sint32).
    public static func semicirclesFromDegrees(_ degrees: Double) -> Int32 {
        let scaled = degrees * (2147483648.0 / 180.0)
        let clamped = max(Double(Int32.min), min(Double(Int32.max), scaled))
        return Int32(clamped)
    }

}
