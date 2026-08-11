import Foundation
import GISTools

/// One entry per `record` message. `lat`/`lon` are `nil` when the record has
/// no GPS position (e.g. indoor/trainer activities).
fileprivate struct RecordInfo {
    var lat: Int32?
    var lon: Int32?
    var fields: [Int: Any]
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
        var allRecords: [RecordInfo] = []
        var lapMessages: [FITDecoder.RawMessage] = []
        var eventMessages: [FITDecoder.RawMessage] = []
        var sessionMeta: [String: Sendable] = [:]
        var activityMeta: [String: Sendable] = [:]
        var fileIdMeta: [String: Sendable] = [:]
        var deviceInfoMeta: [String: Sendable] = [:]

        for msg in messages {
            let messageType = FITProfile.MesgNum(msg.globalMessageNumber)
            switch messageType {
            case .record:
                let lat = msg.fields[0] as? Int32
                let lon = msg.fields[1] as? Int32
                // FIT sentinel for invalid GPS fix: 0x7FFFFFFF
                let validGPS = lat != nil && lon != nil && lat != Int32.max && lon != Int32.max
                allRecords.append(RecordInfo(
                    lat: validGPS ? lat : nil,
                    lon: validGPS ? lon : nil,
                    fields: msg.fields))

            case .lap:
                lapMessages.append(msg)

            case .event:
                eventMessages.append(msg)

            case .session:
                sessionMeta = applyFields(msg.fields, mesgNum: messageType.rawValue)

            case .activity:
                activityMeta = applyFields(msg.fields, mesgNum: messageType.rawValue)

            case .fileId:
                fileIdMeta = applyFields(msg.fields, mesgNum: messageType.rawValue)

            case .deviceInfo:
                deviceInfoMeta = applyFields(msg.fields, mesgNum: messageType.rawValue)

            default:
                break
            }
        }

        // When at least one record carries a valid GPS position we keep the
        // historical behaviour: build the track from GPS-bearing records only
        // and align the per-point sensor arrays to those records. When NO
        // record has GPS (indoor/trainer activity) we preserve every record's
        // sensor data, indexed across all records, and emit an empty
        // `MultiLineString` as the track geometry.
        let anyGPS = allRecords.contains { $0.lat != nil && $0.lon != nil }
        let trackRecords: [RecordInfo] = anyGPS
            ? allRecords.filter { $0.lat != nil && $0.lon != nil }
            : allRecords

        // Build per-point sensor arrays aligned to `trackRecords`. Every record
        // field is captured as a per-point array so records round-trip fully.
        var heartRates: [Int?] = []
        var cadences: [Int?] = []
        var powers: [Int?] = []
        var speeds: [Double?] = []
        var temperatures: [Double?] = []
        var altitudes: [Double?] = []
        var timestamps: [String?] = []
        var perFieldArrays: [String: [Sendable?]] = [:]

        for record in trackRecords {
            let fields = record.fields
            if let v = fields[3] as? UInt8 { heartRates.append(Int(v)) }
            else { heartRates.append(nil) }
            if let v = fields[4] as? UInt8 { cadences.append(Int(v)) }
            else { cadences.append(nil) }
            if let v = fields[7] as? UInt16 { powers.append(Int(v)) }
            else { powers.append(nil) }
            if let v = fields[6] as? UInt16 { speeds.append(Double(v) / 1000.0) }
            else { speeds.append(nil) }
            if let v = fields[13] as? Int8 { temperatures.append(Double(v)) }
            else { temperatures.append(nil) }
            if let v = fields[2] as? UInt16 { altitudes.append(Double(v) / 5.0 - 500.0) }
            else { altitudes.append(nil) }
            if let v = fields[253] as? UInt32 {
                timestamps.append(FIT.iso8601String(from: FIT.dateFromTimestamp(v)))
            }
            else { timestamps.append(nil) }

            // Capture every other record field as a per-point array.
            let meta = applyFields(fields, mesgNum: FITProfile.MesgNum.record.rawValue)
            for (name, value) in meta {
                if name == "position_lat" || name == "position_long" || name == "timestamp" { continue }
                perFieldArrays[name, default: []].append(value)
            }
        }

        // Build track Feature with MultiLineString (possibly empty for indoor
        // activities — sensor data is still preserved on the Feature).
        var features: [Feature] = []
        if !trackRecords.isEmpty {
            let segments: [[Coordinate3D]] = buildSegments(
                trackRecords,
                altitudes: altitudes,
                lapStarts: [])
            let lineStrings = segments.map { LineString(unchecked: $0) }
            let multiLine: MultiLineString
            if lineStrings.isEmpty {
                // Indoor activity: no usable GPS coordinates at all.
                multiLine = MultiLineString()
            }
            else {
                multiLine = MultiLineString(unchecked: lineStrings)
            }
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

            // Store every other per-record field as a per-point array.
            for (name, array) in perFieldArrays {
                if array.contains(where: { $0 != nil }) {
                    feature.properties["fit_record_\(name)"] = array
                }
            }

            features.append(feature)
        }

        // Emit each lap as its own Feature carrying its full metadata. The
        // marker is placed at the lap's start position when available, falling
        // back to the nearest record coordinate.
        for lap in lapMessages {
            var lapFeature = Feature(Point(markerCoordinate(for: lap, records: allRecords)))
            lapFeature.properties["fit_type"] = FITRecordType.lap.rawValue
            let meta = applyFields(lap.fields, mesgNum: FITProfile.MesgNum.lap.rawValue)
            lapFeature.properties.merge(meta) { (_, new) in new }
            features.append(lapFeature)
        }

        // Emit each event as its own Feature carrying its full metadata. The
        // marker is placed at the record nearest the event's timestamp.
        for event in eventMessages {
            var eventFeature = Feature(Point(markerCoordinate(for: event, records: allRecords)))
            eventFeature.properties["fit_type"] = FITRecordType.event.rawValue
            let meta = applyFields(event.fields, mesgNum: FITProfile.MesgNum.event.rawValue)
            eventFeature.properties.merge(meta) { (_, new) in new }
            features.append(eventFeature)
        }

        // Merge metadata into foreign members. `fit_device` combines the
        // file_id and device_info messages; `fit_activity` carries the
        // activity message.
        var foreign: [String: Sendable] = [:]
        if !activityMeta.isEmpty { foreign["fit_activity"] = activityMeta as Sendable }
        var deviceMeta = fileIdMeta
        deviceMeta.merge(deviceInfoMeta) { (_, new) in new }
        if !deviceMeta.isEmpty { foreign["fit_device"] = deviceMeta as Sendable }

        // Build result (features is private(set), rebuild through init)
        var result = FeatureCollection(features)
        result.foreignMembers = foreign
        return result
    }

    // MARK: - Segment building

    /// Determines a valid coordinate for a marker Feature (lap/event).
    ///
    /// - For a lap, the lap's own `start_position_lat`/`start_position_long`
    ///   fields are used when present.
    /// - Otherwise the record whose timestamp is closest to the marker's
    ///   timestamp is used, so the marker sits on the track.
    /// - Falls back to the first GPS-bearing record.
    private static func markerCoordinate(
        for message: FITDecoder.RawMessage,
        records: [RecordInfo]
    ) -> Coordinate3D {
        // Lap start position, if present.
        if let lat = message.fields[3] as? Int32,
           let lon = message.fields[4] as? Int32,
           lat != Int32.max, lon != Int32.max {
            return Coordinate3D(
                x: FIT.degreesFromSemicircles(lon),
                y: FIT.degreesFromSemicircles(lat),
                projection: .epsg4326)
        }

        // Nearest record by timestamp.
        let markerTime = message.fields[253] as? UInt32
        let gpsRecords = records.filter { $0.lat != nil && $0.lon != nil }
        if let markerTime, !gpsRecords.isEmpty {
            let nearest = gpsRecords.min { a, b in
                let ta = a.fields[253] as? UInt32 ?? UInt32.max
                let tb = b.fields[253] as? UInt32 ?? UInt32.max
                return abs(Int(ta) - Int(markerTime)) < abs(Int(tb) - Int(markerTime))
            }
            if let nearest, let lat = nearest.lat, let lon = nearest.lon {
                return Coordinate3D(
                    x: FIT.degreesFromSemicircles(lon),
                    y: FIT.degreesFromSemicircles(lat),
                    projection: .epsg4326)
            }
        }

        // Fall back to the first GPS-bearing record.
        if let first = gpsRecords.first, let lat = first.lat, let lon = first.lon {
            return Coordinate3D(
                x: FIT.degreesFromSemicircles(lon),
                y: FIT.degreesFromSemicircles(lat),
                projection: .epsg4326)
        }

        return Coordinate3D(latitude: 0, longitude: 0)
    }

    private static func buildSegments(
        _ points: [RecordInfo],
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

            let coords: [Coordinate3D] = points[start..<end].enumerated().compactMap { (i, p) in
                guard let lat = p.lat, let lon = p.lon else { return nil }
                let alt = start + i < altitudes.count ? altitudes[start + i] : nil
                return Coordinate3D(
                    x: FIT.degreesFromSemicircles(lon),
                    y: FIT.degreesFromSemicircles(lat),
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
        if let arr = value as? [Any] { return arr.map { asSendable($0) } }
        return "\(value)"
    }

    // MARK: - Generic message encoding

    /// Reconstructs a FIT message from a dictionary of user-friendly values
    /// (as produced by ``applyFields(_:mesgNum:)``) using the FIT Profile
    /// metadata. Every field present in the dictionary is written back, so the
    /// round-trip preserves the full content of the message.
    private static func buildMessage(
        mesgNum: UInt16,
        from values: [String: Sendable]
    ) -> FITEncoder.EncodedMessage {
        let fields = FITProfile.fields(for: mesgNum)
        var encoded: [FITEncoder.EncodedField] = []

        for (fieldNum, meta) in fields.sorted(by: { $0.key < $1.key }) {
            guard let value = values[meta.name] else { continue }
            guard let raw = meta.rawValue(from: value) else { continue }
            encoded.append(FITEncoder.EncodedField(
                num: UInt8(fieldNum),
                baseType: meta.baseType,
                data: FITEncoder.encode(raw: raw, baseType: meta.baseType)))
        }

        return FITEncoder.EncodedMessage(
            globalMessageNumber: mesgNum,
            fields: encoded)
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
        if let device = fc.fitDevice {
            messages.append(buildMessage(mesgNum: FITProfile.MesgNum.fileId.rawValue, from: device))
        }

        // Find the track Feature
        guard let track = fc.features.first(where: { $0.fitType == .record }),
              let multiLine = track.geometry as? MultiLineString
        else {
            throw FITEncoder.EncoderError.noRecordFeature
        }

        let allCoords = multiLine.lineStrings.flatMap { $0.coordinates }

        // Per-point sensor arrays — fall back to arrays sized for the existing
        // coordinates so behaviour for GPS-bearing tracks is unchanged.
        let heartRates = track.fitHeartRates ?? Array(repeating: nil, count: allCoords.count)
        let cadences = track.fitCadences ?? Array(repeating: nil, count: allCoords.count)
        let powers = track.fitPowers ?? Array(repeating: nil, count: allCoords.count)
        let speeds = track.fitSpeeds ?? Array(repeating: nil, count: allCoords.count)
        let temperatures = track.fitTemperatures ?? Array(repeating: nil, count: allCoords.count)
        let rawTimestamps = track.properties["fit_timestamps"] as? [String?] ?? Array(repeating: nil, count: allCoords.count)

        // Total record count. For GPS-bearing tracks every sensor array is
        // sized to `allCoords.count`. For indoor activities where the
        // MultiLineString is empty but per-point sensor arrays/timestamps are
        // present, the record count is driven by those arrays instead.
        let recordCount = [
            allCoords.count,
            heartRates.count,
            cadences.count,
            powers.count,
            speeds.count,
            temperatures.count,
            rawTimestamps.count
        ].max() ?? 0

        // Record messages — reconstruct each record from the per-point arrays.
        let recordFields = FITProfile.fields(for: FITProfile.MesgNum.record.rawValue)
        for i in 0..<recordCount {
            var values: [String: Sendable] = [:]

            // Position and altitude come from the geometry.
            if i < allCoords.count {
                let c = allCoords[i]
                values["position_lat"] = FIT.semicirclesFromDegrees(c.latitude) as Sendable
                values["position_long"] = FIT.semicirclesFromDegrees(c.longitude) as Sendable
                if let alt = c.altitude {
                    values["altitude"] = alt as Sendable
                }
            }

            // Standard sensor arrays.
            if i < heartRates.count, let v = heartRates[i] { values["heart_rate"] = v as Sendable }
            if i < cadences.count, let v = cadences[i] { values["cadence"] = v as Sendable }
            if i < powers.count, let v = powers[i] { values["power"] = v as Sendable }
            if i < speeds.count, let v = speeds[i] { values["speed"] = v as Sendable }
            if i < temperatures.count, let v = temperatures[i] { values["temperature"] = v as Sendable }
            if i < rawTimestamps.count, let v = rawTimestamps[i] {
                // The timestamp field is a date; store it as an ISO string so
                // the generic encoder can convert it back to a FIT timestamp.
                values["timestamp"] = v as Sendable
            }

            // Every other per-record field (skip those handled above).
            let handled = Set(["position_lat", "position_long", "altitude", "heart_rate",
                               "cadence", "power", "speed", "temperature", "timestamp"])
            for (_, meta) in recordFields {
                guard !handled.contains(meta.name) else { continue }
                let key = "fit_record_\(meta.name)"
                guard let array = track.properties[key] as? [Sendable?], i < array.count, let v = array[i] else { continue }
                values[meta.name] = v
            }

            messages.append(buildMessage(mesgNum: FITProfile.MesgNum.record.rawValue, from: values))
        }

        // Lap messages — one per lap Feature (fall back to a single lap when
        // the track has no explicit lap Features).
        let lapFeatures = fc.features.filter { $0.fitType == .lap }
        if !lapFeatures.isEmpty {
            for lapFeature in lapFeatures {
                messages.append(buildMessage(mesgNum: FITProfile.MesgNum.lap.rawValue, from: lapFeature.properties))
            }
        } else if recordCount > 0 {
            messages.append(buildMessage(mesgNum: FITProfile.MesgNum.lap.rawValue, from: track.properties))
        }

        // Session message (from track properties)
        messages.append(buildMessage(mesgNum: FITProfile.MesgNum.session.rawValue, from: track.properties))

        // Activity message (from foreign members)
        if let activityMeta = fc.fitActivity {
            messages.append(buildMessage(mesgNum: FITProfile.MesgNum.activity.rawValue, from: activityMeta))
        }

        // Event messages — one per event Feature.
        for eventFeature in fc.features.filter({ $0.fitType == .event }) {
            messages.append(buildMessage(mesgNum: FITProfile.MesgNum.event.rawValue, from: eventFeature.properties))
        }

        // Device info message (from foreign members).
        if let deviceMeta = fc.fitDevice {
            messages.append(buildMessage(mesgNum: FITProfile.MesgNum.deviceInfo.rawValue, from: deviceMeta))
        }

        return messages
    }


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
