# Reading tracks and sensor data

A FIT activity is decoded into a `FeatureCollection`. This article describes
the exact mapping and the typed accessors.

## Message mapping

| FIT message | GeoJSON representation | `fit_type` |
|---|---|---|
| `record` | `MultiLineString` track | `record` |
| `lap` | `Point` marker with lap metadata | `lap` |
| `event` | `Point` marker with event metadata | `event` |
| `session` | Metadata on the track feature and in `fit_sessions` | — |
| `activity` | `FeatureCollection` foreign member `fit_activity` | — |
| `file_id` | `FeatureCollection` foreign member `fit_device` | — |
| `device_info` | `fit_device` and the `fit_devices` array | — |

## Track geometry

The record track is a `MultiLineString`. Each line string is one lap segment.
The line strings are split at lap start times, so a three-lap activity produces
three line strings.

```swift
let track = collection.features.first { $0.fitType == .record }
let multiLine = track?.geometry as? MultiLineString

print(multiLine?.lineStrings.count ?? 0)          // lap segments
print(multiLine?.lineStrings.flatMap(\.coordinates).count ?? 0)
```

Coordinates are always EPSG:4326 and carry the record altitude in
`Coordinate3D`'s Z value:

```swift
let first = multiLine?.lineStrings.first?.coordinates.first
print(first?.latitude ?? 0, first?.altitude ?? 0)
```

Records without a valid GPS fix are omitted when the activity contains at least
one GPS-bearing record, so the per-point arrays stay aligned with the
coordinates. Indoor activities, where no record has a GPS fix, keep every record
and use an empty `MultiLineString` as the track geometry.

## Per-point sensor arrays

The standard sensor fields are stored as optional arrays parallel to the
flattened coordinates:

| Property | Type | FIT field |
|---|---|---|
| `fitHeartRates` | `[Int?]?` | `record.heart_rate` |
| `fitCadences` | `[Int?]?` | `record.cadence` |
| `fitPowers` | `[Int?]?` | `record.power` |
| `fitSpeeds` | `[Double?]?` | `record.enhanced_speed`, falling back to `record.speed` |
| `fitTemperatures` | `[Double?]?` | `record.temperature` |
| `fitAltitudes` | `[Double?]?` | Z value of the coordinates |
| `fitTimestamps` | `[Date?]?` | `record.timestamp` |

`nil` means the field was absent or invalid for that record.

```swift
let heartRates = track?.fitHeartRates ?? []
for (index, heartRate) in heartRates.enumerated() {
    if let heartRate {
        print("Point \(index): \(heartRate) bpm")
    }
}
```

Every other record field is preserved as an array under
`fit_record_<field_name>`. For example, `distance` is available as
`fit_record_distance`, and `enhanced_speed` as `fit_record_enhanced_speed`. These
arrays use the same indexing as the standard arrays.

## Session and device metadata

The last session's fields are merged into the track feature's properties for
convenience. All sessions are available through `fitSessions`:

```swift
let sport = track?.properties["sport"]
let averageHeartRate = track?.fitAvgHeartRate
let distance = track?.fitTotalDistance

for session in collection.fitSessions ?? [] {
    print(session["sport"] ?? "")
}
```

`fitDevice` combines the file-ID fields with the first device-info message.
`fitDevices` contains every device-info message.

```swift
print(collection.fitDevice?["manufacturer"] ?? "")
print(collection.fitDevices?.count ?? 0)
```

`fitSport` maps the raw sport value to a name such as `"running"` or `"cycling"`.

## Laps, events and enum names

Lap and event messages each become a `Point` feature. A lap marker uses the
lap's start position when present; otherwise the nearest record by timestamp is
used. An event marker uses the nearest record by timestamp.

```swift
for lap in collection.features where lap.fitType == .lap {
    print(lap.fitEnumName(for: "sport") ?? "")
    print(lap.fitTotalDistance ?? 0)
}

for event in collection.features where event.fitType == .event {
    print(event.fitEnumName(for: "event") ?? "")
}
```

FIT stores enum fields as raw integers. `FIT.name(for:value:)` converts a raw
value, and `Feature.fitEnumName(for:)` converts a feature property:

```swift
FIT.name(for: "event", value: 9)       // "lap"
FIT.name(for: "sport", value: 1)       // "running"
```

## Point features and slicing

A track can be expanded into individual point features:

```swift
let points = track?.fitPointFeatures()

let firstMinute = track?.fitPointFeatures(from: startDate, to: endDate)
let firstKilometer = track?.fitPointFeatures(from: 0.0, to: 1_000.0)
let middleThird = track?.fitPointFeatures(fraction: 0.33, to: 0.66)
```

Each point feature has the coordinate as its geometry, the standard sensor values
as individual properties (`heart_rate`, `power`, `timestamp`, …), and every
non-standard record field as a property with its FIT name (for example
`distance`).

A collection of point features can be reconstructed into a track:

```swift
let rebuilt = points?.fitTrackFromPointFeatures()
let rebuiltViaInitializer = Feature(fitTrackFrom: points)
```

Reconstruction produces one line string and re-accumulates the sensor and record
arrays. Non-point features are skipped. The result is `nil` when no point
features exist.

## Slicing semantics

- Time windows use the `record.timestamp` values and include both endpoints.
- Distance windows use cumulative Haversine distances in meters along the
  flattened track.
- Fraction windows clamp to `0.0 ... 1.0`; `to` is clamped to at least `from`.
- When a track has no timestamps, a time-window request returns all points.
