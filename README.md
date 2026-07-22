[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-fit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/gis-tools-fit)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-fit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/gis-tools-fit)
[![](https://img.shields.io/github/license/Outdooractive/gis-tools-fit)](https://github.com/Outdooractive/gis-tools-fit/blob/main/LICENSE)  
[![](https://img.shields.io/github/v/release/Outdooractive/gis-tools-fit?sort=semver&display_name=tag)](https://github.com/Outdooractive/gis-tools-fit/releases) [![](https://img.shields.io/github/release-date/Outdooractive/gis-tools-fit?display_date=published_at)](https://github.com/Outdooractive/gis-tools-fit/releases)  
[![](https://img.shields.io/github/issues/Outdooractive/gis-tools-fit)](https://github.com/Outdooractive/gis-tools-fit/issues) [![](https://img.shields.io/github/issues-pr/Outdooractive/gis-tools-fit)](https://github.com/Outdooractive/gis-tools-fit/pulls)

# GISToolsFIT

FIT (Flexible and Interoperable Data Transfer) file read **and write** support for Swift, built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools). Parses Garmin FIT activity files into typed `FeatureCollection` objects and writes them back to binary FIT, pure Swift implementation based on the public FIT protocol specification.

## Features

- Pure Swift FIT decoder and encoder — no external dependencies
- Reads and writes FIT 2.0 files with CRC validation
- Record points → `Feature<MultiLineString>` with per-point sensor data as parallel arrays
- Lap boundaries split the track into `MultiLineString` segments
- Session, Lap, Event, File-ID, and Activity messages → `Feature` properties + `FeatureCollection` metadata
- **Per-point arrays**: heart rate, cadence, power, speed, temperature, altitude, timestamps
- **Typed convenience API** on `Feature` and `FeatureCollection` — no manual dictionary casting
- `fitPointFeatures()` → expand track into individual `Point` features with each record's sensor data
- Time-window, distance-window, and fractional-window slicing of point data

## Requirements

Swift 6.1 or higher. Compiles on iOS (≥ iOS 15), macOS (≥ macOS 15), tvOS (≥ tvOS 15), watchOS (≥ watchOS 7), Linux, Android and Wasm. No external dependencies beyond the base `gis-tools` package.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Outdooractive/gis-tools-fit", from: "1.0.0"),
    .package(url: "https://github.com/Outdooractive/gis-tools", from: "2.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "GISToolsFIT", package: "gis-tools-fit"),
        .product(name: "GISTools", package: "gis-tools"),
    ]),
]
```

## Usage

### Reading

```swift
import GISTools
import GISToolsFIT

let url = URL(fileURLWithPath: "/path/to/activity.fit")
let fc = try FITCoder.read(from: url)

// Or via the convenience init:
guard let fc = FeatureCollection(fit: url) else { return }
```

### Writing

```swift
// Encode a FeatureCollection back to binary FIT data
let data = try FITCoder.write(from: fc)

// Or write directly to a file
try FITCoder.write(from: fc, to: url)

// Or via the FeatureCollection convenience method
try fc.writeFIT(to: url)
```

The `FeatureCollection` must contain a track `Feature` with a `MultiLineString`
geometry and `fit_type == "record"`, as produced by `FITCoder.read(from:)`.
Per-point sensor arrays, session, lap, and activity metadata are written back
into the corresponding FIT messages. Round-trip read → write → read preserves
coordinates, heart rate, cadence, power, speed, temperature, altitude, and
timestamps.

### Track geometry

```swift
let track = fc.features.first!
let multiLine = track.geometry as! MultiLineString
print("\(multiLine.lineStrings.count) lap segments")
for (i, seg) in multiLine.lineStrings.enumerated() {
    print("  Lap \(i): \(seg.coordinates.count) points")
}
print("\(multiLine.lineStrings.flatMap { $0.coordinates }.count) total points")
```

### Per-point sensor data (parallel arrays)

Per-point arrays are indexed parallel to the flattened `MultiLineString` coordinates. For Garmin devices, every record contains all sensor fields, so the arrays always align:

```swift
let hr = track.fitHeartRates      // [Int?]? — heart rate per track point
let cad = track.fitCadences        // [Int?]? — cadence per track point
let pw = track.fitPowers           // [Int?]? — power in watts
let spd = track.fitSpeeds          // [Double?]? — speed in m/s
let tmp = track.fitTemperatures    // [Double?]? — temperature in °C
let alt = track.fitAltitudes       // [Double?]? — altitude in meters
let ts = track.fitTimestamps       // [Date?]? — timestamps per point

// Index i in the arrays → coordinate[i] in the flattened MultiLineString
// nil means no data recorded for that sensor at that point
for i in 0..<(track.fitHeartRates?.count ?? 0) {
    if let hr = hr[i], let cad = cad[i], let pw = pw[i] {
        print("Point \(i): HR=\(hr), cad=\(cad), power=\(pw)")
    }
}
```

### Point feature conversion

Convert the multi-point track into individual `Point` features, each carrying its own sensor data:

```swift
// All track points as individual Features
let pts = track.fitPointFeatures()
pts.features.count                  // e.g. 5283
pts.features[0].properties["heart_rate"]  // 120
pts.features[0].properties["power"]       // 150
pts.features[0].properties["timestamp"]   // 500100 (raw FIT timestamp)
```

### Time-based slicing

```swift
import Foundation

let start = FITDateFromTimestamp(500100)
let end = FITDateFromTimestamp(500200)
let segment = track.fitPointFeatures(from: start, to: end)
print("\(segment.features.count) points in this window")
```

### Distance-based slicing

```swift
// Points between 1 km and 5 km along the track
let middle = track.fitPointFeatures(from: 1000.0, to: 5000.0)

// Last kilometer
let lastKm = track.fitPointFeatures(from: totalMeters - 1000.0, to: totalMeters)
```

### Fractional slicing

```swift
// Middle third of the track
let midThird = track.fitPointFeatures(fraction: 0.33, to: 0.66)
```

### Reconstructing a track from point features

Convert a `FeatureCollection` of Point features (from `fitPointFeatures()`) back into a `Feature<MultiLineString>` track with per-point sensor arrays rebuilt:

```swift
let pts = track.fitPointFeatures()

// Via FeatureCollection:
let rebuilt = pts.fitTrackFromPointFeatures()
rebuilt?.fitHeartRates?[0]   // 120
rebuilt?.fitPowers?[2]        // 280

// Via Feature convenience init:
let track = Feature(fitTrackFrom: pts)
track?.fitCadences?[1]        // 90
```

Non-Point features are silently skipped. Returns `nil` if no Point features exist.

### FeatureCollection convenience properties

```swift
// Quick access to record features
let records = fc.fitRecords
records[0].properties["heart_rate"]  // 120

// Device and activity metadata
let device = fc.fitDevice
print(device?["manufacturer"])  // e.g. "Garmin"

let activity = fc.fitActivity
print(fc.fitSport)             // e.g. "Cycling"
```

### Summary data

```swift
// Session metadata (avg/max HR, speed, distance, calories)
print(track.fitAvgHeartRate)        // Int? — e.g. 145
print(track.fitMaxHeartRate)        // Int?
print(track.fitTotalDistance)       // Double? — meters
print(track.fitTotalCalories)       // Int? — kcal
```
### Per-point array reference

| Property | Type | FIT Field |
|---|---|---|
| `fitHeartRates` | `[Int?]?` | `record.heart_rate` |
| `fitCadences` | `[Int?]?` | `record.cadence` |
| `fitPowers` | `[Int?]?` | `record.power` |
| `fitSpeeds` | `[Double?]?` | `record.speed` (converted) |
| `fitTemperatures` | `[Double?]?` | `record.temperature` |
| `fitAltitudes` | `[Double?]?` | `record.altitude` (converted) |
| `fitTimestamps` | `[Date?]?` | `record.timestamp` |

### Single-value property reference

| Property | Type | Source |
|---|---|---|
| `fitType` | `FITRecordType?` | `.record` / `.lap` / `.session` |
| `fitHeartRate` | `Int?` | single-record summary |
| `fitCadence` | `Int?` | single-record summary |
| `fitPower` | `Int?` | single-record summary |
| `fitSpeed` | `Double?` | falls back to `enhanced_speed` |
| `fitTemperature` | `Double?` | |
| `fitAltitude` | `Double?` | falls back to `enhanced_altitude` |
| `fitDistance` | `Double?` | `record.distance` (converted) |
| `fitPositionLat` / `fitPositionLon` | `CLLocationDegrees?` | converted from semicircles |
| `fitAvgHeartRate` / `fitMaxHeartRate` | `Int?` | session summary |
| `fitAvgSpeed` / `fitMaxSpeed` | `Double?` | session summary |
| `fitTotalDistance` | `Double?` | session total (meters) |
| `fitTotalElapsedTime` | `Double?` | session total (seconds) |
| `fitTotalCalories` | `Int?` | session total (kcal) |
| `fitTotalAscent` / `fitTotalDescent` | `Double?` | session total (meters) |

### FeatureCollection metadata reference

| Property | Type | Source |
|---|---|---|
| `fitRecords` | `[Feature]` | features filtered by `fitType == .record` |
| `fitActivity` | `[String: Sendable]?` | activity message |
| `fitDevice` | `[String: Sendable]?` | file_id + device_info |
| `fitSport` | `String?` | session sport type |

**Methods on `FeatureCollection`:**

| Method | Returns | Description |
|---|---|---|
| `fitTrackFromPointFeatures()` | `Feature?` | Reconstructs a `Feature<MultiLineString>` from Point features produced by `fitPointFeatures()`. Sensor data is re-accumulated into per-point arrays. Returns `nil` if no Point features exist. |

**Convenience initializer on `Feature`:**

| Initializer | Description |
|---|---|
| `Feature(fitTrackFrom:)` | Creates a track Feature from a `FeatureCollection` of Point features. Same as `fitTrackFromPointFeatures()`. |

### Limitations

- **Compressed timestamps**: basic support; time-offset accumulation is minimal
- **Developer fields**: parsed but not exposed via typed API
- **Large files**: all messages are decoded in memory at once; files with 500K+ records may use significant memory
- **No Garmin SDK**: this is a clean-room implementation of the FIT protocol; edge cases in vendor-specific extensions may not be handled

## Contributing

Please [create an issue](https://github.com/Outdooractive/gis-tools-fit/issues) or [open a pull request](https://github.com/Outdooractive/gis-tools-fit/pulls) with a fix or enhancement.

## License

MIT

## Authors

Thomas Rasch, Outdooractive

Built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools).
