import Foundation
import GISTools

// MARK: - FeatureCollection convenience extensions

extension FeatureCollection {

    /// Creates a ``FeatureCollection`` from a FIT file.
    ///
    /// - Parameter fit: The URL of the FIT file.
    public init?(fit url: URL) {
        guard let fc = try? FITCoder.read(from: url) else { return nil }
        self = fc
    }

    /// Writes the receiver as a FIT file (not yet supported).
    public func writeFIT(to url: URL) throws {
        throw FITError.parseError(detail: "FIT writing is not yet supported")
    }

}

// MARK: - FITCoder

/// Reads FIT (Flexible and Interoperable Data Transfer) files.
///
/// FIT files contain fitness activity data recorded by GPS devices.
/// This coder maps them to a ``FeatureCollection`` with:
///
/// | FIT Message     | GeoJSON Geometry    | `fit_type` property |
/// |-----------------|---------------------|---------------------|
/// | Record (points) | `MultiLineString`   | `"record"`          |
/// | Lap             | (none, metadata)    | `"lap"`             |
/// | Session         | (none, metadata)    | `"session"`         |
/// | Event           | (none, metadata)    | `"event"`           |
/// | File ID         | (none, metadata)    | `"file_id"`         |
/// | Activity        | (none, metadata)    | `"activity"`        |
public enum FITCoder {

    /// Reads a FIT file and returns a ``FeatureCollection``.
    ///
    /// - Parameter url: The URL of the FIT file.
    /// - Returns: A ``FeatureCollection`` with the FIT data.
    /// - Throws: ``FITError`` if the file cannot be read or parsed.
    public static func read(from url: URL) throws -> FeatureCollection {
        let data = try Data(contentsOf: url)
        return try read(from: data)
    }

    /// Reads FIT data and returns a ``FeatureCollection``.
    ///
    /// - Parameter data: The binary FIT data.
    /// - Returns: A ``FeatureCollection`` with the FIT data.
    /// - Throws: ``FITError`` if the data cannot be parsed.
    public static func read(from data: Data) throws -> FeatureCollection {
        let rawMessages: [FITDecoder.RawMessage]
        do {
            rawMessages = try FITDecoder.decode(data: data)
        }
        catch let error as FITDecoder.DecoderError {
            throw FITError.parseError(detail: error.localizedDescription)
        }

        return convertToGeoJSON(rawMessages)
    }

    // MARK: - Conversion to GeoJSON

