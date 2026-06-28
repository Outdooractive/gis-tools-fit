import Foundation

/// Known FIT message types and their field definitions.
/// These are derived from the public FIT Profile specification.
enum FITProfile {

    // MARK: - Known message numbers

    enum MesgNum: UInt16 {
        case fileId = 0
        case capabilities = 2
        case deviceSettings = 4
        case userProfile = 5
        case hrmProfile = 6
        case sdmProfile = 7
        case bikeProfile = 8
        case lap = 9
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

        static func plain(_ name: String, units: String = "", fieldType: String = "") -> FieldMeta {
            FieldMeta(name: name, units: units, scale: 1.0, offset: 0.0, fieldType: fieldType)
        }

        static func scaled(_ name: String, units: String, scale: Double, offset: Double = 0.0) -> FieldMeta {
            FieldMeta(name: name, units: units, scale: scale, offset: offset, fieldType: "")
        }

        func formatValue(_ raw: Any) -> Any? {
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
    }

    // MARK: - Field lookup

    /// Returns the field metadata for a given message and field number.
    static func fieldMetadata(mesgNum: UInt16, fieldNum: Int) -> FieldMeta? {
        guard let msg = knownMessages[MesgNum(mesgNum)] else { return nil }
        return msg[fieldNum]
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
        0: .plain("type", fieldType: "fit_file"),
        1: .plain("manufacturer", fieldType: "manufacturer"),
        2: .plain("product", fieldType: "uint16"),
        3: .plain("serial_number", fieldType: "uint32z"),
        4: .plain("time_created", fieldType: "date_time"),
        5: .plain("number", fieldType: "uint16"),
        8: .plain("product_name", fieldType: "string"),
    ]

