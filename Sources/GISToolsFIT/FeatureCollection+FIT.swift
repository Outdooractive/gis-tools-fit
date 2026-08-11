import Foundation
import GISTools

// MARK: - FeatureCollection FIT convenience extensions

extension FeatureCollection {

    /// Creates a ``FeatureCollection`` from a FIT file URL.
    ///
    /// - Parameter fit: The URL of the FIT file.
    public init?(fit url: URL) {
        guard let fc = try? FITCoder.read(from: url) else { return nil }
        self = fc
    }

    /// Creates a ``FeatureCollection`` from binary FIT data.
    ///
    /// - Parameter fitData: The binary FIT data.
    public init?(fitData: Data) {
        guard let fc = try? FITCoder.read(from: fitData) else { return nil }
        self = fc
    }

    /// Encodes the receiver to binary FIT data.
    ///
    /// - Returns: The binary FIT data.
    /// - Throws: ``FITError`` if the collection cannot be encoded.
    public func fitData() throws -> Data {
        try FITCoder.write(from: self)
    }

    /// Writes the receiver as a FIT file.
    ///
    /// - Parameter url: The destination URL.
    /// - Throws: ``FITError`` if the data cannot be encoded or the file
    ///           cannot be written.
    public func writeFIT(to url: URL) throws {
        let data = try FITCoder.write(from: self)
        try data.write(to: url)
    }

    /// Features that originated from FIT record messages (track points).
    public var fitRecords: [Feature] {
        features.filter { $0.fitType == .record }
    }

    /// Reconstructs a track ``Feature`` from Point features produced by
    /// ``Feature/fitPointFeatures()``.
    ///
    /// Non-Point features are silently skipped. Sensor data is re-accumulated
    /// into per-point arrays on the returned track Feature.
    ///
    /// - Returns: A `Feature<MultiLineString>` with per-point sensor
    ///            arrays, or `nil` if no Point features were found.
    public func fitTrackFromPointFeatures() -> Feature? {
        let pointFeatures = features.filter { $0.geometry is Point }
        guard !pointFeatures.isEmpty else { return nil }

        let coords = pointFeatures.map { ($0.geometry as! Point).coordinate }
        let multiLine = MultiLineString(unchecked: [LineString(unchecked: coords)])

        var feature = Feature(multiLine)
        feature.properties["fit_type"] = FITRecordType.record.rawValue

        var heartRates: [Int?] = []
        var cadences: [Int?] = []
        var powers: [Int?] = []
        var speeds: [Double?] = []
        var temperatures: [Double?] = []
        var timestamps: [String?] = []

        for pf in pointFeatures {
            let p = pf.properties
            heartRates.append(p["heart_rate"] as? Int)
            cadences.append(p["cadence"] as? Int)
            powers.append(p["power"] as? Int)
            speeds.append(p["speed"] as? Double)
            temperatures.append(p["temperature"] as? Double)
            timestamps.append(p["timestamp"] as? String)
        }

        if heartRates.contains(where: { $0 != nil }) { feature.properties["fit_heart_rates"] = heartRates }
        if cadences.contains(where: { $0 != nil }) { feature.properties["fit_cadences"] = cadences }
        if powers.contains(where: { $0 != nil }) { feature.properties["fit_powers"] = powers }
        if speeds.contains(where: { $0 != nil }) { feature.properties["fit_speeds"] = speeds }
        if temperatures.contains(where: { $0 != nil }) { feature.properties["fit_temperatures"] = temperatures }
        if timestamps.contains(where: { $0 != nil }) { feature.properties["fit_timestamps"] = timestamps }

        return feature
    }

    /// Activity metadata from the FIT file.
    public var fitActivity: [String: Sendable]? {
        get { foreignMembers["fit_activity"] as? [String: Sendable] }
        set { foreignMembers["fit_activity"] = newValue }
    }

    /// Device information from the FIT file.
    public var fitDevice: [String: Sendable]? {
        get { foreignMembers["fit_device"] as? [String: Sendable] }
        set { foreignMembers["fit_device"] = newValue }
    }

    /// The sport type of the activity (from session data), mapped to its
    /// human-readable name (e.g. `"running"`).
    public var fitSport: String? {
        // Session metadata (including sport) is merged onto the record track
        // Feature, so look there first.
        if let track = fitRecords.first,
           let sport = track.properties["sport"],
           let intValue = intValue(sport) {
            return FIT.name(for: "sport", value: intValue)
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

    private func intValue(_ value: Sendable) -> Int? {
        if let i = value as? Int { return i }
        if let i64 = value as? Int64 { return Int(i64) }
        if let u8 = value as? UInt8 { return Int(u8) }
        if let u16 = value as? UInt16 { return Int(u16) }
        if let u32 = value as? UInt32 { return Int(u32) }
        return nil
    }

}
