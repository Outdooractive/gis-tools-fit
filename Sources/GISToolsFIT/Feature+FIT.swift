#if canImport(CoreLocation)
import CoreLocation
#endif
import Foundation
import GISTools

// MARK: - Feature FIT convenience properties

extension Feature {

    /// The type of FIT record this Feature represents.
    public var fitType: FITRecordType? {
        get {
            guard let raw = properties["fit_type"] as? String else { return nil }
            return FITRecordType(rawValue: raw)
        }
        set {
            properties["fit_type"] = newValue?.rawValue
        }
    }

    /// Returns the human-readable name for an enum-typed property value.
    ///
    /// FIT stores enum fields (e.g. `event`, `sport`, `event_type`) as raw
    /// integers. This maps a property's integer value to its name.
    ///
    /// - Parameter key: The property key (e.g. `"event"`).
    /// - Returns: The enum name (e.g. `"lap"`), or `nil` if the property is
    ///   not an enum or the value is unknown.
    public func fitEnumName(for key: String) -> String? {
        guard let value = properties[key] else { return nil }
        let intValue: Int
        if let i = value as? Int { intValue = i }
        else if let i64 = value as? Int64 { intValue = Int(i64) }
        else if let u8 = value as? UInt8 { intValue = Int(u8) }
        else if let u16 = value as? UInt16 { intValue = Int(u16) }
        else if let u32 = value as? UInt32 { intValue = Int(u32) }
        else { return nil }
        return FIT.name(for: key, value: intValue)
    }

    /// Timestamp of this record (seconds since FIT epoch).
    public var fitTimestamp: Date? {
        get { dateProp("fit_timestamp") }
        set { properties["fit_timestamp"] = newValue.map { ISO8601DateFormatter().string(from: $0) } }
    }

    /// Heart rate in beats per minute.
    public var fitHeartRate: Int? {
        get { intProp("heart_rate") }
        set { properties["heart_rate"] = newValue }
    }

    /// Cadence in revolutions per minute.
    public var fitCadence: Int? {
        get { intProp("cadence") }
        set { properties["cadence"] = newValue }
    }

    /// Power in watts.
    public var fitPower: Int? {
        get { intProp("power") }
        set { properties["power"] = newValue }
    }

    /// Speed in meters per second.
    public var fitSpeed: Double? {
        get { doubleProp("speed") ?? doubleProp("enhanced_speed") }
        set { properties["speed"] = newValue }
    }

    /// Temperature in degrees Celsius.
    public var fitTemperature: Double? {
        get { doubleProp("temperature") }
        set { properties["temperature"] = newValue }
    }

    /// Altitude in meters.
    public var fitAltitude: Double? {
        get {
            if let point = geometry as? Point, let alt = point.coordinate.altitude { return alt }
            return doubleProp("altitude") ?? doubleProp("enhanced_altitude")
        }
        set { properties["altitude"] = newValue }
    }

    /// Distance in meters.
    public var fitDistance: Double? {
        get { doubleProp("distance") }
        set { properties["distance"] = newValue }
    }

    /// Latitude in decimal degrees.
    public var fitPositionLat: CLLocationDegrees? {
        get { doubleProp("position_lat") }
        set { properties["position_lat"] = newValue }
    }

    /// Longitude in decimal degrees.
    public var fitPositionLon: CLLocationDegrees? {
        get { doubleProp("position_long") }
        set { properties["position_long"] = newValue }
    }

    // MARK: - Lap/session properties

    /// Lap start time.
    public var fitStartTime: Date? {
        get { dateProp("start_time") }
        set { properties["start_time"] = newValue.map { ISO8601DateFormatter().string(from: $0) } }
    }

    /// Total distance for the lap/session in meters.
    public var fitTotalDistance: Double? {
        get { doubleProp("total_distance") }
        set { properties["total_distance"] = newValue }
    }

    /// Total elapsed time in seconds.
    public var fitTotalElapsedTime: Double? {
        get { doubleProp("total_elapsed_time") }
        set { properties["total_elapsed_time"] = newValue }
    }

    /// Total calories in kcal.
    public var fitTotalCalories: Int? {
        get { intProp("total_calories") }
        set { properties["total_calories"] = newValue }
    }

    /// Average heart rate.
    public var fitAvgHeartRate: Int? {
        get { intProp("avg_heart_rate") }
        set { properties["avg_heart_rate"] = newValue }
    }

