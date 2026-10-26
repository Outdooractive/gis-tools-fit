# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `FITCoder.write(_:options:)` and `FITCoder.write(_:to:options:)` overloads,
  matching the argument-label convention used by the CSV, GPX and Shapefile
  coders.
- `FITReadOptions` (file and header CRC verification) and `FITWriteOptions`
  (protocol version, profile version, header CRC).
- `FeatureCollection.fitData(options:)` and
  `FeatureCollection.writeFIT(to:options:)`.
- `FeatureCollection.fitDevices` and `FeatureCollection.fitSessions`, preserving
  every device-info and session message.
- `Feature.fitTimestamp` and `Feature.fitStartTime` now accept and return
  ISO 8601 dates with or without fractional seconds.
- DocC catalog with getting-started, reading, writing and limitations articles.
- CI jobs for macOS, Linux, coverage and documentation validation.
- Regression tests for all FIT base types, both architectures, invalid
  sentinels, compressed timestamps, header CRC, per-field array alignment,
  enhanced-field fallbacks, multiple sessions/devices, projections and encoder
  limits.

### Changed

- Updated the `gis-tools` dependency pin to `3.0.0-beta.5` and refreshed
  `Package.resolved`.
- `FITError` now includes `.fileWriteError`; file read and write failures are
  wrapped instead of leaking Foundation errors.
- Position fields (`position_lat`, `position_long`, `start_position_*`,
  `end_position_*`, `nec_*`, `swc_*`) are converted to decimal degrees in
  properties and converted back when encoding.
- The record track geometry is split into one line string per lap.
- `fitSpeeds` prefers `enhanced_speed` and falls back to `speed`.
- Altitude uses `enhanced_altitude` as a fallback.
- `fitPointFeatures()` and `fitTrackFromPointFeatures()` now carry every
  non-standard record field (for example `distance`, `grade`,
  `enhanced_speed`).
- Encoder definitions now set the FIT "endian ability" bit for multi-byte base
  types.
- Encoder validates the 16-local-message, 255-field and 255-byte limits and
  rejects values it cannot represent instead of writing empty fields.
- Re-encoding no longer invents empty lap/session/device-info messages.
- The README now documents the actual behavior, limits and current dependency
  versions.

### Fixed

- Compressed timestamp messages are decoded correctly. The timestamp field is
  no longer read from the following field's bytes; the timestamp is
  reconstructed from the previous timestamp and the 5-bit offset.
- Invalid FIT sentinel values (`0xFF`, `0xFFFF`, `0x7FFFFFFF`, `0xFFFFFFFF`, …)
  are omitted instead of being exposed as real sensor values.
- Per-field `fit_record_*` arrays no longer shift when a field is missing from
  some records.
- Multiple device-info messages are no longer collapsed into one.
- Multiple session messages are no longer collapsed into one.
- Header CRC is validated when present and non-zero; invalid header sizes are
  rejected.
- Big-endian definitions decode correctly for every base type.
- Array fields such as session time-in-zone values survive a round-trip.
- Coordinates in EPSG:3857 or EPSG:4978 are reprojected to WGS84 before
  encoding instead of being clamped as invalid semicircles.
- `fitTimestamp`/`fitStartTime` values written with the default ISO 8601
  formatter can be read back again.
- Event markers use the nearest record, while lap markers use the lap start
  position.

### Deprecated

- `FITCoder.write(from:)` — use `FITCoder.write(_:options:)`.
- `FITCoder.write(from:to:)` — use `FITCoder.write(_:to:options:)`.

## [3.0.0-beta.1] - 2025-08-11

- Update to `gis-tools` 3.0.0-beta.1.
- Add FIT round-trip fidelity and enum name mapping.
- Fix FIT epoch timezone handling and preserve sensor data for GPS-less
  activities.
- Fix invalid GPS filtering, encoder definition reuse and integer overflow.

## [1.1.4] and earlier

See the Git history and release notes for earlier changes.