    private static func convertToGeoJSON(_ messages: [FITDecoder.RawMessage]) -> FeatureCollection {
        var recordPoints: [(lat: Int32, lon: Int32, fields: [Int: Any])] = []
        var lapStarts: [Int] = []
        var sessionMeta: [String: Sendable] = [:]
        var activityMeta: [String: Sendable] = [:]
        var deviceMeta: [String: Sendable] = [:]

        // Per-point sensor data arrays (parallel to recordPoints)
        var heartRates: [Int] = []
        var cadences: [Int] = []
        var powers: [Int] = []
        var speeds: [Double] = []
        var temperatures: [Double] = []
        var altitudes: [Double] = []
        var timestamps: [UInt32] = []

        for msg in messages {
            let messageType = FITProfile.MesgNum(msg.globalMessageNumber)
            switch messageType {
            case .record:
                guard let lat = msg.fields[0] as? Int32,
                      let lon = msg.fields[1] as? Int32
                else { break }
                recordPoints.append((lat, lon, msg.fields))

                // Extract per-point sensor data
                if let v = msg.fields[3] as? UInt8 { heartRates.append(Int(v)) }
                if let v = msg.fields[4] as? UInt8 { cadences.append(Int(v)) }
                if let v = msg.fields[7] as? UInt16 { powers.append(Int(v)) }
                if let v = msg.fields[6] as? UInt16 { speeds.append(Double(v) / 1000.0) }
                if let v = msg.fields[139] as? Int8 { temperatures.append(Double(v)) }
                if let v = msg.fields[2] as? UInt16 { altitudes.append(Double(v) / 5.0 - 500.0) }
                if let v = msg.fields[253] as? UInt32 { timestamps.append(v) }

            case .lap:
                lapStarts.append(recordPoints.count)

            case .session:
                sessionMeta = applyFields(msg.fields, mesgNum: messageType.rawValue)

            case .activity:
                activityMeta = applyFields(msg.fields, mesgNum: messageType.rawValue)

            case .fileId:
                deviceMeta = applyFields(msg.fields, mesgNum: messageType.rawValue)

            default:
                break
            }
        }

        // Build track Feature with MultiLineString
        var features: [Feature] = []
        if !recordPoints.isEmpty {
            let segments: [[Coordinate3D]] = buildSegments(recordPoints, lapStarts: lapStarts)
            let lineStrings = segments.map { LineString(unchecked: $0) }
            let multiLine = MultiLineString(unchecked: lineStrings)
            var feature = Feature(multiLine)
            feature.properties["fit_type"] = FITRecordType.record.rawValue
            if !sessionMeta.isEmpty {
                feature.properties.merge(sessionMeta) { (_, new) in new }
            }

            // Store per-point sensor arrays
            if !heartRates.isEmpty { feature.properties["fit_heart_rates"] = heartRates }
            if !cadences.isEmpty { feature.properties["fit_cadences"] = cadences }
            if !powers.isEmpty { feature.properties["fit_powers"] = powers }
            if !speeds.isEmpty { feature.properties["fit_speeds"] = speeds }
            if !temperatures.isEmpty { feature.properties["fit_temperatures"] = temperatures }
            if !altitudes.isEmpty { feature.properties["fit_altitudes"] = altitudes }
            if !timestamps.isEmpty { feature.properties["fit_timestamps"] = timestamps }

            features.append(feature)
        }

        // Merge metadata into foreign members
        var foreign: [String: Sendable] = [:]
        if !activityMeta.isEmpty { foreign["fit_activity"] = activityMeta as Sendable }
        if !deviceMeta.isEmpty { foreign["fit_device"] = deviceMeta as Sendable }

        // Build result (features is private(set), rebuild through init)
        var result = FeatureCollection(features)
        result.foreignMembers = foreign
        return result
    }

    // MARK: - Segment building

    private static func buildSegments(
        _ points: [(lat: Int32, lon: Int32, fields: [Int: Any])],
        lapStarts: [Int]
    ) -> [[Coordinate3D]] {
        // If there are lap markers, split points at lap boundaries
        var splitIndices = Set(lapStarts)
        splitIndices.insert(0)
        splitIndices.insert(points.count)

        let sorted = splitIndices.sorted()
        var segments: [[Coordinate3D]] = []

        for i in 0..<sorted.count - 1 {
            let start = sorted[i]
            let end = sorted[i + 1]
            guard end > start else { continue }

            let coords: [Coordinate3D] = points[start..<end].map { p in
                Coordinate3D(
                    x: FITDegreesFromSemicircles(p.lon),
                    y: FITDegreesFromSemicircles(p.lat),
                    projection: .epsg4326)
            }
            if !coords.isEmpty {
                segments.append(coords)
            }
        }

        return segments
    }

    // MARK: - Field conversion

    /// Converts raw field values to user-friendly values using the FIT Profile.
    private static func applyFields(_ fields: [Int: Any], mesgNum: UInt16 = 0) -> [String: Sendable] {
        var result: [String: Sendable] = [:]
        for (fieldNum, rawValue) in fields {
            guard let meta = FITProfile.fieldMetadata(mesgNum: mesgNum, fieldNum: fieldNum) else {
                // Store unknown fields with numeric keys
                result["field_\(fieldNum)"] = "\(rawValue)"
                continue
            }
            if let converted = meta.formatValue(rawValue) {
                result[meta.name] = asSendable(converted)
            }
        }
        return result
    }

    /// Wraps a value as `Sendable` for storage in `Feature.properties`.
    private static func asSendable(_ value: Any) -> Sendable {
        if let s = value as? String { return s }
        if let i = value as? Int { return i }
        if let d = value as? Double { return d }
        if let i64 = value as? Int64 { return i64 }
        if let b = value as? Bool { return b }
        if let u32 = value as? UInt32 { return Int(u32) }
        if let u16 = value as? UInt16 { return Int(u16) }
        if let u8 = value as? UInt8 { return Int(u8) }
        if let i16 = value as? Int16 { return Int(i16) }
        if let i8 = value as? Int8 { return Int(i8) }
        if let f = value as? Float { return Double(f) }
        return "\(value)"
    }

}
