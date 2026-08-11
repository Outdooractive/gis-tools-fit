import Foundation

/// FIT enum value → name lookup.
///
/// FIT stores enum-typed fields (e.g. `event`, `sport`, `event_type`) as raw
/// integers. These methods provide the value → name lookup so users can turn a
/// decoded value like `event: 9` into `"lap"`.
extension FIT {

    /// Returns the human-readable name for an enum value, or `nil` if the
    /// value is not a known member of the given field type.
    ///
    /// - Parameters:
    ///   - fieldType: The FIT field type name (e.g. `"event"`, `"sport"`).
    ///     Field names that differ from their type name (e.g. `"trigger"` for
    ///     `session_trigger`) are resolved automatically.
    ///   - value: The raw integer value.
    /// - Returns: The name, or `nil` if unknown.
    public static func name(for fieldType: String, value: Int) -> String? {
        let type = fieldAliases[fieldType] ?? fieldType
        guard let table = tables[type] else { return nil }
        return table[value]
    }

    /// Returns the human-readable name for an enum value, or `nil`.
    public static func name(for fieldType: String, value: UInt8) -> String? {
        name(for: fieldType, value: Int(value))
    }

    /// Returns the human-readable name for an enum value, or `nil`.
    public static func name(for fieldType: String, value: UInt16) -> String? {
        name(for: fieldType, value: Int(value))
    }