    /// Maximum heart rate.
    public var fitMaxHeartRate: Int? {
        get { intProp("max_heart_rate") }
        set { properties["max_heart_rate"] = newValue }
    }

    /// Average speed in meters per second.
    public var fitAvgSpeed: Double? {
        get { doubleProp("avg_speed") }
        set { properties["avg_speed"] = newValue }
    }

    /// Maximum speed in meters per second.
    public var fitMaxSpeed: Double? {
        get { doubleProp("max_speed") }
        set { properties["max_speed"] = newValue }
    }

    /// Total ascent in meters.
    public var fitTotalAscent: Double? {
        get { doubleProp("total_ascent") }
        set { properties["total_ascent"] = newValue }
    }

    /// Total descent in meters.
    public var fitTotalDescent: Double? {
        get { doubleProp("total_descent") }
        set { properties["total_descent"] = newValue }
    }

    // MARK: - Per-point sensor arrays

    /// Heart rate per track point (parallel to `MultiLineString` coordinates).
    public var fitHeartRates: [Int?]? {
        properties["fit_heart_rates"] as? [Int?]
    }

    /// Cadence per track point.
    public var fitCadences: [Int?]? {
        properties["fit_cadences"] as? [Int?]
    }

    /// Power per track point (watts).
    public var fitPowers: [Int?]? {
        properties["fit_powers"] as? [Int?]
    }

    /// Speed per track point (m/s).
    public var fitSpeeds: [Double?]? {
        properties["fit_speeds"] as? [Double?]
    }

    /// Temperature per track point (degrees Celsius).
    public var fitTemperatures: [Double?]? {
        properties["fit_temperatures"] as? [Double?]
    }

    /// Altitude per track point (meters).
    public var fitAltitudes: [Double?]? {
        guard let multiLine = geometry as? MultiLineString else { return nil }
        let alts = multiLine.lineStrings.flatMap { $0.coordinates.map(\.altitude) }
        return alts.contains { $0 != nil } ? alts : nil
    }

    /// Timestamps per track point (Date). Maps nil timestamps to nil.
    public var fitTimestamps: [Date?]? {
        guard let raw = properties["fit_timestamps"] as? [String?] else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return raw.map { $0.flatMap { formatter.date(from: $0) } }
    }

    // MARK: - Point feature conversion

    /// Converts the track's `MultiLineString` geometry into a `FeatureCollection` of
    /// single `Point` features, each carrying the per-point sensor data for that record.
    ///
    /// The returned features have `fit_type = "record"` and per-point sensor values
    /// stored as individual properties (`heart_rate`, `cadence`, `power`, etc.).
    public func fitPointFeatures() -> FeatureCollection {
        let coords = flattenedCoordinates
        let hr = fitHeartRates ?? []
        let cad = fitCadences ?? []
        let pw = fitPowers ?? []
        let spd = fitSpeeds ?? []
        let tmp = fitTemperatures ?? []
        let alt = fitAltitudes ?? []
        let ts = properties["fit_timestamps"] as? [String?] ?? []

        var features: [Feature] = []
        for i in 0..<coords.count {
            var coord = coords[i]
            if i < alt.count, let v = alt[i] { coord.altitude = v }
            var f = Feature(Point(coord))
            f.properties["fit_type"] = "record"
            if i < hr.count, let v = hr[i] { f.properties["heart_rate"] = v }
            if i < cad.count, let v = cad[i] { f.properties["cadence"] = v }
            if i < pw.count, let v = pw[i] { f.properties["power"] = v }
            if i < spd.count, let v = spd[i] { f.properties["speed"] = v }
            if i < tmp.count, let v = tmp[i] { f.properties["temperature"] = v }
            if i < ts.count, let v = ts[i] { f.properties["timestamp"] = v }
            features.append(f)
        }
        return FeatureCollection(features)
    }

