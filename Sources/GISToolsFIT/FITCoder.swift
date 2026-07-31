import Foundation
import GISTools

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

    /// Reads Fit data and returns a ``FeatureCollection``.
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

    // MARK: - Writing

    /// Encodes a ``FeatureCollection`` into binary FIT data.
    ///
    /// The collection must contain a track `Feature` with a `MultiLineString`
    /// geometry and `fit_type == "record"`, as produced by ``read(from:)``.
    /// Per-point sensor arrays (`fit_heart_rates`, `fit_cadences`, etc.) and
    /// session/activity metadata stored on the `FeatureCollection` are
    /// written back into the corresponding FIT messages.
    ///
    /// - Parameter featureCollection: The feature collection to encode.
    /// - Returns: The binary FIT data.
    /// - Throws: ``FITError`` if the collection cannot be encoded.
    public static func write(from featureCollection: FeatureCollection) throws -> Data {
        do {
            let messages = try convertFromGeoJSON(featureCollection)
            return FITEncoder.encode(messages: messages)
        }
        catch let error as FITEncoder.EncoderError {
            throw FITError.invalidFile(detail: error.localizedDescription)
        }
        catch let error as FITError {
            throw error
        }
        catch {
            throw FITError.invalidFile(detail: "\(error)")
        }
    }

    /// Writes a ``FeatureCollection`` to a FIT file at the given URL.
    ///
    /// - Parameters:
    ///    - featureCollection: The feature collection to encode.
    ///    - url: The destination file URL.
    /// - Throws: ``FITError`` if encoding or file writing fails.
    public static func write(
        from featureCollection: FeatureCollection,
        to url: URL
    ) throws {
        let data = try write(from: featureCollection)
        try data.write(to: url)
    }

    // MARK: - Conversion to GeoJSON

    private static func convertToGeoJSON(_ messages: [FITDecoder.RawMessage]) -> FeatureCollection {
        var recordPoints: [(lat: Int32, lon: Int32, fields: [Int: Any])] = []
        var lapStarts: [Int] = []
        var sessionMeta: [String: Sendable] = [:]
        var activityMeta: [String: Sendable] = [:]
        var deviceMeta: [String: Sendable] = [:]

        // Per-point sensor data arrays (aligned to record order)
        var heartRates: [Int?] = []
        var cadences: [Int?] = []
        var powers: [Int?] = []
        var speeds: [Double?] = []
        var temperatures: [Double?] = []
        var altitudes: [Double?] = []
        var timestamps: [UInt32?] = []

        for msg in messages {
            let messageType = FITProfile.MesgNum(msg.globalMessageNumber)
            switch messageType {
            case .record:
                guard let lat = msg.fields[0] as? Int32,
                      let lon = msg.fields[1] as? Int32
                else { break }

                // FIT sentinel for invalid (no GPS fix): 0x7FFFFFFF
                guard lat != Int32.max, lon != Int32.max else { break }

                recordPoints.append((lat, lon, msg.fields))

                // Extract per-point sensor data — always append per record
                if let v = msg.fields[3] as? UInt8 { heartRates.append(Int(v)) }
                else { heartRates.append(nil) }
                if let v = msg.fields[4] as? UInt8 { cadences.append(Int(v)) }
                else { cadences.append(nil) }
                if let v = msg.fields[7] as? UInt16 { powers.append(Int(v)) }
                else { powers.append(nil) }
                if let v = msg.fields[6] as? UInt16 { speeds.append(Double(v) / 1000.0) }
                else { speeds.append(nil) }
                if let v = msg.fields[139] as? Int8 { temperatures.append(Double(v)) }
                else { temperatures.append(nil) }
                if let v = msg.fields[2] as? UInt16 { altitudes.append(Double(v) / 5.0 - 500.0) }
                else { altitudes.append(nil) }
                if let v = msg.fields[253] as? UInt32 { timestamps.append(v) }
                else { timestamps.append(nil) }

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
            let segments: [[Coordinate3D]] = buildSegments(recordPoints, altitudes: altitudes, lapStarts: lapStarts)
            let lineStrings = segments.map { LineString(unchecked: $0) }
            let multiLine = MultiLineString(unchecked: lineStrings)
            var feature = Feature(multiLine)
            feature.properties["fit_type"] = FITRecordType.record.rawValue
            if !sessionMeta.isEmpty {
                feature.properties.merge(sessionMeta) { (_, new) in new }
            }

            // Store per-point sensor arrays (only if at least one non-nil)
            if heartRates.contains(where: { $0 != nil }) { feature.properties["fit_heart_rates"] = heartRates }
            if cadences.contains(where: { $0 != nil }) { feature.properties["fit_cadences"] = cadences }
            if powers.contains(where: { $0 != nil }) { feature.properties["fit_powers"] = powers }
            if speeds.contains(where: { $0 != nil }) { feature.properties["fit_speeds"] = speeds }
            if temperatures.contains(where: { $0 != nil }) { feature.properties["fit_temperatures"] = temperatures }
            if timestamps.contains(where: { $0 != nil }) { feature.properties["fit_timestamps"] = timestamps }

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
        altitudes: [Double?],
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

            let coords: [Coordinate3D] = points[start..<end].enumerated().map { (i, p) in
                let alt = start + i < altitudes.count ? altitudes[start + i] : nil
                return Coordinate3D(
                    x: FIT.degreesFromSemicircles(p.lon),
                    y: FIT.degreesFromSemicircles(p.lat),
                    z: alt,
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

    // MARK: - Conversion from GeoJSON

    /// Converts a ``FeatureCollection`` back into encoded FIT messages.
    ///
    /// This reconstructs `file_id`, `record`, `lap`, `session` and
    /// `activity` messages from the GeoJSON representation produced by
    /// ``convertToGeoJSON(_:)``.
    private static func convertFromGeoJSON(
        _ fc: FeatureCollection
    ) throws -> [FITEncoder.EncodedMessage] {
        var messages: [FITEncoder.EncodedMessage] = []

        // file_id (from device metadata)
        messages.append(buildFileIdMessage(from: fc))

        // Find the track Feature
        guard let track = fc.features.first(where: { $0.fitType == .record }),
              let multiLine = track.geometry as? MultiLineString
        else {
            throw FITEncoder.EncoderError.noRecordFeature
        }

        let allCoords = multiLine.lineStrings.flatMap { $0.coordinates }

        // Per-point sensor arrays
        let heartRates = track.fitHeartRates ?? Array(repeating: nil, count: allCoords.count)
        let cadences = track.fitCadences ?? Array(repeating: nil, count: allCoords.count)
        let powers = track.fitPowers ?? Array(repeating: nil, count: allCoords.count)
        let speeds = track.fitSpeeds ?? Array(repeating: nil, count: allCoords.count)
        let temperatures = track.fitTemperatures ?? Array(repeating: nil, count: allCoords.count)
        let rawTimestamps = track.properties["fit_timestamps"] as? [UInt32?] ?? Array(repeating: nil, count: allCoords.count)

        // Lap boundaries: one lap per LineString segment
        var lapStarts: [Int] = []
        var index = 0
        for lineString in multiLine.lineStrings {
            lapStarts.append(index)
            index += lineString.coordinates.count
        }

        // Record messages
        for i in 0..<allCoords.count {
            messages.append(buildRecordMessage(
                coordinate: allCoords[i],
                heartRate: i < heartRates.count ? heartRates[i] : nil,
                cadence: i < cadences.count ? cadences[i] : nil,
                power: i < powers.count ? powers[i] : nil,
                speed: i < speeds.count ? speeds[i] : nil,
                temperature: i < temperatures.count ? temperatures[i] : nil,
                timestamp: i < rawTimestamps.count ? rawTimestamps[i] : nil))
        }

        // Lap messages
        for lapStart in lapStarts {
            messages.append(buildLapMessage(
                lapStart: lapStart,
                totalRecords: allCoords.count,
                track: track))
        }

        // Session message (from track properties)
        messages.append(buildSessionMessage(from: track, totalRecords: allCoords.count))

        // Activity message (from foreign members)
        if let activityMeta = fc.fitActivity {
            messages.append(buildActivityMessage(from: activityMeta))
        }

        return messages
    }

    // MARK: - Message builders

    /// Builds the `file_id` message (global 0).
    private static func buildFileIdMessage(
        from fc: FeatureCollection
    ) -> FITEncoder.EncodedMessage {
        let device = fc.fitDevice ?? [:]

        let fileType: UInt8 = uint8Value(device["type"]) ?? 4  // default: activity
        let manufacturer: UInt16 = uint16Value(device["manufacturer"]) ?? 1
        let product: UInt16 = uint16Value(device["product"]) ?? 0
        let serial: UInt32 = uint32Value(device["serial_number"]) ?? 0
        let timeCreated: UInt32 = uint32Value(device["time_created"]) ?? 0

        return FITEncoder.EncodedMessage(
            globalMessageNumber: FITProfile.MesgNum.fileId.rawValue,
            fields: [
                .init(num: 0, baseType: .enumType, data: Data([fileType])),
                .init(num: 1, baseType: .uint16, data: FITEncoder.le16(manufacturer)),
                .init(num: 2, baseType: .uint16, data: FITEncoder.le16(product)),
                .init(num: 3, baseType: .uint32z, data: FITEncoder.le32(serial)),
                .init(num: 253, baseType: .uint32, data: FITEncoder.le32(timeCreated)),
            ])
    }

    /// Builds a `record` message (global 20).
    private static func buildRecordMessage(
        coordinate: Coordinate3D,
        heartRate: Int?,
        cadence: Int?,
        power: Int?,
        speed: Double?,
        temperature: Double?,
        timestamp: UInt32?
    ) -> FITEncoder.EncodedMessage {
        let lat = FIT.semicirclesFromDegrees(coordinate.latitude)
        let lon = FIT.semicirclesFromDegrees(coordinate.longitude)

        var fields: [FITEncoder.EncodedField] = [
            .init(num: 0, baseType: .sint32, data: FITEncoder.le32(lat)),
            .init(num: 1, baseType: .sint32, data: FITEncoder.le32(lon)),
        ]

        // Altitude: convert back to raw uint16 (scaled by 5, offset 500)
        if let altitude = coordinate.altitude {
            let raw = UInt32((altitude + 500.0) * 5.0)
            fields.append(.init(
                num: 2,
                baseType: .uint16,
                data: FITEncoder.le16(UInt16(min(raw, UInt32(UInt16.max))))))
        }

        if let heartRate {
            fields.append(.init(
                num: 3,
                baseType: .uint8,
                data: Data([UInt8(min(heartRate, Int(UInt8.max)))])))
        }
        if let cadence {
            fields.append(.init(
                num: 4,
                baseType: .uint8,
                data: Data([UInt8(min(cadence, Int(UInt8.max)))])))
        }
        if let speed {
            let raw = UInt32(speed * 1000.0)
            fields.append(.init(
                num: 6,
                baseType: .uint16,
                data: FITEncoder.le16(UInt16(min(raw, UInt32(UInt16.max))))))
        }
        if let power {
            fields.append(.init(
                num: 7,
                baseType: .uint16,
                data: FITEncoder.le16(UInt16(min(power, Int(UInt16.max))))))
        }
        if let temperature {
            fields.append(.init(
                num: 139,
                baseType: .sint8,
                data: Data([UInt8(bitPattern: Int8(temperature))])))
        }
        if let timestamp {
            fields.append(.init(
                num: 253,
                baseType: .uint32,
                data: FITEncoder.le32(timestamp)))
        }

        return FITEncoder.EncodedMessage(
            globalMessageNumber: FITProfile.MesgNum.record.rawValue,
            fields: fields)
    }

    /// Builds a `lap` message (global 9).
    private static func buildLapMessage(
        lapStart: Int,
        totalRecords: Int,
        track: Feature
    ) -> FITEncoder.EncodedMessage {
        let startTime: UInt32 = uint32Value(track.properties["start_time"]) ?? 0
        let totalElapsedTime: Double = doubleValue(track.properties["total_elapsed_time"]) ?? 0.0
        let totalTimerTime: Double = doubleValue(track.properties["total_timer_time"]) ?? totalElapsedTime
        let totalDistance: Double = doubleValue(track.properties["total_distance"]) ?? 0.0
        let totalCalories: Int = intValue(track.properties["total_calories"]) ?? 0
        let avgSpeed: Double = doubleValue(track.properties["avg_speed"]) ?? 0.0
        let maxSpeed: Double = doubleValue(track.properties["max_speed"]) ?? 0.0
        let avgHeartRate: Int = intValue(track.properties["avg_heart_rate"]) ?? 0
        let maxHeartRate: Int = intValue(track.properties["max_heart_rate"]) ?? 0
        let avgCadence: Int = intValue(track.properties["avg_cadence"]) ?? 0
        let maxCadence: Int = intValue(track.properties["max_cadence"]) ?? 0
        let avgPower: Int = intValue(track.properties["avg_power"]) ?? 0
        let maxPower: Int = intValue(track.properties["max_power"]) ?? 0
        let totalAscent: Double = doubleValue(track.properties["total_ascent"]) ?? 0.0
        let totalDescent: Double = doubleValue(track.properties["total_descent"]) ?? 0.0

        // event = lap (9), event_type = stop (1)
        let timestamp = uint32Value(track.properties["fit_timestamp"]) ?? uint32Value(track.properties["timestamp"]) ?? 0

        let fields: [FITEncoder.EncodedField] = [
            .init(num: 253, baseType: .uint32, data: FITEncoder.le32(timestamp)),
            .init(num: 0, baseType: .uint32, data: FITEncoder.le32(startTime)),
            .init(num: 5, baseType: .uint32, data: FITEncoder.le32(UInt32(totalElapsedTime * 1000.0))),
            .init(num: 6, baseType: .uint32, data: FITEncoder.le32(UInt32(totalTimerTime * 1000.0))),
            .init(num: 7, baseType: .uint32, data: FITEncoder.le32(UInt32(totalDistance * 100.0))),
            .init(num: 9, baseType: .uint16, data: FITEncoder.le16(UInt16(min(totalCalories, Int(UInt16.max))))),
            .init(num: 11, baseType: .uint16, data: FITEncoder.le16(UInt16(UInt32(avgSpeed * 1000.0)))),
            .init(num: 12, baseType: .uint16, data: FITEncoder.le16(UInt16(UInt32(maxSpeed * 1000.0)))),
            .init(num: 13, baseType: .uint8, data: Data([UInt8(min(avgHeartRate, Int(UInt8.max)))])),
            .init(num: 14, baseType: .uint8, data: Data([UInt8(min(maxHeartRate, Int(UInt8.max)))])),
            .init(num: 15, baseType: .uint8, data: Data([UInt8(min(avgCadence, Int(UInt8.max)))])),
            .init(num: 16, baseType: .uint8, data: Data([UInt8(min(maxCadence, Int(UInt8.max)))])),
            .init(num: 17, baseType: .uint16, data: FITEncoder.le16(UInt16(min(avgPower, Int(UInt16.max))))),
            .init(num: 18, baseType: .uint16, data: FITEncoder.le16(UInt16(min(maxPower, Int(UInt16.max))))),
            .init(num: 19, baseType: .uint16, data: FITEncoder.le16(UInt16(UInt32((totalAscent + 500.0) * 5.0)))),
            .init(num: 20, baseType: .uint16, data: FITEncoder.le16(UInt16(UInt32((totalDescent + 500.0) * 5.0)))),
            .init(num: 24, baseType: .enumType, data: Data([9])),  // event = lap
            .init(num: 25, baseType: .enumType, data: Data([1])),  // event_type = stop
        ]

        _ = lapStart
        _ = totalRecords

        return FITEncoder.EncodedMessage(
            globalMessageNumber: FITProfile.MesgNum.lap.rawValue,
            fields: fields)
    }

    /// Builds a `session` message (global 18).
    private static func buildSessionMessage(
        from track: Feature,
        totalRecords: Int
    ) -> FITEncoder.EncodedMessage {
        let startTime: UInt32 = uint32Value(track.properties["start_time"]) ?? 0
        let totalElapsedTime: Double = doubleValue(track.properties["total_elapsed_time"]) ?? 0.0
        let totalTimerTime: Double = doubleValue(track.properties["total_timer_time"]) ?? totalElapsedTime
        let totalDistance: Double = doubleValue(track.properties["total_distance"]) ?? 0.0
        let totalCalories: Int = intValue(track.properties["total_calories"]) ?? 0
        let avgSpeed: Double = doubleValue(track.properties["avg_speed"]) ?? 0.0
        let maxSpeed: Double = doubleValue(track.properties["max_speed"]) ?? 0.0
        let avgHeartRate: Int = intValue(track.properties["avg_heart_rate"]) ?? 0
        let maxHeartRate: Int = intValue(track.properties["max_heart_rate"]) ?? 0
        let avgCadence: Int = intValue(track.properties["avg_cadence"]) ?? 0
        let maxCadence: Int = intValue(track.properties["max_cadence"]) ?? 0
        let avgPower: Int = intValue(track.properties["avg_power"]) ?? 0
        let maxPower: Int = intValue(track.properties["max_power"]) ?? 0
        let totalAscent: Double = doubleValue(track.properties["total_ascent"]) ?? 0.0
        let totalDescent: Double = doubleValue(track.properties["total_descent"]) ?? 0.0
        let sport: UInt8 = uint8Value(track.properties["sport"]) ?? 0
        let timestamp = uint32Value(track.properties["fit_timestamp"]) ?? uint32Value(track.properties["timestamp"]) ?? 0
        let numLaps: UInt16 = 1

        _ = totalRecords

        return FITEncoder.EncodedMessage(
            globalMessageNumber: FITProfile.MesgNum.session.rawValue,
            fields: [
                .init(num: 253, baseType: .uint32, data: FITEncoder.le32(timestamp)),
                .init(num: 0, baseType: .uint32, data: FITEncoder.le32(startTime)),
                .init(num: 5, baseType: .uint32, data: FITEncoder.le32(UInt32(totalElapsedTime * 1000.0))),
                .init(num: 6, baseType: .uint32, data: FITEncoder.le32(UInt32(totalTimerTime * 1000.0))),
                .init(num: 7, baseType: .uint32, data: FITEncoder.le32(UInt32(totalDistance * 100.0))),
                .init(num: 9, baseType: .uint16, data: FITEncoder.le16(UInt16(min(totalCalories, Int(UInt16.max))))),
                .init(num: 11, baseType: .uint16, data: FITEncoder.le16(UInt16(UInt32(avgSpeed * 1000.0)))),
                .init(num: 12, baseType: .uint16, data: FITEncoder.le16(UInt16(UInt32(maxSpeed * 1000.0)))),
                .init(num: 13, baseType: .uint8, data: Data([UInt8(min(avgHeartRate, Int(UInt8.max)))])),
                .init(num: 14, baseType: .uint8, data: Data([UInt8(min(maxHeartRate, Int(UInt8.max)))])),
                .init(num: 15, baseType: .uint8, data: Data([UInt8(min(avgCadence, Int(UInt8.max)))])),
                .init(num: 16, baseType: .uint8, data: Data([UInt8(min(maxCadence, Int(UInt8.max)))])),
                .init(num: 17, baseType: .uint16, data: FITEncoder.le16(UInt16(min(avgPower, Int(UInt16.max))))),
                .init(num: 18, baseType: .uint16, data: FITEncoder.le16(UInt16(min(maxPower, Int(UInt16.max))))),
                .init(num: 19, baseType: .uint16, data: FITEncoder.le16(UInt16(UInt32(totalAscent * 5.0)))),
                .init(num: 20, baseType: .uint16, data: FITEncoder.le16(UInt16(UInt32(totalDescent * 5.0)))),
                .init(num: 23, baseType: .enumType, data: Data([sport])),
                .init(num: 35, baseType: .uint16, data: FITEncoder.le16(numLaps)),
            ])
    }

    /// Builds an `activity` message (global 34).
    private static func buildActivityMessage(
        from activityMeta: [String: Sendable]
    ) -> FITEncoder.EncodedMessage {
        let totalTimerTime: Double = doubleValue(activityMeta["total_timer_time"]) ?? 0.0
        let numSessions: UInt16 = uint16Value(activityMeta["num_sessions"]) ?? 1
        let activityType: UInt8 = uint8Value(activityMeta["type"]) ?? 0
        let timestamp = uint32Value(activityMeta["timestamp"]) ?? 0
        let localTimestamp = uint32Value(activityMeta["local_timestamp"]) ?? timestamp

        return FITEncoder.EncodedMessage(
            globalMessageNumber: FITProfile.MesgNum.activity.rawValue,
            fields: [
                .init(num: 253, baseType: .uint32, data: FITEncoder.le32(timestamp)),
                .init(num: 0, baseType: .uint32, data: FITEncoder.le32(UInt32(totalTimerTime * 1000.0))),
                .init(num: 1, baseType: .uint16, data: FITEncoder.le16(numSessions)),
                .init(num: 2, baseType: .enumType, data: Data([activityType])),
                .init(num: 5, baseType: .uint32, data: FITEncoder.le32(localTimestamp)),
            ])
    }

    // MARK: - Property extraction helpers

    private static func intValue(_ value: Sendable?) -> Int? {
        guard let value else { return nil }
        if let i = value as? Int { return i }
        if let i64 = value as? Int64 { return Int(i64) }
        if let d = value as? Double { return Int(d) }
        if let u32 = value as? UInt32 { return Int(u32) }
        if let u16 = value as? UInt16 { return Int(u16) }
        if let u8 = value as? UInt8 { return Int(u8) }
        if let i16 = value as? Int16 { return Int(i16) }
        if let i8 = value as? Int8 { return Int(i8) }
        return nil
    }

    private static func doubleValue(_ value: Sendable?) -> Double? {
        guard let value else { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let i64 = value as? Int64 { return Double(i64) }
        if let u32 = value as? UInt32 { return Double(u32) }
        if let u16 = value as? UInt16 { return Double(u16) }
        if let u8 = value as? UInt8 { return Double(u8) }
        if let i16 = value as? Int16 { return Double(i16) }
        if let f = value as? Float { return Double(f) }
        return nil
    }

    private static func uint8Value(_ value: Sendable?) -> UInt8? {
        guard let v = intValue(value) else { return nil }
        return UInt8(max(0, min(v, Int(UInt8.max))))
    }

    private static func uint16Value(_ value: Sendable?) -> UInt16? {
        guard let v = intValue(value) else { return nil }
        return UInt16(max(0, min(v, Int(UInt16.max))))
    }

    private static func uint32Value(_ value: Sendable?) -> UInt32? {
        guard let v = intValue(value) else { return nil }
        return UInt32(max(0, min(v, Int(UInt32.max))))
    }

}
