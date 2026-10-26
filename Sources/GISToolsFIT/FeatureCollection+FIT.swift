import Foundation
import GISTools

// MARK: - FeatureCollection FIT convenience extensions

extension FeatureCollection {

    /// Creates a feature collection from a FIT file URL.
    ///
    /// - Parameters:
    ///   - url: The URL of the FIT file.
    ///   - options: The read options (default ``FITReadOptions``).
    public init?(
        fit url: URL,
        options: FITReadOptions = FITReadOptions()
    ) {
        guard let fc = try? FITCoder.read(from: url, options: options) else { return nil }
        self = fc
    }

    /// Creates a feature collection from binary FIT data.
    ///
    /// - Parameters:
    ///   - fitData: The binary FIT data.
    ///   - options: The read options (default ``FITReadOptions``).
    public init?(
        fitData: Data,
        options: FITReadOptions = FITReadOptions()
    ) {
        guard let fc = try? FITCoder.read(from: fitData, options: options) else { return nil }
        self = fc
    }

    /// Encodes the receiver to binary FIT data.
    ///
    /// - Parameter options: The write options (default ``FITWriteOptions``).
    /// - Returns: The binary FIT data.
    /// - Throws: ``FITError`` if the collection cannot be encoded.
    public func fitData(options: FITWriteOptions = FITWriteOptions()) throws -> Data {
        try FITCoder.write(self, options: options)
    }

    /// Writes the receiver as a FIT file.
    ///
    /// - Parameters:
    ///   - url: The destination URL.
    ///   - options: The write options (default ``FITWriteOptions``).
    /// - Throws: ``FITError`` if the data cannot be encoded or the file
    ///           cannot be written.
    public func writeFIT(
        to url: URL,
        options: FITWriteOptions = FITWriteOptions()
    ) throws {
        try FITCoder.write(self, to: url, options: options)
    }

    /// Features that originated from FIT record messages (track points).
    public var fitRecords: [Feature] {
        features.filter { $0.fitType == .record }
    }

    /// Reconstructs a track Feature from Point features produced by
    /// `Feature.fitPointFeatures()`.
    ///
    /// Non-Point features are silently skipped. Sensor data is re-accumulated
    /// into per-point arrays on the returned track Feature.
    ///
    /// - Returns: A `Feature<MultiLineString>` with per-point sensor
    ///            arrays, or `nil` if no Point features were found.
    public func fitTrackFromPointFeatures() -> Feature? {
        let pointFeatures = features.filter { $0.geometry is Point }
        guard !pointFeatures.isEmpty else { return nil }

        let coords = pointFeatures.compactMap { ($0.geometry as? Point)?.coordinate }
        let multiLine = MultiLineString(unchecked: [LineString(unchecked: coords)])

        var feature = Feature(multiLine)
        feature.properties["fit_type"] = FITRecordType.record.rawValue

        var heartRates: [Int?] = []
        var cadences: [Int?] = []
        var powers: [Int?] = []
        var speeds: [Double?] = []
        var temperatures: [Double?] = []
        var timestamps: [String?] = []

        // Accumulate every non-standard per-record property into a
        // `fit_record_<name>` array so that fields such as distance, grade or
        // enhanced speed survive a point-feature round trip.
        var extraArrays: [String: [Sendable?]] = [:]
        let standardKeys: Set<String> = [
            "fit_type", "heart_rate", "cadence", "power", "speed",
            "temperature", "timestamp", "altitude",
            "position_lat", "position_long",
        ]
        let recordFieldNames = Set(
            FITProfile.fields(for: FITProfile.MesgNum.record.rawValue).values.map(\.name))
        for pf in pointFeatures {
            for key in pf.properties.keys where !standardKeys.contains(key) && recordFieldNames.contains(key) {
                extraArrays[key] = []
            }
        }

        for pf in pointFeatures {
            let p = pf.properties
            heartRates.append(intValue(p["heart_rate"]))
            cadences.append(intValue(p["cadence"]))
            powers.append(intValue(p["power"]))
            speeds.append(doubleValue(p["speed"]))
            temperatures.append(doubleValue(p["temperature"]))
            timestamps.append(timestampValue(p["timestamp"]))
            for key in Array(extraArrays.keys) {
                extraArrays[key]?.append(p[key])
            }
        }

        if heartRates.contains(where: { $0 != nil }) { feature.properties["fit_heart_rates"] = heartRates }
        if cadences.contains(where: { $0 != nil }) { feature.properties["fit_cadences"] = cadences }
        if powers.contains(where: { $0 != nil }) { feature.properties["fit_powers"] = powers }
        if speeds.contains(where: { $0 != nil }) { feature.properties["fit_speeds"] = speeds }
        if temperatures.contains(where: { $0 != nil }) { feature.properties["fit_temperatures"] = temperatures }
        if timestamps.contains(where: { $0 != nil }) { feature.properties["fit_timestamps"] = timestamps }
        for (key, values) in extraArrays where values.contains(where: { $0 != nil }) {
            feature.properties["fit_record_\(key)"] = values
        }

        return feature
    }

