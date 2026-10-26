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

/// Reads and writes FIT (Flexible and Interoperable Data Transfer) files.
///
/// FIT files contain fitness activity data recorded by GPS devices.
/// This coder maps them to a feature collection with:
///
/// | FIT Message     | GeoJSON Geometry    | `fit_type` property |
/// |-----------------|---------------------|---------------------|
/// | Record (points) | `MultiLineString`   | `"record"`          |
/// | Lap             | `Point`             | `"lap"`             |
/// | Event           | `Point`             | `"event"`           |
/// | Session         | (none, metadata)    | `"session"`         |
/// | File ID         | (none, metadata)    | `"file_id"`         |
/// | Activity        | (none, metadata)    | `"activity"`        |
///
/// The record track's `MultiLineString` contains one line string per lap.
/// Per-point sensor data is stored as parallel arrays on the record
/// feature.
public enum FITCoder {

    // MARK: - Reading

    /// Reads a FIT file and returns a feature collection.
    ///
    /// - Parameters:
    ///   - url: The URL of the FIT file.
    ///   - options: The read options (default ``FITReadOptions``).
    /// - Returns: A feature collection with the FIT data.
    /// - Throws: ``FITError`` if the file cannot be read or parsed.
    public static func read(
        from url: URL,
        options: FITReadOptions = FITReadOptions()
    ) throws -> FeatureCollection {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        }
        catch let error as FITError {
            throw error
        }
        catch {
            throw FITError.fileReadError(detail: error.localizedDescription)
        }
        return try read(from: data, options: options)
    }

    /// Reads FIT data and returns a feature collection.
    ///
    /// - Parameters:
    ///   - data: The binary FIT data.
    ///   - options: The read options (default ``FITReadOptions``).
    /// - Returns: A feature collection with the FIT data.
    /// - Throws: ``FITError`` if the data cannot be parsed.
    public static func read(
        from data: Data,
        options: FITReadOptions = FITReadOptions()
    ) throws -> FeatureCollection {
        let rawMessages: [FITDecoder.RawMessage]
        do {
            rawMessages = try FITDecoder.decode(
                data: data,
                verifyCRC: options.verifyCRC,
                verifyHeaderCRC: options.verifyHeaderCRC)
        }
        catch let error as FITDecoder.DecoderError {
            throw FITError.parseError(detail: error.localizedDescription)
        }
        catch {
            throw FITError.parseError(detail: error.localizedDescription)
        }

        return convertToGeoJSON(rawMessages)
    }

    // MARK: - Writing

    /// Encodes a feature collection into binary FIT data.
    ///
    /// The collection must contain a track feature with a `MultiLineString`
    /// geometry and `fit_type == "record"`, as produced by the FIT reading API.
    /// Per-point sensor arrays (`fit_heart_rates`, `fit_cadences`, etc.) and
    /// session/activity metadata stored on the feature collection are
    /// written back into the corresponding FIT messages.
    ///
    /// - Parameters:
    ///   - featureCollection: The feature collection to encode.
    ///   - options: The write options (default ``FITWriteOptions``).
    /// - Returns: The binary FIT data.
    /// - Throws: ``FITError`` if the collection cannot be encoded.
    public static func write(
        _ featureCollection: FeatureCollection,
        options: FITWriteOptions = FITWriteOptions()
    ) throws -> Data {
        do {
            let messages = try convertFromGeoJSON(featureCollection)
            return try FITEncoder.encode(
                messages: messages,
                protocolVersion: options.protocolVersion,
                profileVersion: options.profileVersion,
                includeHeaderCRC: options.includeHeaderCRC)
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

    /// Encodes a feature collection into binary FIT data.
    ///
    /// - Parameter featureCollection: The feature collection to encode.
    /// - Returns: The binary FIT data.
    /// - Throws: ``FITError`` if the collection cannot be encoded.
    @available(*, deprecated, message: "Use write(_:options:) instead.")
    public static func write(from featureCollection: FeatureCollection) throws -> Data {
        try write(featureCollection)
    }

    /// Writes a feature collection to a FIT file at the given URL.
    ///
    /// - Parameters:
    ///   - featureCollection: The feature collection to encode.
    ///   - url: The destination file URL.
    ///   - options: The write options (default ``FITWriteOptions``).
    /// - Throws: ``FITError`` if encoding or file writing fails.
    public static func write(
        _ featureCollection: FeatureCollection,
        to url: URL,
        options: FITWriteOptions = FITWriteOptions()
    ) throws {
        let data = try write(featureCollection, options: options)
        do {
            try data.write(to: url)
        }
        catch let error as FITError {
            throw error
        }
        catch {
            throw FITError.fileWriteError(detail: error.localizedDescription)
        }
    }

    /// Writes a feature collection to a FIT file at the given URL.
    ///
    /// - Parameters:
    ///   - featureCollection: The feature collection to encode.
    ///   - url: The destination file URL.
    /// - Throws: ``FITError`` if encoding or file writing fails.
    @available(*, deprecated, message: "Use write(_:to:options:) instead.")
    public static func write(
        from featureCollection: FeatureCollection,
        to url: URL
    ) throws {
        try write(featureCollection, to: url)
    }

    // MARK: - Conversion to GeoJSON

    private static func convertToGeoJSON(_ messages: [FITDecoder.RawMessage]) -> FeatureCollection {
        var allRecords: [RecordInfo] = []
        var lapMessages: [FITDecoder.RawMessage] = []
        var eventMessages: [FITDecoder.RawMessage] = []
        var sessionMetas: [[String: Sendable]] = []
        var activityMeta: [String: Sendable] = [:]
        var fileIdMeta: [String: Sendable] = [:]
        var deviceInfos: [[String: Sendable]] = []

        for msg in messages {
            let messageType = FITProfile.MesgNum(msg.globalMessageNumber)
            switch messageType {
            case .record:
                let lat = msg.fields[0] as? Int32
                let lon = msg.fields[1] as? Int32
                // FIT sentinel for invalid GPS fix: 0x7FFFFFFF. The decoder
                // already removes the sentinel, but keep the explicit check
                // for callers that construct raw messages directly.
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
                let meta = applyFields(msg.fields, mesgNum: messageType.rawValue)
                if !meta.isEmpty {
                    sessionMetas.append(meta)
                }

            case .activity:
                let meta = applyFields(msg.fields, mesgNum: messageType.rawValue)
                if !meta.isEmpty {
                    activityMeta = meta
                }

            case .fileId:
                let meta = applyFields(msg.fields, mesgNum: messageType.rawValue)
                if !meta.isEmpty {
                    fileIdMeta = meta
                }

            case .deviceInfo:
                let meta = applyFields(msg.fields, mesgNum: messageType.rawValue)
                if !meta.isEmpty {
                    deviceInfos.append(meta)
                }

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

        // Build per-point sensor arrays aligned to `trackRecords`.
        var heartRates: [Int?] = []
        var cadences: [Int?] = []
        var powers: [Int?] = []
        var speeds: [Double?] = []
        var temperatures: [Double?] = []
        var altitudes: [Double?] = []
        var timestamps: [String?] = []

        for record in trackRecords {
            let fields = record.fields
            heartRates.append((fields[3] as? UInt8).map(Int.init))
            cadences.append((fields[4] as? UInt8).map(Int.init))
            powers.append((fields[7] as? UInt16).map(Int.init))
            speeds.append(speed(from: fields))
            temperatures.append((fields[13] as? Int8).map(Double.init))
            altitudes.append(altitude(from: fields))
            if let v = fields[253] as? UInt32 {
                timestamps.append(FIT.iso8601String(from: FIT.dateFromTimestamp(v)))
            }
            else {
                timestamps.append(nil)
            }
        }

        // Capture every other record field as a per-point array. This is a
        // two-pass algorithm: collect all field names first, then append a
        // value (or nil) for every record so arrays cannot shift when a field
        // is absent from some records.
        let recordMetas = trackRecords.map {
            applyFields($0.fields, mesgNum: FITProfile.MesgNum.record.rawValue)
        }
        let handledRecordFields: Set<String> = [
            "position_lat", "position_long", "timestamp",
            "heart_rate", "cadence", "power", "speed", "temperature",
            "altitude",
        ]
        var perFieldArrays: [String: [Sendable?]] = [:]
        for meta in recordMetas {
            for name in meta.keys where !handledRecordFields.contains(name) {
                perFieldArrays[name] = []
            }
        }
        for meta in recordMetas {
            for name in Array(perFieldArrays.keys) {
                perFieldArrays[name]?.append(meta[name])
            }
        }

        // Lap boundaries split the track into one line string per lap.
        let lapStartIndices = lapStartRecordIndices(laps: lapMessages, records: trackRecords)

        // Build track feature with MultiLineString (possibly empty for indoor
        // activities — sensor data is still preserved on the feature).
        var features: [Feature] = []
        if !trackRecords.isEmpty {
            let segments = buildSegments(
                trackRecords,
                altitudes: altitudes,
                lapStarts: lapStartIndices)
            let lineStrings = segments.map { LineString(unchecked: $0) }
            let multiLine = lineStrings.isEmpty
                ? MultiLineString()
                : MultiLineString(unchecked: lineStrings)

            var feature = Feature(multiLine)
            feature.properties["fit_type"] = FITRecordType.record.rawValue
            // The last session is also merged onto the track for backwards
            // compatibility. All sessions are available through
            // `FeatureCollection.fitSessions`.
            if let session = sessionMetas.last {
                feature.properties.merge(session) { (_, new) in new }
            }

            // Store per-point sensor arrays (only if at least one non-nil).
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

        // Emit each lap as its own feature carrying its full metadata. The
        // marker is placed at the lap's start position when available, falling
        // back to the nearest record coordinate.
        for lap in lapMessages {
            var lapFeature = Feature(Point(markerCoordinate(
                for: lap,
                records: allRecords,
                useStartPosition: true)))
            lapFeature.properties["fit_type"] = FITRecordType.lap.rawValue
            let meta = applyFields(lap.fields, mesgNum: FITProfile.MesgNum.lap.rawValue)
            lapFeature.properties.merge(meta) { (_, new) in new }
            features.append(lapFeature)
        }

        // Emit each event as its own feature carrying its full metadata. The
        // marker is placed at the record nearest the event's timestamp.
        for event in eventMessages {
            var eventFeature = Feature(Point(markerCoordinate(
                for: event,
                records: allRecords,
                useStartPosition: false)))
            eventFeature.properties["fit_type"] = FITRecordType.event.rawValue
            let meta = applyFields(event.fields, mesgNum: FITProfile.MesgNum.event.rawValue)
            eventFeature.properties.merge(meta) { (_, new) in new }
            features.append(eventFeature)
        }

        // Merge metadata into foreign members. `fit_device` combines the
        // file_id and first device_info message; `fit_devices` preserves all
        // device_info messages. `fit_activity` carries the activity message
        // and `fit_sessions` preserves every session message.
        var foreign: [String: Sendable] = [:]
        if !activityMeta.isEmpty { foreign["fit_activity"] = activityMeta as Sendable }
        if !sessionMetas.isEmpty { foreign["fit_sessions"] = sessionMetas as Sendable }
        if !deviceInfos.isEmpty { foreign["fit_devices"] = deviceInfos as Sendable }

        var deviceMeta = fileIdMeta
        if let firstDevice = deviceInfos.first {
            deviceMeta.merge(firstDevice) { (_, new) in new }
        }
        if !deviceMeta.isEmpty { foreign["fit_device"] = deviceMeta as Sendable }

        var result = FeatureCollection(features)
        result.foreignMembers = foreign
        return result
    }

    // MARK: - Record field conversion

    /// The record speed in metres per second, preferring `enhanced_speed`.
    private static func speed(from fields: [Int: Any]) -> Double? {
        if let enhanced = fields[73] as? UInt32 {
            return Double(enhanced) / 1000.0
        }
        if let legacy = fields[6] as? UInt16 {
            return Double(legacy) / 1000.0
        }
        return nil
    }

    /// The record altitude in metres, preferring `enhanced_altitude`.
    private static func altitude(from fields: [Int: Any]) -> Double? {
        if let enhanced = fields[78] as? UInt32 {
            return Double(enhanced) / 5.0 - 500.0
        }
        if let legacy = fields[2] as? UInt16 {
            return Double(legacy) / 5.0 - 500.0
        }
        return nil
    }

    // MARK: - Segment building

    /// Finds the record index at which each lap starts.
    ///
    /// Lap start timestamps are compared with record timestamps. Laps without
    /// a usable start timestamp, and laps that start at the first record, do
    /// not create an additional segment.
    private static func lapStartRecordIndices(
        laps: [FITDecoder.RawMessage],
        records: [RecordInfo]
    ) -> [Int] {
        guard !records.isEmpty else { return [] }

        var indices: [Int] = []
        for lap in laps {
            guard let timestamp = lap.fields[2] as? UInt32 else { continue }
            guard let index = records.firstIndex(where: {
                guard let recordTimestamp = $0.fields[253] as? UInt32 else { return false }
                return recordTimestamp >= timestamp
            }) else { continue }
            if index > 0, index < records.count {
                indices.append(index)
            }
        }
        return Array(Set(indices)).sorted()
    }

    /// Determines a valid coordinate for a marker feature (lap/event).
    ///
    /// - For a lap, the lap's own `start_position_lat`/`start_position_long`
    ///   fields are used when present and `useStartPosition` is `true`.
    /// - Otherwise the record whose timestamp is closest to the marker's
    ///   timestamp is used, so the marker sits on the track.
    /// - Falls back to the first GPS-bearing record.
    private static func markerCoordinate(
        for message: FITDecoder.RawMessage,
        records: [RecordInfo],
        useStartPosition: Bool
    ) -> Coordinate3D {
        if useStartPosition,
           let lat = message.fields[3] as? Int32,
           let lon = message.fields[4] as? Int32
        {
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
        var splitIndices = Set(lapStarts.filter { $0 > 0 && $0 < points.count })
        splitIndices.insert(0)
        splitIndices.insert(points.count)

        let sorted = splitIndices.sorted()
        var segments: [[Coordinate3D]] = []

        for i in 0..<sorted.count - 1 {
            let start = sorted[i]
            let end = sorted[i + 1]
            guard end > start else { continue }

            let coords: [Coordinate3D] = points[start..<end].enumerated().compactMap { (offset, point) in
                guard let lat = point.lat, let lon = point.lon else { return nil }
                let altitude = start + offset < altitudes.count ? altitudes[start + offset] : nil
                return Coordinate3D(
                    x: FIT.degreesFromSemicircles(lon),
                    y: FIT.degreesFromSemicircles(lat),
                    z: altitude,
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
                // Unknown fields are kept as strings for diagnostics. They
                // cannot be re-encoded because their base type is unknown.
                result["field_\(fieldNum)"] = "\(rawValue)"
                continue
            }
            if let converted = meta.formatValue(rawValue) {
                result[meta.name] = asSendable(converted)
            }
        }
        return result
    }

    /// Wraps a value as `Sendable` for storage in a feature's properties.
    private static func asSendable(_ value: Any) -> Sendable {
        if let s = value as? String { return s }
        if let i = value as? Int { return i }
        if let d = value as? Double { return d }
        if let i64 = value as? Int64 { return i64 }
        if let b = value as? Bool { return b }
        if let u64 = value as? UInt64 { return u64 }
        if let u32 = value as? UInt32 { return Int(u32) }
        if let u16 = value as? UInt16 { return Int(u16) }
        if let u8 = value as? UInt8 { return Int(u8) }
        if let i32 = value as? Int32 { return Int(i32) }
        if let i16 = value as? Int16 { return Int(i16) }
        if let i8 = value as? Int8 { return Int(i8) }
        if let f = value as? Float { return Double(f) }
        if let arr = value as? [Any] { return arr.map { asSendable($0) } }
        return "\(value)"
    }

    // MARK: - Generic message encoding

    /// Reconstructs a FIT message from a dictionary of user-friendly values
    /// (as produced by ``applyFields(_:mesgNum:)``) using the FIT Profile
    /// metadata.
    private static func buildMessage(
        mesgNum: UInt16,
        from values: [String: Sendable]
    ) throws -> FITEncoder.EncodedMessage {
        let fields = FITProfile.fields(for: mesgNum)
        var encoded: [FITEncoder.EncodedField] = []

        for (fieldNum, meta) in fields.sorted(by: { $0.key < $1.key }) {
            guard let value = values[meta.name] else { continue }
            guard let raw = meta.rawValue(from: value) else { continue }
            let data = try FITEncoder.encode(raw: raw, baseType: meta.baseType)
            encoded.append(FITEncoder.EncodedField(
                num: UInt8(fieldNum),
                baseType: meta.baseType,
                data: data))
        }

        return FITEncoder.EncodedMessage(
            globalMessageNumber: mesgNum,
            fields: encoded)
    }

    // MARK: - Conversion from GeoJSON

    /// Converts a feature collection back into encoded FIT messages.
    ///
    /// This reconstructs `file_id`, `record`, `lap`, `session`, `activity`,
    /// `event` and `device_info` messages from the GeoJSON representation
    /// produced by ``convertToGeoJSON(_:)``.
    private static func convertFromGeoJSON(
        _ fc: FeatureCollection
    ) throws -> [FITEncoder.EncodedMessage] {
        var messages: [FITEncoder.EncodedMessage] = []

        // file_id (from device metadata)
        if let device = fc.fitDevice {
            let message = try buildMessage(
                mesgNum: FITProfile.MesgNum.fileId.rawValue,
                from: device)
            if !message.fields.isEmpty { messages.append(message) }
        }

        // Find the track feature.
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
        var recordCount = [
            allCoords.count,
            heartRates.count,
            cadences.count,
            powers.count,
            speeds.count,
            temperatures.count,
            rawTimestamps.count
        ].max() ?? 0
        for (key, value) in track.properties where key.hasPrefix("fit_record_") {
            if let array = value as? [Sendable?] {
                recordCount = max(recordCount, array.count)
            }
        }

        // Record messages — reconstruct each record from the per-point arrays.
        let recordFields = FITProfile.fields(for: FITProfile.MesgNum.record.rawValue)
        let handledRecordFields: Set<String> = [
            "position_lat", "position_long", "altitude",
            "heart_rate", "cadence", "power", "speed", "temperature",
            "timestamp",
        ]
        let perRecordFieldNames = recordFields.values
            .map(\.name)
            .filter { !handledRecordFields.contains($0) }
            .sorted()

        for i in 0..<recordCount {
            var values: [String: Sendable] = [:]

            // Position and altitude come from the geometry.
            if i < allCoords.count {
                var coordinate = allCoords[i]
                if coordinate.projection != .epsg4326, coordinate.projection != .noSRID {
                    coordinate = coordinate.projected(to: .epsg4326)
                }
                values["position_lat"] = coordinate.latitude as Sendable
                values["position_long"] = coordinate.longitude as Sendable
                if let alt = coordinate.altitude {
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
                values["timestamp"] = v as Sendable
            }

            // Every other per-record field (skip those handled above).
            for name in perRecordFieldNames {
                guard let array = track.properties["fit_record_\(name)"] as? [Sendable?],
                      i < array.count,
                      let v = array[i]
                else { continue }
                values[name] = v
            }

            let message = try buildMessage(
                mesgNum: FITProfile.MesgNum.record.rawValue,
                from: values)
            if !message.fields.isEmpty { messages.append(message) }
        }

        // Lap messages — one per lap feature.
        for lapFeature in fc.features.filter({ $0.fitType == .lap }) {
            let message = try buildMessage(
                mesgNum: FITProfile.MesgNum.lap.rawValue,
                from: lapFeature.properties)
            if !message.fields.isEmpty { messages.append(message) }
        }

        // Session messages. Prefer the preserved `fit_sessions` array; fall
        // back to session metadata merged onto the track feature.
        if let sessions = fc.fitSessions, !sessions.isEmpty {
            for session in sessions {
                let message = try buildMessage(
                    mesgNum: FITProfile.MesgNum.session.rawValue,
                    from: session)
                if !message.fields.isEmpty { messages.append(message) }
            }
        }
        else {
            let message = try buildMessage(
                mesgNum: FITProfile.MesgNum.session.rawValue,
                from: track.properties)
            if !message.fields.isEmpty { messages.append(message) }
        }

        // Activity message (from foreign members).
        if let activityMeta = fc.fitActivity {
            let message = try buildMessage(
                mesgNum: FITProfile.MesgNum.activity.rawValue,
                from: activityMeta)
            if !message.fields.isEmpty { messages.append(message) }
        }

        // Event messages — one per event feature.
        for eventFeature in fc.features.filter({ $0.fitType == .event }) {
            let message = try buildMessage(
                mesgNum: FITProfile.MesgNum.event.rawValue,
                from: eventFeature.properties)
            if !message.fields.isEmpty { messages.append(message) }
        }

        // Device info messages. Prefer the preserved array of device_info
        // messages; fall back to device metadata stored on `fit_device`.
        if let devices = fc.fitDevices, !devices.isEmpty {
            for device in devices {
                let message = try buildMessage(
                    mesgNum: FITProfile.MesgNum.deviceInfo.rawValue,
                    from: device)
                if !message.fields.isEmpty { messages.append(message) }
            }
        }
        else if let deviceMeta = fc.fitDevice, hasDeviceInfoFields(deviceMeta) {
            let message = try buildMessage(
                mesgNum: FITProfile.MesgNum.deviceInfo.rawValue,
                from: deviceMeta)
            if !message.fields.isEmpty { messages.append(message) }
        }

        return messages
    }

    /// Returns `true` when a device metadata dictionary contains at least one
    /// field that only exists in the `device_info` message (as opposed to the
    /// `file_id` message). This prevents a file that has no `device_info`
    /// message from gaining one when it is re-encoded.
    private static func hasDeviceInfoFields(_ device: [String: Sendable]) -> Bool {
        let deviceOnlyFields: Set<String> = [
            "device_index", "device_type", "software_version", "hardware_version",
            "cum_operating_time", "battery_voltage", "battery_status",
            "sensor_position", "descriptor", "ant_transmission_type",
            "ant_device_number", "ant_network", "source_type", "battery_level",
        ]
        return device.keys.contains { deviceOnlyFields.contains($0) }
    }

}
