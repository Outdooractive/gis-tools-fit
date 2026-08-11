#!/usr/bin/env python3
"""Generate a sample FIT activity file using the Garmin FIT Python SDK.

This writes an activity file and populates every common field of the main
message types (file_id, activity, session, lap, record, event, device_info).
It is a convenient sample to exercise FIT parsers/encoders.

Usage:
    python3 generate_sample_fit.py [output.fit]
"""

import sys
from datetime import datetime, timedelta

from garmin_fit_sdk import Encoder

# Garmin FIT epoch = 1989-12-31 00:00:00 UTC
FIT_EPOCH = datetime(1989, 12, 31)
START = datetime(2024, 6, 1, 7, 30, 0)


def dt(value):
    """Convert a datetime to a FIT timestamp (seconds since FIT epoch)."""
    return int((value - FIT_EPOCH).total_seconds())


def main(output_path="sample.fit"):
    encoder = Encoder()

    # ---- File ID (must be the first message) --------------------------------
    encoder.write_mesg({
        "mesg_num": 0,
        "type": "activity",
        "manufacturer": "garmin",
        "garmin_product": "fr255",
        "serial_number": 0x0123456789ABCDEF,
        "time_created": dt(START),
        "number": 1,
        "product_name": "Garmin Forerunner 255",
    })

    # ---- Activity -----------------------------------------------------------
    encoder.write_mesg({
        "mesg_num": 34,
        "timestamp": dt(START),
        "total_timer_time": 3600.0,
        "num_sessions": 1,
        "type": "manual",
        "event": "activity",
        "event_type": "stop",
        "local_timestamp": dt(START),
        "event_group": 1,
    })

    # ---- Session ------------------------------------------------------------
    encoder.write_mesg({
        "mesg_num": 18,
        "message_index": 0,
        "timestamp": dt(START + timedelta(seconds=3600)),
        "event": "session",
        "event_type": "stop",
        "start_time": dt(START),
        "start_position_lat": 510000000,
        "start_position_long": 90000000,
        "sport": "running",
        "sub_sport": "generic",
        "total_elapsed_time": 3660.0,
        "total_timer_time": 3600.0,
        "total_distance": 12000.0,
        "total_cycles": 3600,
        "total_calories": 800,
        "total_fat_calories": 120,
        "avg_speed": 3.333,
        "max_speed": 5.0,
        "avg_heart_rate": 145,
        "max_heart_rate": 175,
        "avg_cadence": 170,
        "avg_running_cadence": 85,
        "max_cadence": 92,
        "max_running_cadence": 92,
        "avg_power": 250,
        "max_power": 320,
        "total_ascent": 150,
        "total_descent": 120,
        "total_training_effect": 3.5,
        "first_lap_index": 0,
        "num_laps": 3,
        "event_group": 1,
        "trigger": "activity_end",
        "nec_lat": 510500000,
        "nec_long": 90050000,
        "swc_lat": 509500000,
        "swc_long": 89950000,
        "num_lengths": 0,
        "normalized_power": 240,
        "training_stress_score": 45.0,
        "intensity_factor": 0.8,
        "left_right_balance": 5000,
        "end_position_lat": 510200000,
        "end_position_long": 90010000,
        "avg_stroke_count": 0,
        "avg_stroke_distance": 0,
        "pool_length": 0,
        "threshold_power": 280,
        "pool_length_unit": "metric",
        "total_work": 900000,
        "avg_altitude": 100.0,
        "max_altitude": 140.0,
        "gps_accuracy": 3,
        "avg_grade": 0.5,
        "avg_pos_grade": 2.0,
        "avg_neg_grade": 1.5,
        "max_pos_grade": 5.0,
        "max_neg_grade": 4.0,
        "avg_temperature": 20,
        "max_temperature": 23,
        "total_moving_time": 3500.0,
        "avg_pos_vertical_speed": 0.5,
        "avg_neg_vertical_speed": 0.4,
        "max_pos_vertical_speed": 2.0,
        "max_neg_vertical_speed": 1.8,
        "min_heart_rate": 90,
        "time_in_hr_zone": [600.0, 900.0, 1200.0, 600.0, 300.0],
        "time_in_speed_zone": [1800.0, 1800.0],
        "time_in_cadence_zone": [900.0, 2700.0],
        "time_in_power_zone": [600.0, 1200.0, 1200.0, 600.0],
        "avg_lap_time": 1200.0,
        "best_lap_index": 1,
        "min_altitude": 60.0,
        "active_time": 3600.0,
        "enhanced_avg_speed": 3.333,
        "enhanced_max_speed": 5.0,
        "enhanced_avg_altitude": 100.0,
        "enhanced_min_altitude": 60.0,
        "enhanced_max_altitude": 140.0,
        "avg_vertical_ratio": 6.0,
        "avg_stance_time_balance": 49.0,
        "avg_step_length": 95.0,
        "total_anaerobic_training_effect": 2.0,
        "avg_vam": 12.0,
        "training_load_peak": 120.0,
        "total_grit": 20.0,
        "total_flow": 30.0,
        "jump_count": 0,
        "avg_grit": 5.0,
        "avg_flow": 7.5,
        "workout_feel": 7,
        "workout_rpe": 14,
        "avg_spo2": 97,
        "avg_stress": 45,
        "metabolic_calories": 700,
        "sdrr_hrv": 40,
        "rmssd_hrv": 55,
        "total_fractional_ascent": 0.5,
        "total_fractional_descent": 0.25,
        "avg_core_temperature": 37.5,
        "min_core_temperature": 37.0,
        "max_core_temperature": 38.0,
    })

    # ---- Lap (x3) -----------------------------------------------------------
    for lap_index in range(3):
        encoder.write_mesg({
            "mesg_num": 19,
            "message_index": lap_index,
            "timestamp": dt(START + timedelta(seconds=1200 * (lap_index + 1))),
            "event": "lap",
            "event_type": "stop",
            "start_time": dt(START + timedelta(seconds=1200 * lap_index)),
            "start_position_lat": 510000000,
            "start_position_long": 90000000,
            "end_position_lat": 510100000,
            "end_position_long": 90005000,
            "total_elapsed_time": 1220.0,
            "total_timer_time": 1200.0,
            "total_distance": 4000.0,
            "total_cycles": 1200,
            "total_strides": 1200,
            "total_calories": 260,
            "total_fat_calories": 40,
            "avg_speed": 3.333,
            "max_speed": 5.0,
            "avg_heart_rate": 144,
            "max_heart_rate": 175,
            "avg_cadence": 170,
            "avg_running_cadence": 85,
            "max_cadence": 92,
            "max_running_cadence": 92,
            "avg_power": 248,
            "max_power": 320,
            "total_ascent": 50,
            "total_descent": 40,
            "intensity": "active",
            "lap_trigger": "distance",
            "sport": "running",
            "event_group": 1,
            "normalized_power": 240,
            "left_right_balance": 5000,
            "avg_stroke_distance": 0,
            "sub_sport": "generic",
            "total_work": 300000,
            "avg_altitude": 100.0,
            "max_altitude": 120.0,
            "gps_accuracy": 3,
            "avg_grade": 0.5,
            "avg_pos_grade": 2.0,
            "avg_neg_grade": 1.5,
            "max_pos_grade": 4.0,
            "max_neg_grade": 3.0,
            "avg_temperature": 20,
            "max_temperature": 22,
            "total_moving_time": 1180.0,
            "avg_pos_vertical_speed": 0.5,
            "avg_neg_vertical_speed": 0.4,
            "max_pos_vertical_speed": 1.8,
            "max_neg_vertical_speed": 1.6,
            "time_in_hr_zone": [200.0, 300.0, 400.0, 200.0, 100.0],
            "time_in_speed_zone": [600.0, 600.0],
            "time_in_cadence_zone": [300.0, 900.0],
            "time_in_power_zone": [200.0, 400.0, 400.0, 200.0],
            "min_altitude": 80.0,
            "min_heart_rate": 95,
            "active_time": 1200.0,
            "avg_vertical_ratio": 6.0,
            "avg_stance_time_percent": 25.0,
            "avg_stance_time": 220.0,
            "avg_fractional_cadence": 0.5,
            "max_fractional_cadence": 0.5,
            "total_fractional_cycles": 0.5,
            "avg_left_torque_effectiveness": 50.0,
            "avg_right_torque_effectiveness": 52.0,
            "avg_left_pedal_smoothness": 40.0,
            "avg_right_pedal_smoothness": 42.0,
            "avg_combined_pedal_smoothness": 41.0,
            "enhanced_avg_speed": 3.333,
            "enhanced_max_speed": 5.0,
            "enhanced_avg_altitude": 100.0,
            "enhanced_min_altitude": 80.0,
            "enhanced_max_altitude": 120.0,
            "avg_vertical_ratio": 6.0,
            "avg_stance_time_balance": 49.0,
            "avg_step_length": 95.0,
            "avg_vam": 12.0,
            "total_grit": 6.0,
            "total_flow": 10.0,
            "jump_count": 0,
            "avg_grit": 5.0,
            "avg_flow": 8.0,
            "total_fractional_ascent": 0.2,
            "total_fractional_descent": 0.1,
        })

    # ---- Record samples -----------------------------------------------------
    for i in range(30):
        seconds = i * 120
        timestamp = START + timedelta(seconds=seconds)
        distance = i * 400.0
        encoder.write_mesg({
            "mesg_num": 20,
            "timestamp": dt(timestamp),
            "position_lat": 510000000 + i * 1000,
            "position_long": 90000000 + i * 500,
            "altitude": 100.0 + i * 0.5,
            "heart_rate": 140 + (i % 30),
            "cadence": 170 + (i % 10),
            "distance": distance,
            "speed": 3.333,
            "power": 250 + (i % 50),
            "grade": 0.5,
            "temperature": 20,
            "cycles": 1000,
            "total_cycles": i * 4000,
            "accumulated_power": i * 12000,
            "left_right_balance": 5000,
            "gps_accuracy": 3,
            "vertical_speed": 0.5,
            "calories": 25 + i,
            "vertical_oscillation": 6.0,
            "stance_time_percent": 25.0,
            "stance_time": 220.0,
            "activity_type": "running",
            "cadence256": 43690,
            "fractional_cadence": 0.5,
            "device_index": 0,
            "enhanced_speed": 3.333,
            "enhanced_altitude": 100.0 + i * 0.5,
            "vertical_ratio": 6.0,
            "stance_time_balance": 49.0,
            "step_length": 95.0,
            "cycle_length16": 250.0,
            "respiration_rate": 20,
            "enhanced_respiration_rate": 20.0,
            "grit": 5.0,
            "flow": 8.0,
            "current_stress": 40.0,
            "core_temperature": 37.5,
        })

    # ---- Events -------------------------------------------------------------
    encoder.write_mesg({
        "mesg_num": 21,
        "timestamp": dt(START),
        "event": "timer",
        "event_type": "start",
        "timer_trigger": "manual",
        "event_group": 1,
    })
    encoder.write_mesg({
        "mesg_num": 21,
        "timestamp": dt(START + timedelta(seconds=3600)),
        "event": "timer",
        "event_type": "stop_all",
        "timer_trigger": "auto",
        "event_group": 1,
    })

    # ---- Device Info --------------------------------------------------------
    encoder.write_mesg({
        "mesg_num": 23,
        "timestamp": dt(START),
        "device_index": 0,
        "device_type": 1,
        "manufacturer": "garmin",
        "serial_number": 0x0123456789ABCDEF,
        "garmin_product": "fr255",
        "software_version": 12.34,
        "hardware_version": 1,
        "cum_operating_time": 100000,
        "battery_voltage": 4.1,
        "battery_status": "good",
        "sensor_position": "left_leg",
        "descriptor": "Forerunner 255",
        "product_name": "Garmin Forerunner 255",
    })

    # ---- Close and write file ----------------------------------------------
    data = encoder.close()
    with open(output_path, "wb") as f:
        f.write(data)

    print(f"Wrote {len(data)} bytes to {output_path}")


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "sample.fit"
    main(path)
