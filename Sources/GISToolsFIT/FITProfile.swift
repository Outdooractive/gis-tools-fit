import Foundation

/// Known FIT message types and their field definitions.
/// These are derived from the public FIT Profile specification.
enum FITProfile {

    // MARK: - Known message numbers

    enum MesgNum: UInt16 {
        case fileId = 0
        case capabilities = 1
        case deviceSettings = 2
        case userProfile = 3
        case hrmProfile = 4
        case sdmProfile = 5
        case bikeProfile = 6
        case lap = 19
        case session = 18
        case record = 20
        case event = 21
        case deviceInfo = 23
        case activity = 34
        case unknown = 0xFFFF

        init(_ value: UInt16) {
            self = MesgNum(rawValue: value) ?? .unknown
        }
    }

    // MARK: - Field metadata

    /// Describes how to convert a raw field value to a user-friendly value.
    struct FieldMeta {
        let name: String
        let units: String
        let scale: Double
        let offset: Double
        let fieldType: String  // for documentation
        let baseType: FITBaseType
        let isDate: Bool

        static func plain(_ name: String, units: String = "", fieldType: String = "", baseType: FITBaseType = .uint8, isDate: Bool = false) -> FieldMeta {
            FieldMeta(name: name, units: units, scale: 1.0, offset: 0.0, fieldType: fieldType, baseType: baseType, isDate: isDate)
        }

        static func scaled(_ name: String, units: String, scale: Double, offset: Double = 0.0, baseType: FITBaseType = .uint16, isDate: Bool = false) -> FieldMeta {
            FieldMeta(name: name, units: units, scale: scale, offset: offset, fieldType: "", baseType: baseType, isDate: isDate)
        }

        func formatValue(_ raw: Any) -> Any? {
            // Arrays are formatted element-wise.
            if let arr = raw as? [Any] {
                return arr.compactMap { formatValue($0) }
            }
            // Date fields: convert the raw FIT timestamp to an ISO8601 string.
            if isDate {
                if let u32 = raw as? UInt32 {
                    return FIT.iso8601String(from: FIT.dateFromTimestamp(u32))
                }
                if let i = raw as? Int { return FIT.iso8601String(from: FIT.dateFromTimestamp(UInt32(i))) }
                if let i64 = raw as? Int64 { return FIT.iso8601String(from: FIT.dateFromTimestamp(UInt32(i64))) }
                if let u64 = raw as? UInt64 { return FIT.iso8601String(from: FIT.dateFromTimestamp(UInt32(u64))) }
                return nil
            }
            guard let num = raw as? Double else {
                // Already a string, return as-is
                if let s = raw as? String { return s }
                // Try numeric conversion
                if let i = raw as? Int { return applyScale(Double(i)) }
                if let i32 = raw as? Int32 { return applyScale(Double(i32)) }
                if let u32 = raw as? UInt32 { return applyScale(Double(u32)) }
                if let i16 = raw as? Int16 { return applyScale(Double(i16)) }
                if let u16 = raw as? UInt16 { return applyScale(Double(u16)) }
                if let i8 = raw as? Int8 { return applyScale(Double(i8)) }
                if let u8 = raw as? UInt8 { return applyScale(Double(u8)) }
                if let u64 = raw as? UInt64 { return applyScale(Double(u64)) }
                if let i64 = raw as? Int64 { return applyScale(Double(i64)) }
                if let f = raw as? Float { return Double(f) }
                if let d = raw as? Double { return d }
                return raw
            }
            return applyScale(num)
        }

        private func applyScale(_ value: Double) -> Any {
            if scale == 1.0, offset == 0.0 {
                // Check if it's a whole number -> return as Int64
                if value == floor(value),
                   value >= Double(Int64.min),
                   value <= Double(Int64.max)
                {
                    return Int64(value)
                }
                return value
            }
            let result = value / scale - offset
            // Keep as Double since we applied scale/offset
            return result
        }

        /// Converts a user-friendly value (as produced by ``formatValue(_:)``)
        /// back into the raw integer/float value stored in the FIT file.
        func rawValue(from formatted: Any) -> Any? {
            // Arrays are converted element-wise.
            if let arr = formatted as? [Any] {
                return arr.compactMap { rawValue(from: $0) }
            }
            // Date fields: convert the ISO8601 string back to a FIT timestamp.
            if isDate {
                if let s = formatted as? String {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: s) {
                        return Int64(date.timeIntervalSince(FIT.epoch))
                    }
                }
                return nil
            }
            // Strings pass through unchanged.
            if let s = formatted as? String { return s }