    // Message 20: record
    private static let recordFields: [Int: FieldMeta] = [
        253: .plain("timestamp", fieldType: "date_time"),
        0: .plain("position_lat", units: "semicircles"),
        1: .plain("position_long", units: "semicircles"),
        2: .scaled("altitude", units: "m", scale: 5.0, offset: 500.0),
        3: .plain("heart_rate", units: "bpm"),
        4: .plain("cadence", units: "rpm"),
        5: .scaled("distance", units: "m", scale: 100.0),
        6: .scaled("speed", units: "m/s", scale: 1000.0),
        7: .plain("power", units: "watts"),
        8: .scaled("enhanced_speed", units: "m/s", scale: 1000.0),
        9: .scaled("enhanced_altitude", units: "m", scale: 5.0, offset: 500.0),
        11: .plain("grade", units: "%"),
        12: .plain("accumulated_power", units: "watts"),
        13: .plain("left_right_balance", fieldType: "uint8"),
        17: .plain("compressed_accumulated_power", fieldType: "uint16"),
        18: .scaled("vertical_oscillation", units: "mm", scale: 10.0),
        19: .scaled("stance_time", units: "ms", scale: 10.0),
        28: .plain("stance_time_balance", units: "%"),
        29: .plain("accelerometer_frequency", fieldType: "uint16"),
        30: .plain("linear_acceleration_vertical", fieldType: "float32"),
        31: .plain("grit", fieldType: "float32"),
        32: .plain("flow", fieldType: "float32"),
        39: .plain("vertical_ratio", fieldType: "float32"),
        40: .plain("stance_time_ratio", fieldType: "float32"),
        41: .scaled("step_length", units: "mm", scale: 10.0),
        42: .scaled("cycle_length16", units: "mm", scale: 5.0),
        43: .scaled("absolute_pressure", units: "Pa", scale: 1.0),
        44: .scaled("depth", units: "m", scale: 1000.0),
        45: .scaled("next_stop_depth", units: "m", scale: 1000.0),
        46: .plain("next_stop_time", units: "min"),
        47: .plain("next_stop_distance", units: "m"),
        48: .plain("time_underwater", units: "s"),
        49: .plain("time_above_water", units: "s"),
        50: .plain("next_stop_gas", fieldType: "uint8"),
        51: .scaled("maximum_depth", units: "m", scale: 1000.0),
        52: .plain("gas_type", fieldType: "uint8"),
        53: .scaled("gas_usage_rate", units: "L/min", scale: 100.0),
        54: .scaled("gas_consumed", units: "L", scale: 100.0),
        55: .scaled("salinity", units: "ppt", scale: 1000.0),
        56: .plain("heart_rate_alert", fieldType: "uint8"),
        57: .plain("cadence_alert", fieldType: "uint8"),
        58: .plain("speed_alert", fieldType: "uint8"),
        59: .plain("power_alert", fieldType: "uint8"),
        60: .plain("heart_rate_zone", fieldType: "uint8"),
        61: .plain("cadence_zone", fieldType: "uint8"),
        62: .plain("speed_zone", fieldType: "uint8"),
        63: .plain("power_zone", fieldType: "uint8"),
        64: .scaled("ball_speed", units: "m/s", scale: 100.0),
        65: .scaled("cadence256", units: "rpm", scale: 256.0),
        66: .scaled("fractional_cadence", units: "rpm", scale: 128.0),
        67: .scaled("total_hemoglobin_conc", units: "g/dL", scale: 100.0),
        68: .scaled("total_hemoglobin_conc_min", units: "g/dL", scale: 100.0),
        69: .scaled("total_hemoglobin_conc_max", units: "g/dL", scale: 100.0),
        70: .scaled("saturated_hemoglobin_percent", units: "%", scale: 10.0),
        71: .scaled("saturated_hemoglobin_percent_min", units: "%", scale: 10.0),
        72: .scaled("saturated_hemoglobin_percent_max", units: "%", scale: 10.0),
        73: .plain("device_index", fieldType: "uint8"),
        75: .plain("min_heart_rate", fieldType: "uint8"),
        76: .plain("avg_heart_rate", fieldType: "uint8"),
        77: .plain("max_heart_rate", fieldType: "uint8"),
        78: .plain("temperature", units: "C"),
        83: .plain("activity_type", fieldType: "activity_type"),
        84: .plain("left_torque_effectiveness", units: "%"),
        85: .plain("right_torque_effectiveness", units: "%"),
        86: .plain("left_pedal_smoothness", units: "%"),
        87: .plain("right_pedal_smoothness", units: "%"),
        88: .plain("combined_pedal_smoothness", units: "%"),
        89: .scaled("time128", units: "s", scale: 128.0),
        90: .plain("stroke_type", fieldType: "stroke_type"),
        91: .plain("zone", fieldType: "uint8"),
        92: .plain("event", fieldType: "event"),
        93: .plain("event_type", fieldType: "event_type"),
        94: .scaled("avg_vertical_oscillation", units: "mm", scale: 10.0),
        95: .scaled("avg_stance_time", units: "ms", scale: 10.0),
        96: .plain("avg_stance_time_balance", units: "%"),
        98: .scaled("avg_step_length", units: "mm", scale: 10.0),
        99: .scaled("total_anaerobic_training_effect", units: "FE", scale: 10.0),
        100: .scaled("avg_vam", units: "m/s", scale: 1000.0),
        101: .plain("timing_code", fieldType: "timing_code"),
    ]

