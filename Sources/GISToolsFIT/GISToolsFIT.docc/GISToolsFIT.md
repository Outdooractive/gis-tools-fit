# ``GISToolsFIT``

Read and write Garmin FIT (Flexible and Interoperable Data Transfer) activity
files in Swift.

## Overview

`GISToolsFIT` is a companion package to
[GISTools](https://github.com/Outdooractive/gis-tools). It decodes FIT activity
files into a `FeatureCollection` and encodes a `FeatureCollection` back into
a binary FIT file. The implementation is pure Swift and based on the public FIT
protocol documentation; it does not use the Garmin SDK.

A FIT activity becomes:

- One record track `Feature` with a `MultiLineString` geometry. The record
  messages supply the coordinates and the per-point sensor arrays. Line
  strings are split at lap boundaries.
- One lap `Feature` and one event `Feature` per corresponding FIT message,
  carrying their metadata as properties and placed at a representative
  coordinate.
- Session, activity, file-ID and device-info metadata on the track feature or
  the collection's foreign members.

```swift
import GISTools
import GISToolsFIT

let collection = try FITCoder.read(from: fitURL)
let track = collection.features.first { $0.fitType == .record }

print(track?.fitHeartRates ?? [])
print(collection.fitSport ?? "unknown")

try FITCoder.write(collection, to: outputURL)
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:ReadingTracks>

### Writing and round-trips

- <doc:WritingAndRoundTrips>

### Behavior and limits

- <doc:Limitations>
