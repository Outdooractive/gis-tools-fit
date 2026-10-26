# Getting started

`GISToolsFIT` reads and writes FIT 2.0 activity files. It builds on
[GISTools](https://github.com/Outdooractive/gis-tools) and uses the same
`FeatureCollection` model as the other `gis-tools-*` packages.

## Requirements

- Swift 6.1 or newer
- iOS 15+, macOS 15+, tvOS 15+, watchOS 7+, Linux

## Installation

Add both packages to your `Package.swift`:

```swift
dependencies: [
    .package(
        url: "https://github.com/Outdooractive/gis-tools",
        from: "3.0.0-beta.5"),
    .package(
        url: "https://github.com/Outdooractive/gis-tools-fit",
        from: "3.0.0-beta.1"),
],
targets: [
    .target(
        name: "MyTarget",
        dependencies: [
            .product(name: "GISTools", package: "gis-tools"),
            .product(name: "GISToolsFIT", package: "gis-tools-fit"),
        ]),
]
```

## Reading a file

```swift
import GISTools
import GISToolsFIT

let collection = try FITCoder.read(from: fitURL)
```

Or use the optional convenience initializer, which returns `nil` when the file
cannot be decoded:

```swift
guard let collection = FeatureCollection(fit: fitURL) else {
    return
}
```

Pass ``FITReadOptions`` to skip CRC verification for a known-damaged file:

```swift
let collection = try FITCoder.read(
    from: fitURL,
    options: FITReadOptions(verifyCRC: false))
```

## Writing a file

```swift
try FITCoder.write(collection, to: outputURL)

// Or through the collection:
try collection.writeFIT(to: outputURL)

// Or get the bytes:
let data = try collection.fitData()
```

The collection must contain a track feature with `fit_type == "record"` and a
`MultiLineString` geometry. See <doc:WritingAndRoundTrips> for the exact
contract.

## Errors

All public operations throw ``FITError``:

| Case | Meaning |
|---|---|
| `.fileReadError` | The file could not be read from disk |
| `.fileWriteError` | The encoded data could not be written to disk |
| `.parseError` | The bytes are not a decodable FIT file |
| `.invalidFile` | The value cannot be encoded as FIT |

See <doc:ReadingTracks> to learn how messages map to features.