    /// Activity metadata from the FIT file.
    public var fitActivity: [String: Sendable]? {
        get { foreignMembers["fit_activity"] as? [String: Sendable] }
        set { foreignMembers["fit_activity"] = newValue }
    }

    /// Combined file-ID and device information from the FIT file.
    ///
    /// For files with multiple `device_info` messages this contains the
    /// file-ID fields merged with the first device. Use ``fitDevices`` to
    /// access every device.
    public var fitDevice: [String: Sendable]? {
        get { foreignMembers["fit_device"] as? [String: Sendable] }
        set { foreignMembers["fit_device"] = newValue }
    }

    /// All `device_info` messages from the FIT file, in file order.
    public var fitDevices: [[String: Sendable]]? {
        get { foreignMembers["fit_devices"] as? [[String: Sendable]] }
        set { foreignMembers["fit_devices"] = newValue }
    }

    /// All `session` messages from the FIT file, in file order.
    ///
    /// The last session's fields are also merged onto the record track
    /// Feature for backwards compatibility.
    public var fitSessions: [[String: Sendable]]? {
        get { foreignMembers["fit_sessions"] as? [[String: Sendable]] }
        set { foreignMembers["fit_sessions"] = newValue }
    }

    /// The sport type of the activity (from session data), mapped to its
    /// human-readable name (e.g. `"running"`).
    public var fitSport: String? {
        // Session metadata (including sport) is merged onto the record track
        // Feature, so look there first.
        if let track = fitRecords.first {
            if let sport = track.properties["sport"],
               let intValue = intValue(sport)
            {
                return FIT.name(for: "sport", value: intValue)
            }
            if let sub = track.properties["sub_sport"],
               let intValue = intValue(sub)
            {
                return FIT.name(for: "sub_sport", value: intValue)
            }
        }
        let act = foreignMembers["fit_activity"] as? [String: Sendable]
        if let sport = act?["sport"], let intValue = intValue(sport) {
            return FIT.name(for: "sport", value: intValue)
        }
        if let sub = act?["sub_sport"], let intValue = intValue(sub) {
            return FIT.name(for: "sub_sport", value: intValue)
        }
        return nil
    }

    private func intValue(_ value: Sendable?) -> Int? {
        guard let value else { return nil }
        if let i = value as? Int { return i }
        if let i64 = value as? Int64 { return Int(clamping: i64) }
        if let i32 = value as? Int32 { return Int(i32) }
        if let u8 = value as? UInt8 { return Int(u8) }
        if let u16 = value as? UInt16 { return Int(u16) }
        if let u32 = value as? UInt32 { return Int(u32) }
        if let u64 = value as? UInt64 { return Int(clamping: u64) }
        if let d = value as? Double { return Int(d) }
        if let f = value as? Float { return Int(f) }
        return nil
    }

    private func doubleValue(_ value: Sendable?) -> Double? {
        guard let value else { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let i64 = value as? Int64 { return Double(i64) }
        if let i32 = value as? Int32 { return Double(i32) }
        if let u8 = value as? UInt8 { return Double(u8) }
        if let u16 = value as? UInt16 { return Double(u16) }
        if let u32 = value as? UInt32 { return Double(u32) }
        if let u64 = value as? UInt64 { return Double(u64) }
        if let f = value as? Float { return Double(f) }
        return nil
    }

    private func timestampValue(_ value: Sendable?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s }
        if let date = value as? Date { return FIT.iso8601String(from: date) }
        return nil
    }

}
