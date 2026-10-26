# Writing and round-trips

`FITCoder` encodes a `FeatureCollection` into a binary FIT 2.0 file.

## Required shape

The collection must contain a track feature whose `fit_type` is `"record"` and
whose geometry is a `MultiLineString`. This is exactly what
`FITCoder.read(from:)` produces.

```swift
let collection = try FITCoder.read(from: inputURL)
try FITCoder.write(collection, to: outputURL)
```

An empty collection, or one without a record track, throws ``FITError``.

## Write options

```swift
let options = FITWriteOptions(
    protocolVersion: 0x20,
    profileVersion: 2100,
    includeHeaderCRC: true)

try FITCoder.write(collection, to: outputURL, options: options)

let data = try collection.fitData(options: options)
try collection.writeFIT(to: outputURL, options: options)
```

The file CRC is always written. `includeHeaderCRC` additionally writes the
optional 14-byte header CRC.

## What is written back

The encoder reconstructs these messages:

| Source | Message |
|---|---|
| `fitDevice` | `file_id` |
| record track and its per-point arrays | `record` |
| `fit_type == "lap"` features | `lap` |
| `fitSessions` (or session fields merged into the track) | `session` |
| `fitActivity` | `activity` |
| `fit_type == "event"` features | `event` |
| `fitDevices` (or `fitDevice` when it contains device-only fields) | `device_info` |

Every record field that the FIT profile knows about and that is present in the
source is written back. This includes enhanced speed and altitude, distance,
grade, power, temperature, timestamps and the session time-in-zone arrays.

## Coordinates

Coordinates are written as FIT semicircles in WGS84. If the geometry is not in
EPSG:4326 or `noSRID`, it is reprojected to EPSG:4326 before encoding.

Altitude comes from the coordinate Z value. The legacy `altitude` field is
written; a preserved `enhanced_altitude` array is written as well when present.

## Round-trip guarantees

For files produced by `FITCoder.read(from:)`:

- Coordinates, altitude, standard sensor arrays and timestamps round-trip.
- Lap and event features round-trip with their metadata.
- Multiple session and device-info messages round-trip.
- Array fields such as time-in-heart-rate-zone round-trip.
- Enum values remain raw integers; their names are a presentation concern.

Not guaranteed:

- Unknown/vendor messages are ignored.
- Unknown fields are kept as `field_<number>` strings for inspection and are
  dropped on re-encode.
- Developer fields are skipped (see <doc:Limitations>).
- Records without GPS are omitted when other records have a GPS fix.
- Point-feature reconstruction always produces a single line string.

## Error handling

```swift
do {
    try FITCoder.write(collection, to: outputURL)
}
catch let error as FITError {
    print(error.localizedDescription)
}
```

Encoding limits are enforced: at most 16 local message definitions, 255 fields
per definition, and 255 bytes per field. Values that cannot be represented by a
field's base type throw instead of being silently truncated.
