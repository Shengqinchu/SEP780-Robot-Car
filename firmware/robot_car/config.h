#ifndef SEP780_CONFIG_H
#define SEP780_CONFIG_H

#include <stdint.h>

namespace robot {
struct Config {
  uint8_t cruise_pwm = 100;
  uint8_t min_runtime_pwm = 50;
  uint8_t line_pulse_pwm = 120;
  uint8_t line_turn_pwm = 150;
  uint8_t turn_reduction_pwm = 120;
  uint8_t max_pwm = 200;
  int8_t left_trim_pwm = 0;
  int8_t right_trim_pwm = 0;
  uint16_t obstacle_stop_mm = 200;
  uint16_t obstacle_resume_mm = 300;
  uint16_t clear_hold_ms = 600;
  uint16_t range_max_age_ms = 250;
  uint16_t input_max_age_ms = 100;
  uint16_t manual_lease_ms = 350;
  uint16_t serial_lease_ms = 1200;
  uint16_t battery_min_mv = 6600;
  uint16_t battery_max_mv = 9000;
  uint16_t battery_low_hold_ms = 300;
  uint16_t line_pulse_on_ms = 80;
  uint16_t line_pulse_off_ms = 80;
  uint16_t horn_lease_ms = 1500;

  bool valid() const {
    return min_runtime_pwm > 0 && min_runtime_pwm <= cruise_pwm &&
      cruise_pwm <= max_pwm && max_pwm <= 200 &&
      line_pulse_pwm >= min_runtime_pwm && line_pulse_pwm <= max_pwm &&
      line_turn_pwm >= line_pulse_pwm && line_turn_pwm <= max_pwm &&
      turn_reduction_pwm <= line_pulse_pwm && left_trim_pwm >= -40 && left_trim_pwm <= 40 &&
      right_trim_pwm >= -40 && right_trim_pwm <= 40 && obstacle_stop_mm >= 100 &&
      obstacle_resume_mm > obstacle_stop_mm && obstacle_resume_mm <= 2000 &&
      clear_hold_ms >= 300 && clear_hold_ms <= 5000 && range_max_age_ms >= 80 &&
      range_max_age_ms <= 500 && input_max_age_ms >= 30 && input_max_age_ms <= 200 &&
      manual_lease_ms >= 150 && manual_lease_ms <= 500 &&
      serial_lease_ms >= manual_lease_ms && serial_lease_ms <= 2000 &&
      battery_min_mv >= 6400 && battery_max_mv > battery_min_mv && battery_max_mv <= 9500 &&
      battery_low_hold_ms >= 100 && battery_low_hold_ms <= 2000 &&
      line_pulse_on_ms >= 20 && line_pulse_on_ms <= 500 &&
      line_pulse_off_ms >= 20 && line_pulse_off_ms <= 500 &&
      horn_lease_ms >= 500 && horn_lease_ms <= 3000;
  }
};

namespace hardware {
// Physical calibration: nearest horn spline plus an -8-degree software trim.
static const uint8_t servo_center_degrees = 82;
static const uint16_t servo_settle_ms = 400;
static const uint16_t sonar_period_ms = 60;
static const uint32_t sonar_timeout_us = 25000;
static const uint16_t buzzer_on_ms = 100;
static const uint16_t buzzer_period_ms = 700;
static const uint16_t horn_on_ms = 120;
static const uint16_t horn_period_ms = 150;
static_assert(buzzer_on_ms > 0 && buzzer_on_ms < buzzer_period_ms,
  "Buzzer pulse must be shorter than its period");
static_assert(horn_on_ms > 0 && horn_on_ms < horn_period_ms,
  "Horn pulse must leave time for battery sampling");
// Physical lifted-wheel calibration: vendor-positive polarity drove this chassis backward.
static const bool invert_left_motor = true;
static const bool invert_right_motor = true;
// Freenove defines black or no reflection as HIGH and white as LOW.
static const bool black_reads_high = true;
static const uint32_t adc_full_scale_mv = 20000;
}
}
#endif