    // Message 9: lap
    private static let lapFields: [Int: FieldMeta] = [
        253: .plain("timestamp", fieldType: "date_time"),
        0: .plain("start_time", fieldType: "date_time"),
        1: .plain("start_position_lat", units: "semicircles"),
        2: .plain("start_position_long", units: "semicircles"),
        3: .plain("end_position_lat", units: "semicircles"),
        4: .plain("end_position_long", units: "semicircles"),
        5: .scaled("total_elapsed_time", units: "s", scale: 1000.0),
        6: .scaled("total_timer_time", units: "s", scale: 1000.0),
        7: .scaled("total_distance", units: "m", scale: 100.0),
        8: .scaled("total_cycles", units: "", scale: 1.0),
        9: .plain("total_calories", units: "kcal"),
        10: .plain("total_fat_calories", units: "kcal"),
        11: .scaled("avg_speed", units: "m/s", scale: 1000.0),
        12: .scaled("max_speed", units: "m/s", scale: 1000.0),
        13: .plain("avg_heart_rate", units: "bpm"),
        14: .plain("max_heart_rate", units: "bpm"),
        15: .plain("avg_cadence", units: "rpm"),
        16: .plain("max_cadence", units: "rpm"),
        17: .plain("avg_power", units: "watts"),
        18: .plain("max_power", units: "watts"),
        19: .scaled("total_ascent", units: "m", scale: 5.0, offset: 500.0),
        20: .scaled("total_descent", units: "m", scale: 5.0, offset: 500.0),
        21: .plain("num_attachments", fieldType: "uint16"),
        22: .plain("num_lengths", fieldType: "uint16"),
        23: .plain("num_splits", fieldType: "uint16"),
        24: .plain("event", fieldType: "event"),
        25: .plain("event_type", fieldType: "event_type"),
        26: .plain("sub_sport", fieldType: "sub_sport"),
        27: .plain("avg_grade", units: "%"),
        28: .plain("avg_vertical_ratio", fieldType: "float32"),
        29: .plain("avg_stance_time_balance", units: "%"),
        30: .scaled("avg_step_length", units: "mm", scale: 10.0),
        31: .scaled("total_anaerobic_effect", units: "FE", scale: 10.0),
        32: .scaled("avg_vam", units: "m/s", scale: 1000.0),
        33: .plain("avg_grit", fieldType: "float32"),
        34: .plain("avg_flow", fieldType: "float32"),
        35: .scaled("avg_fractional_cadence", units: "rpm", scale: 128.0),
        36: .scaled("max_fractional_cadence", units: "rpm", scale: 128.0),
        37: .scaled("total_fractional_cycles", units: "", scale: 128.0),
        38: .scaled("player_score", units: "", scale: 100.0),
        39: .scaled("avg_total_hemoglobin_conc", units: "g/dL", scale: 100.0),
        40: .scaled("min_total_hemoglobin_conc", units: "g/dL", scale: 100.0),
        41: .scaled("max_total_hemoglobin_conc", units: "g/dL", scale: 100.0),
        42: .scaled("avg_saturated_hemoglobin_percent", units: "%", scale: 10.0),
        43: .scaled("min_saturated_hemoglobin_percent", units: "%", scale: 10.0),
        44: .scaled("max_saturated_hemoglobin_percent", units: "%", scale: 10.0),
        45: .plain("avg_left_torque_effectiveness", units: "%"),
        46: .plain("avg_right_torque_effectiveness", units: "%"),
        47: .plain("avg_left_pedal_smoothness", units: "%"),
        48: .plain("avg_right_pedal_smoothness", units: "%"),
        49: .plain("avg_combined_pedal_smoothness", units: "%"),
        50: .scaled("time_in_hr_zone", units: "s", scale: 1000.0),
        51: .scaled("time_in_speed_zone", units: "s", scale: 1000.0),
        52: .scaled("time_in_cadence_zone", units: "s", scale: 1000.0),
        53: .scaled("time_in_power_zone", units: "s", scale: 1000.0),
        54: .scaled("avg_lap_time", units: "s", scale: 1000.0),
        55: .plain("stand_count", fieldType: "uint16"),
        56: .scaled("avg_vertical_oscillation", units: "mm", scale: 10.0),
        57: .scaled("avg_stance_time", units: "ms", scale: 10.0),
        58: .plain("avg_stance_time_percent", units: "%"),
        59: .plain("avg_stance_time_balance", units: "%"),
        60: .plain("num_active_lengths", fieldType: "uint16"),
        61: .scaled("avg_total_hemoglobin_conc", units: "g/dL", scale: 100.0),
        62: .scaled("min_total_hemoglobin_conc", units: "g/dL", scale: 100.0),
        63: .scaled("max_total_hemoglobin_conc", units: "g/dL", scale: 100.0),
        64: .scaled("avg_saturated_hemoglobin_percent", units: "%", scale: 10.0),
        65: .scaled("min_saturated_hemoglobin_percent", units: "%", scale: 10.0),
        66: .scaled("max_saturated_hemoglobin_percent", units: "%", scale: 10.0),
    ]

