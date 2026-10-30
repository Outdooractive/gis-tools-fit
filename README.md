[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-fit%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/Outdooractive/gis-tools-fit)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FOutdooractive%2Fgis-tools-fit%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/Outdooractive/gis-tools-fit)
[![](https://img.shields.io/github/license/Outdooractive/gis-tools-fit)](https://github.com/Outdooractive/gis-tools-fit/blob/main/LICENSE)  
[![](https://img.shields.io/github/v/release/Outdooractive/gis-tools-fit?sort=semver&display_name=tag)](https://github.com/Outdooractive/gis-tools-fit/releases) [![](https://img.shields.io/github/release-date/Outdooractive/gis-tools-fit?display_date=published_at)](https://github.com/Outdooractive/gis-tools-fit/releases)  
[![](https://img.shields.io/github/issues/Outdooractive/gis-tools-fit)](https://github.com/Outdooractive/gis-tools-fit/issues) [![](https://img.shields.io/github/issues-pr/Outdooractive/gis-tools-fit)](https://github.com/Outdooractive/gis-tools-fit/pulls)

# GISToolsFIT

FIT (Flexible and Interoperable Data Transfer) file read **and write** support
for Swift, built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools).
Parses Garmin FIT activity files into typed `FeatureCollection` objects and
writes them back to binary FIT. Pure Swift implementation based on the public
FIT protocol specification.

## Features

- Pure Swift FIT 2.0 decoder and encoder — no external dependencies beyond
  `gis-tools`
- File CRC validation, optional header CRC validation and optional header CRC
  writing
- Correct handling of little- and big-endian definitions, invalid field
  sentinels and compressed-timestamp messages
- Record points → `Feature<MultiLineString>` with one line string per lap
- Per-point sensor arrays: heart rate, cadence, power, enhanced/legacy speed,
  temperature, altitude and timestamps
- Every other record field preserved as a `fit_record_<name>` array
- Lap and Event messages → their own `Feature` markers with full metadata
- Session, Activity, File-ID and Device-Info metadata on the collection
- Multiple session and device-info messages preserved
- Typed convenience API on `Feature` and `FeatureCollection`
- Content-preserving round-trip for supported messages and fields
- Enum name mapping: turn raw enum values (e.g. `event: 9`) into names
  (e.g. `"lap"`)
- `fitPointFeatures()` expands a track into `Point` features with per-point
  data
- Time-window, distance-window and fractional-window slicing
- DocC catalog with guides and API reference

## Requirements

Swift 6.1 or higher. Compiles on iOS (≥ iOS 15), macOS (≥ macOS 15),
tvOS (≥ tvOS 15), watchOS (≥ watchOS 7), Linux, Android and Wasm.

## Installation with Swift Package Manager

```swift
dependencies: [
    .package(
        url: "https://github.com/Outdooractive/gis-tools",
        from: "3.0.0"),
    .package(
        url: "https://github.com/Outdooractive/gis-tools-fit",
        from: "3.0.0"),
],
targets: [
    .target(name: "MyTarget", dependencies: [
        .product(name: "GISTools", package: "gis-tools"),
        .product(name: "GISToolsFIT", package: "gis-tools-fit"),
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

// Or via the convenience initializer:
guard let fc = FeatureCollection(fit: url) else { return }
```

Read options control CRC validation:

```swift
let fc = try FITCoder.read(
    from: url,
    options: FITReadOptions(verifyCRC: false))
```

### Writing

```swift
// Encode a FeatureCollection back to binary FIT data
let data = try FITCoder.write(fc)

// Or write directly to a file
try FITCoder.write(fc, to: url)

// Or via the FeatureCollection convenience methods
let encoded = try fc.fitData()
try fc.writeFIT(to: url)
```

The old `FITCoder.write(from:)` and `FITCoder.write(from:to:)` spellings are
deprecated and remain available as overloads. New code should use
`FITCoder.write(_:)` and `FITCoder.write(_:to:)` to match the CSV, GPX and
Shapefile coders.

The `FeatureCollection` must contain a track `Feature` with a `MultiLineString`
geometry and `fit_type == "record"`, as produced by `FITCoder.read(from:)`.
Per-point sensor arrays, session, lap, activity and device metadata are written
back into the corresponding FIT messages.

Write options are available for protocol version, profile version and the
optional 14-byte header with header CRC:

```swift
let data = try FITCoder.write(
    fc,
    options: FITWriteOptions(includeHeaderCRC: true))
```

### Track geometry

The record track is a `MultiLineString`. Each line string is one lap segment:

```swift
let track = fc.features.first { $0.fitType == .record }
let multiLine = track?.geometry as? MultiLineString
print("\(multiLine?.lineStrings.count ?? 0) lap segments")
for (i, seg) in (multiLine?.lineStrings ?? []).enumerated() {
    print("  Lap \(i): \(seg.coordinates.count) points")
}
```

Coordinates are always EPSG:4326. Altitude is stored in
`Coordinate3D.altitude`.

### Per-point sensor data (parallel arrays)

Per-point arrays are indexed parallel to the flattened `MultiLineString`
coordinates. `nil` means the field was invalid or absent for that record.

```swift
let hr = track?.fitHeartRates      // [Int?]? — heart rate per track point
let cad = track?.fitCadences       // [Int?]? — cadence per track point
let pw = track?.fitPowers          // [Int?]? — power in watts
let spd = track?.fitSpeeds         // [Double?]? — m/s, enhanced fallback
let tmp = track?.fitTemperatures   // [Double?]? — temperature in °C
let alt = track?.fitAltitudes      // [Double?]? — altitude in meters
let ts = track?.fitTimestamps      // [Date?]? — timestamps per point
```

`fitSpeeds` prefers `enhanced_speed` and falls back to `speed`.
`fitAltitudes` reads the Z value of the coordinates; the encoder prefers
`enhanced_altitude` when a record provides it.

Every other record field is preserved as an array under
`fit_record_<field_name>`:

```swift
let distances = track?.properties["fit_record_distance"] as? [Sendable?]
let grades = track?.properties["fit_record_grade"] as? [Sendable?]
```

When an activity contains at least one GPS fix, records without a fix are
omitted so the arrays stay aligned with the coordinates. Indoor activities with
no GPS at all keep every record and use an empty `MultiLineString`.

### Point feature conversion

Convert the multi-point track into individual `Point` features, each carrying
its own sensor data and other record fields:

```swift
let pts = track?.fitPointFeatures()
pts?.features.count                            // e.g. 5283
pts?.features[0].properties["heart_rate"]      // 120
pts?.features[0].properties["power"]           // 150
pts?.features[0].properties["distance"]        // from fit_record_distance
pts?.features[0].properties["timestamp"]       // ISO8601 date string
```

### Time-based slicing

```swift
import Foundation

let start = FIT.dateFromTimestamp(500100)
let end = FIT.dateFromTimestamp(500200)
let segment = track?.fitPointFeatures(from: start, to: end)
print("\(segment?.features.count ?? 0) points in this window")
```

### Distance-based slicing

```swift
// Points between 1 km and 5 km along the track
let middle = track?.fitPointFeatures(from: 1000.0, to: 5000.0)

// Last kilometer
let lastKm = track?.fitPointFeatures(from: totalMeters - 1000.0, to: totalMeters)
```

### Fractional slicing

```swift
// Middle third of the track
let midThird = track?.fitPointFeatures(fraction: 0.33, to: 0.66)
```

### Reconstructing a track from point features

```swift
let pts = track?.fitPointFeatures()

// Via FeatureCollection:
let rebuilt = pts?.fitTrackFromPointFeatures()
rebuilt?.fitHeartRates?[0]   // 120
rebuilt?.fitPowers?[2]       // 280

// Via Feature convenience initializer:
let rebuiltViaInitializer = Feature(fitTrackFrom: pts)
rebuiltViaInitializer?.fitCadences?[1]  // 90
```

Non-Point features are silently skipped. Reconstruction returns `nil` if no
Point features exist. It produces a single line string, so the original lap
split is not restored.

### FeatureCollection convenience properties

```swift
// Quick access to record features
let records = fc.fitRecords
records.first?.properties["heart_rate"]  // 120

// Device and activity metadata
let device = fc.fitDevice         // file_id + first device_info
let devices = fc.fitDevices       // every device_info message
let sessions = fc.fitSessions     // every session message
let activity = fc.fitActivity
print(fc.fitSport)                // e.g. "running"
```

`fitDevice` combines the file-ID fields with the first device-info message.
`fitDevices` preserves every device-info message, including sensor devices.
The last session's fields are also merged onto the record track for backwards
compatibility.

### Enum name mapping

FIT stores enum-typed fields (e.g. `event`, `sport`, `event_type`) as raw
integers. Use `FIT.name(for:value:)` to turn a value into its human-readable
name, or `fitEnumName(for:)` on a `Feature` to map a property directly:

```swift
// Direct lookup
FIT.name(for: "event", value: 9)         // "lap"
FIT.name(for: "event_type", value: 1)    // "stop"
FIT.name(for: "sport", value: 1)         // "running"
FIT.name(for: "manufacturer", value: 1)  // "garmin"

// Via a Feature's properties
let event = fc.features.first { $0.fitType == .event }
event.fitEnumName(for: "event")       // "timer"
event.fitEnumName(for: "event_type")  // "start"
```

Field names that differ from their enum type name (e.g. `trigger` →
`session_trigger`, `sensor_position` → `body_location`) are resolved
automatically. The property name `type` is shared by `file_id` and `activity`;
file-ID names win when a value is valid in both tables.

### Summary data

```swift
// Session metadata (avg/max HR, speed, distance, calories)
print(track?.fitAvgHeartRate)        // Int? — e.g. 145
print(track?.fitMaxHeartRate)        // Int?
print(track?.fitTotalDistance)       // Double? — meters
print(track?.fitTotalCalories)       // Int? — kcal
```

### Per-point array reference

| Property | Type | FIT Field |
|---|---|---|
| `fitHeartRates` | `[Int?]?` | `record.heart_rate` |
| `fitCadences` | `[Int?]?` | `record.cadence` |
| `fitPowers` | `[Int?]?` | `record.power` |
| `fitSpeeds` | `[Double?]?` | `record.enhanced_speed`, fallback `record.speed` |
| `fitTemperatures` | `[Double?]?` | `record.temperature` |
| `fitAltitudes` | `[Double?]?` | coordinate Z (encoder: `enhanced_altitude` preferred) |
| `fitTimestamps` | `[Date?]?` | `record.timestamp` |
| `properties["fit_record_<name>"]` | `[Sendable?]` | every other record field |

### Single-value property reference

| Property | Type | Source |
|---|---|---|
| `fitType` | `FITRecordType?` | `.record` / `.lap` / `.session` |
| `fitHeartRate` | `Int?` | single-record summary |
| `fitCadence` | `Int?` | single-record summary |
| `fitPower` | `Int?` | single-record summary |
| `fitSpeed` | `Double?` | falls back to `enhanced_speed` |
| `fitTemperature` | `Double?` | |
| `fitAltitude` | `Double?` | Point Z, falls back to `enhanced_altitude` |
| `fitDistance` | `Double?` | `record.distance` (converted) |
| `fitPositionLat` / `fitPositionLon` | `CLLocationDegrees?` | Point coordinate or `position_lat`/`start_position_lat` in degrees |
| `fitTimestamp` / `fitStartTime` | `Date?` | ISO 8601 round-trip |
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
| `fitDevice` | `[String: Sendable]?` | file_id + first device_info |
| `fitDevices` | `[[String: Sendable]]?` | every device_info message |
| `fitSessions` | `[[String: Sendable]]?` | every session message |
| `fitSport` | `String?` | session sport/sub-sport mapped to a name |

**Methods on `FeatureCollection`:**

| Method | Returns | Description |
|---|---|---|
| `fitData(options:)` | `Data` | Encodes the receiver to binary FIT |
| `writeFIT(to:options:)` | `Void` | Writes the receiver as a FIT file |
| `fitTrackFromPointFeatures()` | `Feature?` | Reconstructs a track from Point features produced by `fitPointFeatures()`. Returns `nil` if no Point features exist. |

**Convenience initializer on `Feature`:**

| Initializer | Description |
|---|---|
| `Feature(fitTrackFrom:)` | Creates a track Feature from a `FeatureCollection` of Point features. Same as `fitTrackFromPointFeatures()`. |

### Errors

All public operations throw `FITError`:

- `.fileReadError` — the file could not be read
- `.fileWriteError` — the encoded data could not be written
- `.parseError` — the bytes are not a decodable FIT file
- `.invalidFile` — the collection cannot be encoded as FIT

### Limitations

- **Developer fields**: read and skipped correctly, but not exposed through the
  typed API and not written back.
- **Unknown messages/fields**: messages outside the supported set are ignored;
  unknown fields are kept as `field_<number>` strings and are dropped on
  re-encode.
- **GPS gaps**: records without a GPS fix are omitted when other records have
  one, so the per-point arrays stay aligned with the coordinates.
- **Single record track**: a collection with several record features encodes
  the first one.
- **Lap split after point conversion**: reconstruction produces one line
  string; the original lap boundaries are lost.
- **`compressed_speed_distance`**: exposed as raw bytes so it round-trips; it is
  not unpacked into speed/distance values.
- **Large files**: all messages are decoded in memory at once; files with
  500K+ records may use significant memory.
- **No Garmin SDK**: this is a clean-room implementation of the FIT protocol;
  vendor-specific extensions may not be interpreted.

## Documentation

The DocC catalog lives in `Sources/GISToolsFIT/GISToolsFIT.docc/` and contains
articles for getting started, reading tracks and sensor data, writing and
round-trips, and limitations. Build it locally with:

```sh
swift build --target GISToolsFIT \
    -Xswiftc -emit-symbol-graph \
    -Xswiftc -emit-symbol-graph-dir \
    -Xswiftc "$PWD/.build/symbol-graphs"
mkdir -p .build/docc-symbols
cp .build/symbol-graphs/GISToolsFIT.symbols.json .build/docc-symbols/
docc convert Sources/GISToolsFIT/GISToolsFIT.docc \
    --additional-symbol-graph-dir .build/docc-symbols \
    --fallback-display-name GISToolsFIT \
    --fallback-bundle-identifier GISToolsFIT \
    --output-path .build/docs \
    --warnings-as-errors
```

## Contributing

Please [create an issue](https://github.com/Outdooractive/gis-tools-fit/issues)
or [open a pull request](https://github.com/Outdooractive/gis-tools-fit/pulls)
with a fix or enhancement.

## License

MIT

## Authors

Thomas Rasch, Outdooractive

Built on top of [**gis-tools**](https://github.com/Outdooractive/gis-tools).