            let numeric: Double
            if let d = formatted as? Double { numeric = d }
            else if let i = formatted as? Int { numeric = Double(i) }
            else if let i32 = formatted as? Int32 { numeric = Double(i32) }
            else if let i64 = formatted as? Int64 { numeric = Double(i64) }
            else if let u32 = formatted as? UInt32 { numeric = Double(u32) }
            else if let u16 = formatted as? UInt16 { numeric = Double(u16) }
            else if let u8 = formatted as? UInt8 { numeric = Double(u8) }
            else if let i16 = formatted as? Int16 { numeric = Double(i16) }
            else if let i8 = formatted as? Int8 { numeric = Double(i8) }
            else if let u64 = formatted as? UInt64 { numeric = Double(u64) }
            else if let f = formatted as? Float { numeric = Double(f) }
            else { return nil }

            // Reverse of applyScale: raw = (value + offset) * scale
            let raw = (numeric + offset) * scale
            switch baseType {
            case .float32, .float64:
                return raw
            default:
                return Int64(raw.rounded())
            }
        }
    }

    // MARK: - Field lookup

    /// Returns the field metadata for a given message and field number.
    static func fieldMetadata(mesgNum: UInt16, fieldNum: Int) -> FieldMeta? {
        guard let msg = knownMessages[MesgNum(mesgNum)] else { return nil }
        return msg[fieldNum]
    }

    /// Returns all field metadata for a message, keyed by field number.
    static func fields(for mesgNum: UInt16) -> [Int: FieldMeta] {
        knownMessages[MesgNum(mesgNum)] ?? [:]
    }

    static func messageName(mesgNum: UInt16) -> String {
        switch MesgNum(mesgNum) {
        case .fileId: return "file_id"
        case .capabilities: return "capabilities"
        case .deviceSettings: return "device_settings"
        case .userProfile: return "user_profile"
        case .hrmProfile: return "hrm_profile"
        case .sdmProfile: return "sdm_profile"
        case .bikeProfile: return "bike_profile"
        case .lap: return "lap"
        case .session: return "session"
        case .record: return "record"
        case .event: return "event"
        case .deviceInfo: return "device_info"
        case .activity: return "activity"
        case .unknown: return "unknown"
        }
    }

    // MARK: - Known field definitions

    private static let knownMessages: [MesgNum: [Int: FieldMeta]] = [
        .fileId: fileIdFields,
        .record: recordFields,
        .lap: lapFields,
        .session: sessionFields,
        .event: eventFields,
        .activity: activityFields,
        .deviceInfo: deviceInfoFields,
    ]

    // Message 0: file_id
    private static let fileIdFields: [Int: FieldMeta] = [
        0: .plain("type", units: "", baseType: .enumType),
        1: .plain("manufacturer", units: "", baseType: .uint16),
        2: .plain("product", units: "", baseType: .uint16),
        3: .plain("serial_number", units: "", baseType: .uint32z),
        4: .plain("time_created", units: "", baseType: .uint32, isDate: true),
        5: .plain("number", units: "", baseType: .uint16),
        8: .plain("product_name", units: "", baseType: .string),
    ]

    // Message 20: record
    private static let recordFields: [Int: FieldMeta] = [
        253: .plain("timestamp", units: "s", baseType: .uint32, isDate: true),
        0: .plain("position_lat", units: "semicircles", baseType: .sint32),
        1: .plain("position_long", units: "semicircles", baseType: .sint32),
        2: .scaled("altitude", units: "m", scale: 5, offset: 500, baseType: .uint16),
        3: .plain("heart_rate", units: "bpm", baseType: .uint8),
        4: .plain("cadence", units: "rpm", baseType: .uint8),
        5: .scaled("distance", units: "m", scale: 100, offset: 0, baseType: .uint32),
        6: .scaled("speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint16),
        7: .plain("power", units: "watts", baseType: .uint16),
        8: .scaled("compressed_speed_distance", units: "m/s", scale: 100, offset: 0, baseType: .byte),
        9: .scaled("grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        10: .plain("resistance", units: "", baseType: .uint8),
        11: .scaled("time_from_course", units: "s", scale: 1000, offset: 0, baseType: .sint32),
        12: .scaled("cycle_length", units: "m", scale: 100, offset: 0, baseType: .uint8),
        13: .plain("temperature", units: "C", baseType: .sint8),
        17: .scaled("speed_1s", units: "m/s", scale: 16, offset: 0, baseType: .uint8),
        18: .plain("cycles", units: "cycles", baseType: .uint8),
        19: .plain("total_cycles", units: "cycles", baseType: .uint32),
        28: .plain("compressed_accumulated_power", units: "watts", baseType: .uint16),
        29: .plain("accumulated_power", units: "watts", baseType: .uint32),
        30: .plain("left_right_balance", units: "", baseType: .uint8),
        31: .plain("gps_accuracy", units: "m", baseType: .uint8),
        32: .scaled("vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        33: .plain("calories", units: "kcal", baseType: .uint16),
        39: .scaled("vertical_oscillation", units: "mm", scale: 10, offset: 0, baseType: .uint16),
        40: .scaled("stance_time_percent", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        41: .scaled("stance_time", units: "ms", scale: 10, offset: 0, baseType: .uint16),
        42: .plain("activity_type", units: "", baseType: .enumType),
        43: .scaled("left_torque_effectiveness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        44: .scaled("right_torque_effectiveness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        45: .scaled("left_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        46: .scaled("right_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        47: .scaled("combined_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        48: .scaled("time128", units: "s", scale: 128, offset: 0, baseType: .uint8),
        49: .plain("stroke_type", units: "", baseType: .enumType),
        50: .plain("zone", units: "", baseType: .uint8),
        51: .scaled("ball_speed", units: "m/s", scale: 100, offset: 0, baseType: .uint16),
        52: .scaled("cadence256", units: "rpm", scale: 256, offset: 0, baseType: .uint16),
        53: .scaled("fractional_cadence", units: "rpm", scale: 128, offset: 0, baseType: .uint8),
        54: .scaled("total_hemoglobin_conc", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        55: .scaled("total_hemoglobin_conc_min", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        56: .scaled("total_hemoglobin_conc_max", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        57: .scaled("saturated_hemoglobin_percent", units: "%", scale: 10, offset: 0, baseType: .uint16),
        58: .scaled("saturated_hemoglobin_percent_min", units: "%", scale: 10, offset: 0, baseType: .uint16),
        59: .scaled("saturated_hemoglobin_percent_max", units: "%", scale: 10, offset: 0, baseType: .uint16),
        62: .plain("device_index", units: "", baseType: .uint8),
        67: .plain("left_pco", units: "mm", baseType: .sint8),
        68: .plain("right_pco", units: "mm", baseType: .sint8),
        69: .scaled("left_power_phase", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        70: .scaled("left_power_phase_peak", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        71: .scaled("right_power_phase", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        72: .scaled("right_power_phase_peak", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        73: .scaled("enhanced_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint32),
        78: .scaled("enhanced_altitude", units: "m", scale: 5, offset: 500, baseType: .uint32),
        81: .scaled("battery_soc", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        82: .plain("motor_power", units: "watts", baseType: .uint16),
        83: .scaled("vertical_ratio", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        84: .scaled("stance_time_balance", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        85: .scaled("step_length", units: "mm", scale: 10, offset: 0, baseType: .uint16),
        87: .scaled("cycle_length16", units: "m", scale: 100, offset: 0, baseType: .uint16),
        91: .plain("absolute_pressure", units: "Pa", baseType: .uint32),
        92: .scaled("depth", units: "m", scale: 1000, offset: 0, baseType: .uint32),
        93: .scaled("next_stop_depth", units: "m", scale: 1000, offset: 0, baseType: .uint32),
        94: .plain("next_stop_time", units: "s", baseType: .uint32),
        95: .plain("time_to_surface", units: "s", baseType: .uint32),
        96: .plain("ndl_time", units: "s", baseType: .uint32),
        97: .plain("cns_load", units: "percent", baseType: .uint8),
        98: .plain("n2_load", units: "percent", baseType: .uint16),
        99: .plain("respiration_rate", units: "s", baseType: .uint8),
        108: .scaled("enhanced_respiration_rate", units: "Breaths/min", scale: 100, offset: 0, baseType: .uint16),
        114: .plain("grit", units: "", baseType: .float32),
        115: .plain("flow", units: "", baseType: .float32),
        116: .scaled("current_stress", units: "", scale: 100, offset: 0, baseType: .uint16),
        117: .plain("ebike_travel_range", units: "km", baseType: .uint16),
        118: .plain("ebike_battery_level", units: "percent", baseType: .uint8),
        119: .plain("ebike_assist_mode", units: "depends on sensor", baseType: .uint8),
        120: .plain("ebike_assist_level_percent", units: "percent", baseType: .uint8),
        123: .plain("air_time_remaining", units: "s", baseType: .uint32),
        124: .scaled("pressure_sac", units: "bar/min", scale: 100, offset: 0, baseType: .uint16),
        125: .scaled("volume_sac", units: "L/min", scale: 100, offset: 0, baseType: .uint16),
        126: .scaled("rmv", units: "L/min", scale: 100, offset: 0, baseType: .uint16),
        127: .scaled("ascent_rate", units: "m/s", scale: 1000, offset: 0, baseType: .sint32),
        129: .scaled("po2", units: "percent", scale: 100, offset: 0, baseType: .uint8),
        139: .scaled("core_temperature", units: "C", scale: 100, offset: 0, baseType: .uint16),
    ]

    // Message 19: lap
    private static let lapFields: [Int: FieldMeta] = [
        254: .plain("message_index", units: "", baseType: .uint16),
        253: .plain("timestamp", units: "s", baseType: .uint32, isDate: true),
        0: .plain("event", units: "", baseType: .enumType),
        1: .plain("event_type", units: "", baseType: .enumType),
        2: .plain("start_time", units: "", baseType: .uint32, isDate: true),
        3: .plain("start_position_lat", units: "semicircles", baseType: .sint32),
        4: .plain("start_position_long", units: "semicircles", baseType: .sint32),
        5: .plain("end_position_lat", units: "semicircles", baseType: .sint32),
        6: .plain("end_position_long", units: "semicircles", baseType: .sint32),
        7: .scaled("total_elapsed_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        8: .scaled("total_timer_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        9: .scaled("total_distance", units: "m", scale: 100, offset: 0, baseType: .uint32),
        10: .plain("total_cycles", units: "cycles", baseType: .uint32),
        11: .plain("total_calories", units: "kcal", baseType: .uint16),
        12: .plain("total_fat_calories", units: "kcal", baseType: .uint16),
        13: .scaled("avg_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint16),
        14: .scaled("max_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint16),
        15: .plain("avg_heart_rate", units: "bpm", baseType: .uint8),
        16: .plain("max_heart_rate", units: "bpm", baseType: .uint8),
        17: .plain("avg_cadence", units: "rpm", baseType: .uint8),
        18: .plain("max_cadence", units: "rpm", baseType: .uint8),
        19: .plain("avg_power", units: "watts", baseType: .uint16),
        20: .plain("max_power", units: "watts", baseType: .uint16),
        21: .plain("total_ascent", units: "m", baseType: .uint16),
        22: .plain("total_descent", units: "m", baseType: .uint16),
        23: .plain("intensity", units: "", baseType: .enumType),
        24: .plain("lap_trigger", units: "", baseType: .enumType),
        25: .plain("sport", units: "", baseType: .enumType),
        26: .plain("event_group", units: "", baseType: .uint8),
        32: .plain("num_lengths", units: "lengths", baseType: .uint16),
        33: .plain("normalized_power", units: "watts", baseType: .uint16),
        34: .plain("left_right_balance", units: "", baseType: .uint16),
        35: .plain("first_length_index", units: "", baseType: .uint16),
        37: .scaled("avg_stroke_distance", units: "m", scale: 100, offset: 0, baseType: .uint16),
        38: .plain("swim_stroke", units: "", baseType: .enumType),
        39: .plain("sub_sport", units: "", baseType: .enumType),
        40: .plain("num_active_lengths", units: "lengths", baseType: .uint16),
        41: .plain("total_work", units: "J", baseType: .uint32),
        42: .scaled("avg_altitude", units: "m", scale: 5, offset: 500, baseType: .uint16),
        43: .scaled("max_altitude", units: "m", scale: 5, offset: 500, baseType: .uint16),
        44: .plain("gps_accuracy", units: "m", baseType: .uint8),
        45: .scaled("avg_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        46: .scaled("avg_pos_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        47: .scaled("avg_neg_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        48: .scaled("max_pos_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        49: .scaled("max_neg_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        50: .plain("avg_temperature", units: "C", baseType: .sint8),
        51: .plain("max_temperature", units: "C", baseType: .sint8),
        52: .scaled("total_moving_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        53: .scaled("avg_pos_vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        54: .scaled("avg_neg_vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        55: .scaled("max_pos_vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        56: .scaled("max_neg_vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        57: .scaled("time_in_hr_zone", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        58: .scaled("time_in_speed_zone", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        59: .scaled("time_in_cadence_zone", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        60: .scaled("time_in_power_zone", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        61: .plain("repetition_num", units: "", baseType: .uint16),
        62: .scaled("min_altitude", units: "m", scale: 5, offset: 500, baseType: .uint16),
        63: .plain("min_heart_rate", units: "bpm", baseType: .uint8),
        70: .scaled("active_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        71: .plain("wkt_step_index", units: "", baseType: .uint16),
        74: .plain("opponent_score", units: "", baseType: .uint16),
        75: .plain("stroke_count", units: "counts", baseType: .uint16),
        76: .plain("zone_count", units: "counts", baseType: .uint16),
        77: .scaled("avg_vertical_oscillation", units: "mm", scale: 10, offset: 0, baseType: .uint16),
        78: .scaled("avg_stance_time_percent", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        79: .scaled("avg_stance_time", units: "ms", scale: 10, offset: 0, baseType: .uint16),
        80: .scaled("avg_fractional_cadence", units: "rpm", scale: 128, offset: 0, baseType: .uint8),
        81: .scaled("max_fractional_cadence", units: "rpm", scale: 128, offset: 0, baseType: .uint8),
        82: .scaled("total_fractional_cycles", units: "cycles", scale: 128, offset: 0, baseType: .uint8),
        83: .plain("player_score", units: "", baseType: .uint16),
        84: .scaled("avg_total_hemoglobin_conc", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        85: .scaled("min_total_hemoglobin_conc", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        86: .scaled("max_total_hemoglobin_conc", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        87: .scaled("avg_saturated_hemoglobin_percent", units: "%", scale: 10, offset: 0, baseType: .uint16),
        88: .scaled("min_saturated_hemoglobin_percent", units: "%", scale: 10, offset: 0, baseType: .uint16),
        89: .scaled("max_saturated_hemoglobin_percent", units: "%", scale: 10, offset: 0, baseType: .uint16),
        91: .scaled("avg_left_torque_effectiveness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        92: .scaled("avg_right_torque_effectiveness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        93: .scaled("avg_left_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        94: .scaled("avg_right_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        95: .scaled("avg_combined_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        98: .scaled("time_standing", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        99: .plain("stand_count", units: "", baseType: .uint16),
        100: .plain("avg_left_pco", units: "mm", baseType: .sint8),
        101: .plain("avg_right_pco", units: "mm", baseType: .sint8),
        102: .scaled("avg_left_power_phase", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        103: .scaled("avg_left_power_phase_peak", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        104: .scaled("avg_right_power_phase", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        105: .scaled("avg_right_power_phase_peak", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        106: .plain("avg_power_position", units: "watts", baseType: .uint16),
        107: .plain("max_power_position", units: "watts", baseType: .uint16),
        108: .plain("avg_cadence_position", units: "rpm", baseType: .uint8),
        109: .plain("max_cadence_position", units: "rpm", baseType: .uint8),
        110: .scaled("enhanced_avg_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint32),
        111: .scaled("enhanced_max_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint32),
        112: .scaled("enhanced_avg_altitude", units: "m", scale: 5, offset: 500, baseType: .uint32),
        113: .scaled("enhanced_min_altitude", units: "m", scale: 5, offset: 500, baseType: .uint32),
        114: .scaled("enhanced_max_altitude", units: "m", scale: 5, offset: 500, baseType: .uint32),
        115: .plain("avg_lev_motor_power", units: "watts", baseType: .uint16),
        116: .plain("max_lev_motor_power", units: "watts", baseType: .uint16),
        117: .scaled("lev_battery_consumption", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        118: .scaled("avg_vertical_ratio", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        119: .scaled("avg_stance_time_balance", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        120: .scaled("avg_step_length", units: "mm", scale: 10, offset: 0, baseType: .uint16),
        121: .scaled("avg_vam", units: "m/s", scale: 1000, offset: 0, baseType: .uint16),
        122: .scaled("avg_depth", units: "m", scale: 1000, offset: 0, baseType: .uint32),
        123: .scaled("max_depth", units: "m", scale: 1000, offset: 0, baseType: .uint32),
        124: .plain("min_temperature", units: "C", baseType: .sint8),
        136: .scaled("enhanced_avg_respiration_rate", units: "Breaths/min", scale: 100, offset: 0, baseType: .uint16),
        137: .scaled("enhanced_max_respiration_rate", units: "Breaths/min", scale: 100, offset: 0, baseType: .uint16),
        147: .plain("avg_respiration_rate", units: "", baseType: .uint8),
        148: .plain("max_respiration_rate", units: "", baseType: .uint8),
        149: .plain("total_grit", units: "kGrit", baseType: .float32),
        150: .plain("total_flow", units: "Flow", baseType: .float32),
        151: .plain("jump_count", units: "", baseType: .uint16),
        153: .plain("avg_grit", units: "kGrit", baseType: .float32),
        154: .plain("avg_flow", units: "Flow", baseType: .float32),
        156: .scaled("total_fractional_ascent", units: "m", scale: 100, offset: 0, baseType: .uint8),
        157: .scaled("total_fractional_descent", units: "m", scale: 100, offset: 0, baseType: .uint8),
        158: .scaled("avg_core_temperature", units: "C", scale: 100, offset: 0, baseType: .uint16),
        159: .scaled("min_core_temperature", units: "C", scale: 100, offset: 0, baseType: .uint16),
        160: .scaled("max_core_temperature", units: "C", scale: 100, offset: 0, baseType: .uint16),
    ]

    // Message 18: session
    private static let sessionFields: [Int: FieldMeta] = [
        254: .plain("message_index", units: "", baseType: .uint16),
        253: .plain("timestamp", units: "s", baseType: .uint32, isDate: true),
        0: .plain("event", units: "", baseType: .enumType),
        1: .plain("event_type", units: "", baseType: .enumType),
        2: .plain("start_time", units: "", baseType: .uint32, isDate: true),
        3: .plain("start_position_lat", units: "semicircles", baseType: .sint32),
        4: .plain("start_position_long", units: "semicircles", baseType: .sint32),
        5: .plain("sport", units: "", baseType: .enumType),
        6: .plain("sub_sport", units: "", baseType: .enumType),
        7: .scaled("total_elapsed_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        8: .scaled("total_timer_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        9: .scaled("total_distance", units: "m", scale: 100, offset: 0, baseType: .uint32),
        10: .plain("total_cycles", units: "cycles", baseType: .uint32),
        11: .plain("total_calories", units: "kcal", baseType: .uint16),
        13: .plain("total_fat_calories", units: "kcal", baseType: .uint16),
        14: .scaled("avg_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint16),
        15: .scaled("max_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint16),
        16: .plain("avg_heart_rate", units: "bpm", baseType: .uint8),
        17: .plain("max_heart_rate", units: "bpm", baseType: .uint8),
        18: .plain("avg_cadence", units: "rpm", baseType: .uint8),
        19: .plain("max_cadence", units: "rpm", baseType: .uint8),
        20: .plain("avg_power", units: "watts", baseType: .uint16),
        21: .plain("max_power", units: "watts", baseType: .uint16),
        22: .plain("total_ascent", units: "m", baseType: .uint16),
        23: .plain("total_descent", units: "m", baseType: .uint16),
        24: .scaled("total_training_effect", units: "", scale: 10, offset: 0, baseType: .uint8),
        25: .plain("first_lap_index", units: "", baseType: .uint16),
        26: .plain("num_laps", units: "", baseType: .uint16),
        27: .plain("event_group", units: "", baseType: .uint8),
        28: .plain("trigger", units: "", baseType: .enumType),
        29: .plain("nec_lat", units: "semicircles", baseType: .sint32),
        30: .plain("nec_long", units: "semicircles", baseType: .sint32),
        31: .plain("swc_lat", units: "semicircles", baseType: .sint32),
        32: .plain("swc_long", units: "semicircles", baseType: .sint32),
        33: .plain("num_lengths", units: "lengths", baseType: .uint16),
        34: .plain("normalized_power", units: "watts", baseType: .uint16),
        35: .scaled("training_stress_score", units: "tss", scale: 10, offset: 0, baseType: .uint16),
        36: .scaled("intensity_factor", units: "if", scale: 1000, offset: 0, baseType: .uint16),
        37: .plain("left_right_balance", units: "", baseType: .uint16),
        38: .plain("end_position_lat", units: "semicircles", baseType: .sint32),
        39: .plain("end_position_long", units: "semicircles", baseType: .sint32),
        41: .scaled("avg_stroke_count", units: "strokes/lap", scale: 10, offset: 0, baseType: .uint32),
        42: .scaled("avg_stroke_distance", units: "m", scale: 100, offset: 0, baseType: .uint16),
        43: .plain("swim_stroke", units: "swim_stroke", baseType: .enumType),
        44: .scaled("pool_length", units: "m", scale: 100, offset: 0, baseType: .uint16),
        45: .plain("threshold_power", units: "watts", baseType: .uint16),
        46: .plain("pool_length_unit", units: "", baseType: .enumType),
        47: .plain("num_active_lengths", units: "lengths", baseType: .uint16),
        48: .plain("total_work", units: "J", baseType: .uint32),
        49: .scaled("avg_altitude", units: "m", scale: 5, offset: 500, baseType: .uint16),
        50: .scaled("max_altitude", units: "m", scale: 5, offset: 500, baseType: .uint16),
        51: .plain("gps_accuracy", units: "m", baseType: .uint8),
        52: .scaled("avg_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        53: .scaled("avg_pos_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        54: .scaled("avg_neg_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        55: .scaled("max_pos_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        56: .scaled("max_neg_grade", units: "%", scale: 100, offset: 0, baseType: .sint16),
        57: .plain("avg_temperature", units: "C", baseType: .sint8),
        58: .plain("max_temperature", units: "C", baseType: .sint8),
        59: .scaled("total_moving_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        60: .scaled("avg_pos_vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        61: .scaled("avg_neg_vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        62: .scaled("max_pos_vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        63: .scaled("max_neg_vertical_speed", units: "m/s", scale: 1000, offset: 0, baseType: .sint16),
        64: .plain("min_heart_rate", units: "bpm", baseType: .uint8),
        65: .scaled("time_in_hr_zone", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        66: .scaled("time_in_speed_zone", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        67: .scaled("time_in_cadence_zone", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        68: .scaled("time_in_power_zone", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        69: .scaled("avg_lap_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        70: .plain("best_lap_index", units: "", baseType: .uint16),
        71: .scaled("min_altitude", units: "m", scale: 5, offset: 500, baseType: .uint16),
        78: .scaled("active_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        82: .plain("player_score", units: "", baseType: .uint16),
        83: .plain("opponent_score", units: "", baseType: .uint16),
        84: .plain("opponent_name", units: "", baseType: .string),
        85: .plain("stroke_count", units: "counts", baseType: .uint16),
        86: .plain("zone_count", units: "counts", baseType: .uint16),
        87: .scaled("max_ball_speed", units: "m/s", scale: 100, offset: 0, baseType: .uint16),
        88: .scaled("avg_ball_speed", units: "m/s", scale: 100, offset: 0, baseType: .uint16),
        89: .scaled("avg_vertical_oscillation", units: "mm", scale: 10, offset: 0, baseType: .uint16),
        90: .scaled("avg_stance_time_percent", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        91: .scaled("avg_stance_time", units: "ms", scale: 10, offset: 0, baseType: .uint16),
        92: .scaled("avg_fractional_cadence", units: "rpm", scale: 128, offset: 0, baseType: .uint8),
        93: .scaled("max_fractional_cadence", units: "rpm", scale: 128, offset: 0, baseType: .uint8),
        94: .scaled("total_fractional_cycles", units: "cycles", scale: 128, offset: 0, baseType: .uint8),
        95: .scaled("avg_total_hemoglobin_conc", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        96: .scaled("min_total_hemoglobin_conc", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        97: .scaled("max_total_hemoglobin_conc", units: "g/dL", scale: 100, offset: 0, baseType: .uint16),
        98: .scaled("avg_saturated_hemoglobin_percent", units: "%", scale: 10, offset: 0, baseType: .uint16),
        99: .scaled("min_saturated_hemoglobin_percent", units: "%", scale: 10, offset: 0, baseType: .uint16),
        100: .scaled("max_saturated_hemoglobin_percent", units: "%", scale: 10, offset: 0, baseType: .uint16),
        101: .scaled("avg_left_torque_effectiveness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        102: .scaled("avg_right_torque_effectiveness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        103: .scaled("avg_left_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        104: .scaled("avg_right_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        105: .scaled("avg_combined_pedal_smoothness", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        110: .plain("sport_profile_name", units: "", baseType: .string),
        111: .plain("sport_index", units: "", baseType: .uint8),
        112: .scaled("time_standing", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        113: .plain("stand_count", units: "", baseType: .uint16),
        114: .plain("avg_left_pco", units: "mm", baseType: .sint8),
        115: .plain("avg_right_pco", units: "mm", baseType: .sint8),
        116: .scaled("avg_left_power_phase", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        117: .scaled("avg_left_power_phase_peak", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        118: .scaled("avg_right_power_phase", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        119: .scaled("avg_right_power_phase_peak", units: "degrees", scale: 0.7111111, offset: 0, baseType: .uint8),
        120: .plain("avg_power_position", units: "watts", baseType: .uint16),
        121: .plain("max_power_position", units: "watts", baseType: .uint16),
        122: .plain("avg_cadence_position", units: "rpm", baseType: .uint8),
        123: .plain("max_cadence_position", units: "rpm", baseType: .uint8),
        124: .scaled("enhanced_avg_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint32),
        125: .scaled("enhanced_max_speed", units: "m/s", scale: 1000, offset: 0, baseType: .uint32),
        126: .scaled("enhanced_avg_altitude", units: "m", scale: 5, offset: 500, baseType: .uint32),
        127: .scaled("enhanced_min_altitude", units: "m", scale: 5, offset: 500, baseType: .uint32),
        128: .scaled("enhanced_max_altitude", units: "m", scale: 5, offset: 500, baseType: .uint32),
        129: .plain("avg_lev_motor_power", units: "watts", baseType: .uint16),
        130: .plain("max_lev_motor_power", units: "watts", baseType: .uint16),
        131: .scaled("lev_battery_consumption", units: "percent", scale: 2, offset: 0, baseType: .uint8),
        132: .scaled("avg_vertical_ratio", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        133: .scaled("avg_stance_time_balance", units: "percent", scale: 100, offset: 0, baseType: .uint16),
        134: .scaled("avg_step_length", units: "mm", scale: 10, offset: 0, baseType: .uint16),
        137: .scaled("total_anaerobic_training_effect", units: "", scale: 10, offset: 0, baseType: .uint8),
        139: .scaled("avg_vam", units: "m/s", scale: 1000, offset: 0, baseType: .uint16),
        140: .scaled("avg_depth", units: "m", scale: 1000, offset: 0, baseType: .uint32),
        141: .scaled("max_depth", units: "m", scale: 1000, offset: 0, baseType: .uint32),
        142: .plain("surface_interval", units: "s", baseType: .uint32),
        143: .plain("start_cns", units: "percent", baseType: .uint8),
        144: .plain("end_cns", units: "percent", baseType: .uint8),
        145: .plain("start_n2", units: "percent", baseType: .uint16),
        146: .plain("end_n2", units: "percent", baseType: .uint16),
        147: .plain("avg_respiration_rate", units: "", baseType: .uint8),
        148: .plain("max_respiration_rate", units: "", baseType: .uint8),
        149: .plain("min_respiration_rate", units: "", baseType: .uint8),
        150: .plain("min_temperature", units: "C", baseType: .sint8),
        155: .plain("o2_toxicity", units: "OTUs", baseType: .uint16),
        156: .plain("dive_number", units: "", baseType: .uint32),
        168: .scaled("training_load_peak", units: "", scale: 65536, offset: 0, baseType: .sint32),
        169: .scaled("enhanced_avg_respiration_rate", units: "Breaths/min", scale: 100, offset: 0, baseType: .uint16),
        170: .scaled("enhanced_max_respiration_rate", units: "Breaths/min", scale: 100, offset: 0, baseType: .uint16),
        180: .scaled("enhanced_min_respiration_rate", units: "", scale: 100, offset: 0, baseType: .uint16),
        181: .plain("total_grit", units: "kGrit", baseType: .float32),
        182: .plain("total_flow", units: "Flow", baseType: .float32),
        183: .plain("jump_count", units: "", baseType: .uint16),
        186: .plain("avg_grit", units: "kGrit", baseType: .float32),
        187: .plain("avg_flow", units: "Flow", baseType: .float32),
        192: .plain("workout_feel", units: "", baseType: .uint8),
        193: .plain("workout_rpe", units: "", baseType: .uint8),
        194: .plain("avg_spo2", units: "percent", baseType: .uint8),
        195: .plain("avg_stress", units: "percent", baseType: .uint8),
        196: .plain("metabolic_calories", units: "kcal", baseType: .uint16),
        197: .plain("sdrr_hrv", units: "mS", baseType: .uint8),
        198: .plain("rmssd_hrv", units: "mS", baseType: .uint8),
        199: .scaled("total_fractional_ascent", units: "m", scale: 100, offset: 0, baseType: .uint8),
        200: .scaled("total_fractional_descent", units: "m", scale: 100, offset: 0, baseType: .uint8),
        208: .scaled("avg_core_temperature", units: "C", scale: 100, offset: 0, baseType: .uint16),
        209: .scaled("min_core_temperature", units: "C", scale: 100, offset: 0, baseType: .uint16),
        210: .scaled("max_core_temperature", units: "C", scale: 100, offset: 0, baseType: .uint16),
    ]

    // Message 21: event
    private static let eventFields: [Int: FieldMeta] = [
        253: .plain("timestamp", units: "s", baseType: .uint32, isDate: true),
        0: .plain("event", units: "", baseType: .enumType),
        1: .plain("event_type", units: "", baseType: .enumType),
        2: .plain("data16", units: "", baseType: .uint16),
        3: .plain("data", units: "", baseType: .uint32),
        4: .plain("event_group", units: "", baseType: .uint8),
        7: .plain("score", units: "", baseType: .uint16),
        8: .plain("opponent_score", units: "", baseType: .uint16),
        9: .plain("front_gear_num", units: "", baseType: .uint8z),
        10: .plain("front_gear", units: "", baseType: .uint8z),
        11: .plain("rear_gear_num", units: "", baseType: .uint8z),
        12: .plain("rear_gear", units: "", baseType: .uint8z),
        13: .plain("device_index", units: "", baseType: .uint8),
        14: .plain("activity_type", units: "", baseType: .enumType),
        15: .plain("start_timestamp", units: "s", baseType: .uint32, isDate: true),
        21: .plain("radar_threat_level_max", units: "", baseType: .enumType),
        22: .plain("radar_threat_count", units: "", baseType: .uint8),
        23: .scaled("radar_threat_avg_approach_speed", units: "m/s", scale: 10, offset: 0, baseType: .uint8),
        24: .scaled("radar_threat_max_approach_speed", units: "m/s", scale: 10, offset: 0, baseType: .uint8),
    ]

    // Message 34: activity
    private static let activityFields: [Int: FieldMeta] = [
        253: .plain("timestamp", units: "", baseType: .uint32, isDate: true),
        0: .scaled("total_timer_time", units: "s", scale: 1000, offset: 0, baseType: .uint32),
        1: .plain("num_sessions", units: "", baseType: .uint16),
        2: .plain("type", units: "", baseType: .enumType),
        3: .plain("event", units: "", baseType: .enumType),
        4: .plain("event_type", units: "", baseType: .enumType),
        5: .plain("local_timestamp", units: "", baseType: .uint32, isDate: true),
        6: .plain("event_group", units: "", baseType: .uint8),
    ]

    // Message 23: device_info
    private static let deviceInfoFields: [Int: FieldMeta] = [
        253: .plain("timestamp", units: "s", baseType: .uint32, isDate: true),
        0: .plain("device_index", units: "", baseType: .uint8),
        1: .plain("device_type", units: "", baseType: .uint8),
        2: .plain("manufacturer", units: "", baseType: .uint16),
        3: .plain("serial_number", units: "", baseType: .uint32z),
        4: .plain("product", units: "", baseType: .uint16),
        5: .scaled("software_version", units: "", scale: 100, offset: 0, baseType: .uint16),
        6: .plain("hardware_version", units: "", baseType: .uint8),
        7: .plain("cum_operating_time", units: "s", baseType: .uint32),
        10: .scaled("battery_voltage", units: "V", scale: 256, offset: 0, baseType: .uint16),
        11: .plain("battery_status", units: "", baseType: .uint8),
        18: .plain("sensor_position", units: "", baseType: .enumType),
        19: .plain("descriptor", units: "", baseType: .string),
        20: .plain("ant_transmission_type", units: "", baseType: .uint8z),
        21: .plain("ant_device_number", units: "", baseType: .uint16z),
        22: .plain("ant_network", units: "", baseType: .enumType),
        25: .plain("source_type", units: "", baseType: .enumType),
        27: .plain("product_name", units: "", baseType: .string),
        32: .plain("battery_level", units: "%", baseType: .uint8),
    ]

}