    /// Point features within a time window.
    public func fitPointFeatures(from startDate: Date, to endDate: Date) -> FeatureCollection {
        guard let ts = properties["fit_timestamps"] as? [String?] else {
            return fitPointFeatures()
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startSec = startDate.timeIntervalSince(FIT.epoch)
        let endSec = endDate.timeIntervalSince(FIT.epoch)
        let indices = ts.indices.filter { i in
            guard let s = ts[i], let date = formatter.date(from: s) else { return false }
            let t = date.timeIntervalSince(FIT.epoch)
            return t >= startSec && t <= endSec
        }
        return sliceFeatures(at: indices)
    }

    /// Point features within a distance window along the track.
    ///
    /// - Parameter from: Start distance in meters from the beginning of the track.
    /// - Parameter to: End distance in meters.
    /// - Returns: A ``FeatureCollection`` of point features in the distance range.
    public func fitPointFeatures(from startMeters: Double, to endMeters: Double) -> FeatureCollection {
        let distances = cumulativeDistances
        let indices = distances.indices.filter { i in
            distances[i] >= startMeters && distances[i] <= endMeters
        }
        return sliceFeatures(at: indices)
    }

    /// Point features within a fractional window along the track length.
    ///
    /// - Parameter from: Start fraction (0.0–1.0, inclusive).
    /// - Parameter to: End fraction (0.0–1.0, inclusive).
    /// - Returns: A ``FeatureCollection`` of point features in the fraction range.
    public func fitPointFeatures(fraction start: Double, to end: Double) -> FeatureCollection {
        let clampStart = max(0.0, min(start, 1.0))
        let clampEnd = max(clampStart, min(end, 1.0))
        let coords = flattenedCoordinates
        guard !coords.isEmpty else { return FeatureCollection() }
        let totalDistance = cumulativeDistances.last ?? 0
        return fitPointFeatures(from: clampStart * totalDistance, to: clampEnd * totalDistance)
    }

    /// Creates a track ``Feature`` from a collection of Point features
    /// produced by ``fitPointFeatures()``.
    ///
    /// See ``FeatureCollection/fitTrackFromPointFeatures()``.
    public init?(fitTrackFrom pointFeatures: FeatureCollection) {
        guard let track = pointFeatures.fitTrackFromPointFeatures() else { return nil }
        self = track
    }

    // MARK: - Private helpers

    /// Flattened coordinates from the MultiLineString geometry.
    private var flattenedCoordinates: [Coordinate3D] {
        guard let multiLine = geometry as? MultiLineString else { return [] }
        return multiLine.lineStrings.flatMap { $0.coordinates }
    }

    /// Cumulative Haversine distances (meters) from track start to each point.
    private var cumulativeDistances: [Double] {
        let coords = flattenedCoordinates
        guard !coords.isEmpty else { return [] }
        var distances = [Double](repeating: 0.0, count: coords.count)
        for i in 1..<coords.count {
            let d = coords[i - 1].distance(from: coords[i])
            distances[i] = distances[i - 1] + d
        }
        return distances
    }

    /// Builds a FeatureCollection from a subset of track-point indices.
    private func sliceFeatures(at indices: [Int]) -> FeatureCollection {
        let allFeatures = fitPointFeatures()
        let set = Set(indices)
        let selected = allFeatures.features.enumerated().filter { set.contains($0.offset) }.map { $0.element }
        return FeatureCollection(selected)
    }

    // MARK: - Helpers

    private func intProp(_ key: String) -> Int? {
        if let i = properties[key] as? Int { return i }
        if let i64 = properties[key] as? Int64 { return Int(i64) }
        if let d = properties[key] as? Double { return Int(d) }
        if let u32 = properties[key] as? UInt32 { return Int(u32) }
        if let u16 = properties[key] as? UInt16 { return Int(u16) }
        if let u8 = properties[key] as? UInt8 { return Int(u8) }
        if let i16 = properties[key] as? Int16 { return Int(i16) }
        if let i8 = properties[key] as? Int8 { return Int(i8) }
        return nil
    }

    private func doubleProp(_ key: String) -> Double? {
        if let d = properties[key] as? Double { return d }
        if let i = properties[key] as? Int { return Double(i) }
        if let i64 = properties[key] as? Int64 { return Double(i64) }
        if let u32 = properties[key] as? UInt32 { return Double(u32) }
        if let u16 = properties[key] as? UInt16 { return Double(u16) }
        if let u8 = properties[key] as? UInt8 { return Double(u8) }
        if let i16 = properties[key] as? Int16 { return Double(i16) }
        if let f = properties[key] as? Float { return Double(f) }
        return nil
    }

    private func dateProp(_ key: String) -> Date? {
        guard let s = properties[key] as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

}