    /// The value → name tables for the enum field types used by the FIT
    /// messages this library decodes.
    private static let tables: [String: [Int: String]] = [
        "event": [
            0: "timer", 3: "workout", 4: "workout_step", 5: "power_down",
            6: "power_up", 7: "off_course", 8: "session", 9: "lap",
            10: "course_point", 11: "battery", 12: "virtual_partner_pace",
            13: "hr_high_alert", 14: "hr_low_alert", 15: "speed_high_alert",
            16: "speed_low_alert", 17: "cad_high_alert", 18: "cad_low_alert",
            19: "power_high_alert", 20: "power_low_alert", 21: "recovery_hr",
            22: "battery_low", 23: "time_duration_alert",
            24: "distance_duration_alert", 25: "calorie_duration_alert",
            26: "activity", 27: "fitness_equipment", 28: "length",
            32: "user_marker", 33: "sport_point", 36: "calibration",
            42: "front_gear_change", 43: "rear_gear_change",
            44: "rider_position_change", 45: "elev_high_alert",
            46: "elev_low_alert", 47: "comm_timeout", 54: "auto_activity_detect",
            56: "dive_alert", 57: "dive_gas_switched", 71: "tank_pressure_reserve",
            72: "tank_pressure_critical", 73: "tank_lost",
            75: "radar_threat_alert", 76: "tank_battery_low",
            81: "tank_pod_connected", 82: "tank_pod_disconnected",
        ],
        "event_type": [
            0: "start", 1: "stop", 2: "consecutive_depreciated", 3: "marker",
            4: "stop_all", 5: "begin_depreciated", 6: "end_depreciated",
            7: "end_all_depreciated", 8: "stop_disable", 9: "stop_disable_all",
        ],
        "sport": [
            0: "generic", 1: "running", 2: "cycling", 3: "transition",
            4: "fitness_equipment", 5: "swimming", 6: "basketball",
            7: "soccer", 8: "tennis", 9: "american_football", 10: "training",
            11: "walking", 12: "cross_country_skiing", 13: "alpine_skiing",
            14: "snowboarding", 15: "rowing", 16: "mountaineering",
            17: "hiking", 18: "multisport", 19: "paddling", 20: "flying",
            21: "e_biking", 22: "motorcycling", 23: "boating", 24: "driving",
            25: "golf", 26: "hang_gliding", 27: "horseback_riding",
            28: "hunting", 29: "fishing", 30: "inline_skating",
            31: "rock_climbing", 32: "sailing", 33: "ice_skating",
            34: "sky_diving", 35: "snowshoeing", 36: "snowmobiling",
            37: "stand_up_paddleboarding", 38: "surfing", 39: "wakeboarding",
            40: "water_skiing", 41: "kayaking", 42: "rafting",
            43: "windsurfing", 44: "kitesurfing", 45: "tactical",
            46: "jumpmaster", 47: "boxing", 48: "floor_climbing",
            49: "baseball", 53: "diving", 56: "shooting", 58: "winter_sport",
            59: "grinding", 62: "hiit", 63: "video_gaming", 64: "racket",
            65: "wheelchair_push_walk", 66: "wheelchair_push_run",
            67: "meditation", 68: "para_sport", 69: "disc_golf",
            70: "team_sport", 71: "cricket", 72: "rugby", 73: "hockey",
            74: "lacrosse", 75: "volleyball", 76: "water_tubing",
            77: "wakesurfing", 78: "water_sport", 79: "archery",
            80: "mixed_martial_arts", 81: "motor_sports", 82: "snorkeling",
            83: "dance", 84: "jump_rope", 85: "pool_apnea", 86: "mobility",
            87: "geocaching", 88: "canoeing", 254: "all",
        ],
        "sub_sport": [
            0: "generic", 1: "treadmill", 2: "street", 3: "trail", 4: "track",
            5: "spin", 6: "indoor_cycling", 7: "road", 8: "mountain",
            9: "downhill", 10: "recumbent", 11: "cyclocross",
            12: "hand_cycling", 13: "track_cycling", 14: "indoor_rowing",
            15: "elliptical", 16: "stair_climbing", 17: "lap_swimming",
            18: "open_water", 19: "flexibility_training",
            20: "strength_training", 21: "warm_up", 22: "match",
            23: "exercise", 24: "challenge", 25: "indoor_skiing",
            26: "cardio_training", 27: "indoor_walking", 28: "e_bike_fitness",
            29: "bmx", 30: "casual_walking", 31: "speed_walking",
            32: "bike_to_run_transition", 33: "run_to_bike_transition",
            34: "swim_to_bike_transition", 35: "atv", 36: "motocross",
            37: "backcountry", 38: "resort", 39: "rc_drone", 40: "wingsuit",
            41: "whitewater", 42: "skate_skiing", 43: "yoga", 44: "pilates",
            45: "indoor_running", 46: "gravel_cycling", 47: "e_bike_mountain",
            48: "commuting", 49: "mixed_surface", 50: "navigate",
            51: "track_me", 52: "map", 53: "single_gas_diving",
            54: "multi_gas_diving", 55: "gauge_diving", 56: "apnea_diving",
            57: "apnea_hunting", 58: "virtual_activity", 59: "obstacle",
            62: "breathing", 63: "ccr_diving", 65: "sail_race",
            66: "expedition", 67: "ultra", 68: "indoor_climbing",
            69: "bouldering", 70: "hiit", 71: "indoor_grinding",
            72: "hunting_with_dogs", 73: "amrap", 74: "emom", 75: "tabata",
            77: "esport", 78: "triathlon", 79: "duathlon", 80: "brick",
            81: "swim_run", 82: "adventure_race", 83: "trucker_workout",
            84: "pickleball", 85: "padel", 86: "indoor_wheelchair_walk",
            87: "indoor_wheelchair_run", 88: "indoor_hand_cycling",
            90: "field", 91: "ice", 92: "ultimate", 93: "platform",
            94: "squash", 95: "badminton", 96: "racquetball",
            97: "table_tennis", 98: "overland", 99: "trolling_motor",
            110: "fly_canopy", 111: "fly_paraglide", 112: "fly_paramotor",
            113: "fly_pressurized", 114: "fly_navigate", 115: "fly_timer",
            116: "fly_altimeter", 117: "fly_wx", 118: "fly_vfr",
            119: "fly_ifr", 121: "dynamic_apnea", 123: "enduro",
            124: "rucking", 125: "rally", 126: "pool_triathlon",
            127: "e_bike_enduro", 254: "all",
        ],
        "intensity": [
            0: "active", 1: "rest", 2: "warmup", 3: "cooldown",
            4: "recovery", 5: "interval", 6: "other",
        ],
        "lap_trigger": [
            0: "manual", 1: "time", 2: "distance", 3: "position_start",
            4: "position_lap", 5: "position_waypoint", 6: "position_marked",
            7: "session_end", 8: "fitness_equipment",
        ],
        "session_trigger": [
            0: "activity_end", 1: "manual", 2: "auto_multi_sport",
            3: "fitness_equipment",
        ],
        "activity": [0: "manual", 1: "auto_multi_sport"],
        "activity_type": [
            0: "generic", 1: "running", 2: "cycling", 3: "transition",
            4: "fitness_equipment", 5: "swimming", 6: "walking",
            8: "sedentary", 13: "wheelchair_pushing", 254: "all",
        ],
        "battery_status": [
            1: "new", 2: "good", 3: "ok", 4: "low", 5: "critical",
            6: "charging", 7: "unknown",
        ],
        "body_location": [
            0: "left_leg", 1: "left_calf", 2: "left_shin",
            3: "left_hamstring", 4: "left_quad", 5: "left_glute",
            6: "right_leg", 7: "right_calf", 8: "right_shin",
            9: "right_hamstring", 10: "right_quad", 11: "right_glute",
            12: "torso_back", 13: "left_lower_back", 14: "left_upper_back",
            15: "right_lower_back", 16: "right_upper_back", 17: "torso_front",
            18: "left_abdomen", 19: "left_chest", 20: "right_abdomen",
            21: "right_chest", 22: "left_arm", 23: "left_shoulder",
            24: "left_bicep", 25: "left_tricep", 26: "left_brachioradialis",
            27: "left_forearm_extensors", 28: "right_arm",
            29: "right_shoulder", 30: "right_bicep", 31: "right_tricep",
            32: "right_brachioradialis", 33: "right_forearm_extensors",
            34: "neck", 35: "throat", 36: "waist_mid_back", 37: "waist_front",
            38: "waist_left", 39: "waist_right",
        ],
        "display_measure": [0: "metric", 1: "statute", 2: "nautical"],
        "swim_stroke": [
            0: "freestyle", 1: "backstroke", 2: "breaststroke",
            3: "butterfly", 4: "drill", 5: "mixed", 6: "im",
            7: "im_by_round", 8: "rimo",
        ],
        "source_type": [
            0: "ant", 1: "antplus", 2: "bluetooth",
            3: "bluetooth_low_energy", 4: "wifi", 5: "local",
        ],
        "ant_network": [0: "public", 1: "antplus", 2: "antfs", 3: "private"],
        "file": [
            1: "device", 2: "settings", 3: "sport", 4: "activity",
            5: "workout", 6: "course", 7: "schedules", 9: "weight",
            10: "totals", 11: "goals", 14: "blood_pressure",
            15: "monitoring_a", 20: "activity_summary", 28: "monitoring_daily",
            32: "monitoring_b", 34: "segment", 35: "segment_list",
            40: "exd_configuration", 247: "mfg_range_min", 254: "mfg_range_max",
        ],
        "gender": [0: "female", 1: "male"],
        "stroke_type": [
            0: "no_event", 1: "other", 2: "serve", 3: "forehand",
            4: "backhand", 5: "smash",
        ],
        "radar_threat_level_type": [
            0: "threat_unknown", 1: "threat_none", 2: "threat_approaching",
            3: "threat_approaching_fast",
        ],
        "manufacturer": [
            1: "garmin", 2: "garmin_fr405_antfs", 3: "zephyr", 4: "dayton",
            5: "idt", 6: "srm", 7: "quarq", 8: "ibike", 9: "saris",
            10: "spark_hk", 11: "tanita", 12: "echowell", 13: "dynastream_oem",
            14: "nautilus", 15: "dynastream", 16: "timex", 17: "metrigear",
            18: "xelic", 19: "beurer", 20: "cardiosport", 21: "a_and_d",
            22: "hmm", 23: "suunto", 24: "thita_elektronik", 25: "gpulse",
            26: "clean_mobile", 27: "pedal_brain", 28: "peaksware",
            29: "saxonar", 30: "lemond_fitness", 31: "dexcom",
            32: "wahoo_fitness", 33: "octane_fitness", 34: "archinoetics",
            35: "the_hurt_box", 36: "citizen_systems", 37: "magellan",
            38: "osynce", 39: "holux", 40: "concept2", 41: "shimano",
            42: "one_giant_leap", 43: "ace_sensor", 44: "brim_brothers",
            45: "xplova", 46: "perception_digital", 47: "bf1systems",
            48: "pioneer", 49: "spantec", 50: "metalogics", 51: "4iiiis",
            52: "seiko_epson", 53: "seiko_epson_oem", 54: "ifor_powell",
            55: "maxwell_guider", 56: "star_trac", 57: "breakaway",
            58: "alatech_technology_ltd", 59: "mio_technology_europe",
            60: "rotor", 61: "geonaute", 62: "id_bike", 63: "specialized",
            64: "wtek", 65: "physical_enterprises", 66: "north_pole_engineering",
            67: "bkool", 68: "cateye", 69: "stages_cycling", 70: "sigmasport",
            71: "tomtom", 72: "peripedal", 73: "wattbike", 76: "moxy",
            77: "ciclosport", 78: "powerbahn", 79: "acorn_projects_aps",
            80: "lifebeam", 81: "bontrager", 82: "wellgo", 83: "scosche",
            84: "magura", 85: "woodway", 86: "elite", 87: "nielsen_kellerman",
            88: "dk_city", 89: "tacx", 90: "direction_technology",
            91: "magtonic", 92: "1partcarbon", 93: "inside_ride_technologies",
            94: "sound_of_motion", 95: "stryd", 96: "icg", 97: "MiPulse",
            98: "bsx_athletics", 99: "look", 100: "campagnolo_srl",
            101: "body_bike_smart", 102: "praxisworks", 103: "limits_technology",
            104: "topaction_technology", 105: "cosinuss", 106: "fitcare",
            107: "magene", 108: "giant_manufacturing_co", 109: "tigrasport",
            110: "salutron", 111: "technogym", 112: "bryton_sensors",
            113: "latitude_limited", 114: "soaring_technology", 115: "igpsport",
            116: "thinkrider", 117: "gopher_sport", 118: "waterrower",
            119: "orangetheory", 120: "inpeak", 121: "kinetic",
            122: "johnson_health_tech", 123: "polar_electro", 124: "seesense",
            125: "nci_technology", 126: "iqsquare", 127: "leomo",
            128: "ifit_com", 129: "coros_byte", 130: "versa_design",
            131: "chileaf", 132: "cycplus", 133: "gravaa_byte", 134: "sigeyi",
            135: "coospo", 136: "geoid", 137: "bosch", 138: "kyto",
            139: "kinetic_sports", 140: "decathlon_byte", 141: "tq_systems",
            142: "tag_heuer", 143: "keiser_fitness", 144: "zwift_byte",
            145: "porsche_ep", 146: "blackbird", 147: "meilan_byte",
            148: "ezon", 149: "laisi", 150: "myzone", 151: "abawo",
            152: "bafang", 153: "luhong_technology", 255: "development",
            257: "healthandlife", 258: "lezyne", 259: "scribe_labs",
            260: "zwift", 261: "watteam", 262: "recon", 263: "favero_electronics",
            264: "dynovelo", 265: "strava", 266: "precor", 267: "bryton",
            268: "sram", 269: "navman", 270: "cobi", 271: "spivi",
            272: "mio_magellan", 273: "evesports", 274: "sensitivus_gauge",
            275: "podoon", 276: "life_time_fitness", 277: "falco_e_motors",
            278: "minoura", 279: "cycliq", 280: "luxottica", 281: "trainer_road",
            282: "the_sufferfest", 283: "fullspeedahead", 284: "virtualtraining",
            285: "feedbacksports", 286: "omata", 287: "vdo", 288: "magneticdays",
            289: "hammerhead", 290: "kinetic_by_kurt", 291: "shapelog",
            292: "dabuziduo", 293: "jetblack", 294: "coros", 295: "virtugo",
            296: "velosense", 297: "cycligentinc", 298: "trailforks",
            299: "mahle_ebikemotion", 300: "nurvv", 301: "microprogram",
            302: "zone5cloud", 303: "greenteg", 304: "yamaha_motors",
            305: "whoop", 306: "gravaa", 307: "onelap", 308: "monark_exercise",
            309: "form", 310: "decathlon", 311: "syncros", 312: "heatup",
            313: "cannondale", 314: "true_fitness", 315: "RGT_cycling",
            316: "vasa", 317: "race_republic", 318: "fazua", 319: "oreka_training",
            320: "lsec", 321: "lululemon_studio", 322: "shanyue",
            323: "spinning_mda", 324: "hilldating", 325: "aero_sensor",
            326: "nike", 327: "magicshine", 328: "ictrainer",
            329: "absolute_cycling", 330: "eo_swimbetter", 331: "mywhoosh",
            332: "ravemen", 333: "tektro_racing_products",
            334: "darad_innovation_corporation", 335: "cycloptim", 337: "runna",
            339: "zepp", 340: "peloton", 341: "carv", 342: "tissot",
            345: "real_velo", 346: "wetech", 347: "jespr", 348: "huawei",
            349: "gotoes", 350: "cadence_app", 351: "una_watch",
            5759: "actigraphcorp",
        ],
    ]

    /// Maps field names that differ from their enum type name to the type name.
    private static let fieldAliases: [String: String] = [
        "trigger": "session_trigger",
        "pool_length_unit": "display_measure",
        "sensor_position": "body_location",
        "radar_threat_level_max": "radar_threat_level_type",
        "type": "file",
    ]
}