    // Message 18: session
    private static let sessionFields: [Int: FieldMeta] = [
        253: .plain("timestamp", fieldType: "date_time"),
        0: .plain("start_time", fieldType: "date_time"),
        1: .plain("start_position_lat", units: "semicircles"),
        2: .plain("start_position_long", units: "semicircles"),
        3: .plain("end_position_lat", units: "semicircles"),
        4: .plain("end_position_long", units: "semicircles"),
        5: .scaled("total_elapsed_time", units: "s", scale: 1000.0),
        6: .scaled("total_timer_time", units: "s", scale: 1000.0),
        7: .scaled("total_distance", units: "m", scale: 100.0),
        8: .scaled("total_cycles", units: "", scale: 1.0),
        9: .plain("total_calories", units: "kcal"),
        10: .plain("total_fat_calories", units: "kcal"),
        11: .scaled("avg_speed", units: "m/s", scale: 1000.0),
        12: .scaled("max_speed", units: "m/s", scale: 1000.0),
        13: .plain("avg_heart_rate", units: "bpm"),
        14: .plain("max_heart_rate", units: "bpm"),
        15: .plain("avg_cadence", units: "rpm"),
        16: .plain("max_cadence", units: "rpm"),
        17: .plain("avg_power", units: "watts"),
        18: .plain("max_power", units: "watts"),
        19: .scaled("total_ascent", units: "m", scale: 5.0),
        20: .scaled("total_descent", units: "m", scale: 5.0),
        21: .plain("event", fieldType: "event"),
        22: .plain("event_type", fieldType: "event_type"),
        23: .plain("sport", fieldType: "sport"),
        24: .plain("sub_sport", fieldType: "sub_sport"),
        25: .plain("avg_heart_rate", units: "bpm"),
        26: .plain("max_heart_rate", units: "bpm"),
        27: .plain("avg_cadence", units: "rpm"),
        28: .plain("max_cadence", units: "rpm"),
        29: .plain("avg_power", units: "watts"),
        30: .plain("max_power", units: "watts"),
        31: .scaled("total_anaerobic_effect", units: "FE", scale: 10.0),
        32: .scaled("avg_vertical_oscillation", units: "mm", scale: 10.0),
        33: .scaled("avg_stance_time", units: "ms", scale: 10.0),
        34: .plain("avg_stance_time_balance", units: "%"),
        35: .plain("num_laps", fieldType: "uint16"),
        36: .plain("num_attachments", fieldType: "uint16"),
        37: .scaled("avg_step_length", units: "mm", scale: 10.0),
    ]

    // Message 21: event
    private static let eventFields: [Int: FieldMeta] = [
        253: .plain("timestamp", fieldType: "date_time"),
        0: .plain("event", fieldType: "event"),
        1: .plain("event_type", fieldType: "event_type"),
        2: .scaled("data16", units: "", scale: 1.0),
        3: .scaled("data", units: "", scale: 1.0),
        4: .scaled("data_extension", units: "", scale: 1.0),
        5: .scaled("unknown_extension", units: "", scale: 1.0),
    ]

    // Message 34: activity
    private static let activityFields: [Int: FieldMeta] = [
        253: .plain("timestamp", fieldType: "date_time"),
        0: .scaled("total_timer_time", units: "s", scale: 1000.0),
        1: .scaled("num_sessions", units: "", scale: 1.0),
        2: .plain("type", fieldType: "activity"),
        3: .plain("event", fieldType: "event"),
        4: .plain("event_type", fieldType: "event_type"),
        5: .plain("local_timestamp", fieldType: "date_time"),
        6: .plain("num_lengths", fieldType: "uint16"),
    ]

    // Message 23: device_info
    private static let deviceInfoFields: [Int: FieldMeta] = [
        253: .plain("timestamp", fieldType: "date_time"),
        0: .plain("device_index", fieldType: "uint8"),
        1: .plain("device_type", fieldType: "uint8"),
        2: .plain("manufacturer", fieldType: "manufacturer"),
        3: .plain("serial_number", fieldType: "uint32z"),
        4: .plain("product", fieldType: "uint16"),
        5: .scaled("software_version", units: "", scale: 100.0),
        6: .plain("hardware_version", fieldType: "uint8"),
        7: .scaled("battery_voltage", units: "V", scale: 256.0),
        8: .plain("battery_status", fieldType: "battery_status"),
        9: .plain("sensor_position", fieldType: "body_location"),
        10: .plain("descriptor", fieldType: "string"),
        11: .plain("ant_transmission_type", fieldType: "uint8z"),
        12: .plain("ant_device_number", fieldType: "uint16z"),
        13: .plain("ant_network", fieldType: "ant_network"),
        14: .plain("source_type", fieldType: "source_type"),
        15: .plain("product_name", fieldType: "string"),
    ]

}
