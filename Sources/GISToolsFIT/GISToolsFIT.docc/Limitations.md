# Limitations

`GISToolsFIT` covers the FIT activity messages that are useful for rendering and
exporting tracks. This article lists the intentional limits so they are not
mistaken for decoding bugs.

## Message coverage

The decoder recognises these global message numbers and maps them to typed
output: `file_id`, `record`, `lap`, `session`, `event`, `activity` and
`device_info`. Other messages are decoded far enough to validate the file and
are then ignored. Examples include capabilities, settings, workout, course and
monitoring messages.

Unknown fields of a known message are exposed as `field_<number>` strings for
inspection. They cannot be re-encoded because their base type is not part of the
built-in profile.

## Developer fields

Developer field data is consumed correctly, so a definition that contains
developer fields does not corrupt the following messages. The values are not
exposed through the typed API and are not written back. Applications that need
developer fields should read them with the Garmin FIT SDK.

## GPS gaps

If at least one record has a valid GPS fix, records without a fix are omitted
from the track and from the per-point arrays. This keeps every array aligned
with the `MultiLineString` coordinates. The record sensor data for those
moments is therefore not available through the typed API. Activities with no GPS
fix at all (indoor/trainer files) keep every record and use an empty
`MultiLineString`.

## Compressed fields

Compressed timestamp messages are fully supported: the timestamp is
reconstructed from the previous timestamp and the 5-bit offset, and the
definition's timestamp bytes are not misread.

`compressed_speed_distance` is a packed 3-byte field (12-bit speed and 12-bit
distance). It is exposed as raw bytes under `fit_record_compressed_speed_distance`
so that it round-trips without loss; it is not unpacked into speed/distance
values.

## Track shape

A record track is a `MultiLineString` with one line string per lap. Point
feature reconstruction always returns a single line string, so the lap split is
lost when a track is converted to point features and back.

Only one record track is supported. A collection with several record features
encodes the first one.

## Memory

The whole file is decoded into memory before it is converted to features. Very
large activities (hundreds of thousands of records) use memory proportional to
the number of messages and fields.

## Vendor extensions

This is a clean-room implementation based on the public FIT protocol. Vendor
specific messages and fields, non-standard developer fields, and unusual
architectures beyond the standard little- and big-endian definitions are not
interpreted beyond what the protocol requires for safe decoding.

## CRC and damaged files

The file CRC is validated by default. A non-zero header CRC is validated when a
14-byte header is present. Some devices write a zero header CRC; that is
accepted. Use ``FITReadOptions`` to disable verification when intentionally
reading a damaged file.
