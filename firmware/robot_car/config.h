#ifndef SEP780_CONFIG_H
#define SEP780_CONFIG_H

#include <stdint.h>

namespace robot {
struct Config {
  uint8_t cruise_pwm = 90;
  uint8_t turn_reduction_pwm = 50;
  uint8_t max_pwm = 150;
  int8_t left_trim_pwm = 0;
  int8_t right_trim_pwm = 0;
  uint16_t obstacle_stop_mm = 200;
  uint16_t obstacle_resume_mm = 300;
  uint16_t clear_hold_ms = 600;
  uint16_t range_max_age_ms = 250;
  uint16_t input_max_age_ms = 100;
  uint16_t line_lost_ms = 400;
  uint16_t manual_lease_ms = 350;
  uint16_t serial_lease_ms = 1200;
  uint16_t battery_min_mv = 6600;
  uint16_t battery_max_mv = 9000;

  bool valid() const {
    return cruise_pwm > 0 && cruise_pwm <= max_pwm && max_pwm <= 180 &&
      turn_reduction_pwm <= cruise_pwm && left_trim_pwm >= -40 && left_trim_pwm <= 40 &&
      right_trim_pwm >= -40 && right_trim_pwm <= 40 && obstacle_stop_mm >= 100 &&
      obstacle_resume_mm > obstacle_stop_mm && obstacle_resume_mm <= 2000 &&
      clear_hold_ms >= 300 && clear_hold_ms <= 5000 && range_max_age_ms >= 80 &&
      range_max_age_ms <= 500 && input_max_age_ms >= 30 && input_max_age_ms <= 200 &&
      line_lost_ms >= 100 && line_lost_ms <= 1000 && manual_lease_ms >= 150 &&
      manual_lease_ms <= 500 && serial_lease_ms >= manual_lease_ms && serial_lease_ms <= 2000 &&
      battery_min_mv >= 6400 && battery_max_mv > battery_min_mv && battery_max_mv <= 9500;
  }
};

namespace hardware {
static const uint8_t servo_center_degrees = 90;
static const uint16_t servo_settle_ms = 400;
static const uint16_t sonar_period_ms = 60;
static const uint32_t sonar_timeout_us = 25000;
static const bool invert_left_motor = false;
static const bool invert_right_motor = false;
static const bool black_reads_high = true;
static const uint32_t adc_full_scale_mv = 20000;
}
}
#endif
