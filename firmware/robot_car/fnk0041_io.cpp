// FNK0041 pin map and motor polarity follow Freenove's fixed reference snapshot.
// See THIRD_PARTY.md for source and attribution. Control policy is in controller.cpp.
#include "fnk0041_io.h"
#include <Arduino.h>

namespace robot {
namespace {
const uint8_t left_dir = 4, right_dir = 3, left_pwm = 6, right_pwm = 5;
const uint8_t trigger_pin = 7, echo_pin = 8, servo_pin = 2;

void wheel(int16_t pwm, uint8_t direction_pin, uint8_t pwm_pin, bool positive_high, int8_t& previous_sign) {
  pwm = constrain(pwm, -180, 180);
  const int8_t sign = pwm > 0 ? 1 : pwm < 0 ? -1 : 0;
  if (sign != previous_sign) analogWrite(pwm_pin, 0);
  // Drop PWM before reversing; a subsequent write applies the new sign.
  if (sign && previous_sign && sign != previous_sign) { previous_sign = 0; return; }
  digitalWrite(direction_pin, (pwm > 0) == positive_high ? HIGH : LOW);
  analogWrite(pwm_pin, pwm < 0 ? -pwm : pwm);
  previous_sign = sign;
}
}

void Fnk0041Io::begin() {
  pinMode(left_pwm, OUTPUT); pinMode(right_pwm, OUTPUT);
  analogWrite(left_pwm, 0); analogWrite(right_pwm, 0);
  pinMode(left_dir, OUTPUT); pinMode(right_dir, OUTPUT);
  pinMode(trigger_pin, OUTPUT); digitalWrite(trigger_pin, LOW);
  pinMode(echo_pin, INPUT);
  pinMode(A0, INPUT); digitalWrite(A0, LOW); // A0 is shared with the buzzer; keep it an input.
  pinMode(A1, INPUT); pinMode(A2, INPUT); pinMode(A3, INPUT);
  head_.write(hardware::servo_center_degrees);
  head_.attach(servo_pin);
  boot_ms_ = millis();
  sonar_ms_ = boot_ms_;
}

Inputs Fnk0041Io::read() {
  uint32_t now = millis();
  inputs_.head_ready = now - boot_ms_ >= hardware::servo_settle_ms;
  if (inputs_.head_ready && now - sonar_ms_ >= hardware::sonar_period_ms) {
    digitalWrite(trigger_pin, LOW); delayMicroseconds(2);
    digitalWrite(trigger_pin, HIGH); delayMicroseconds(10);
    digitalWrite(trigger_pin, LOW);
    const uint32_t pulse = pulseIn(echo_pin, HIGH, hardware::sonar_timeout_us);
    inputs_.range_ms = sonar_ms_ = millis();
    inputs_.range_valid = pulse >= 116 && pulse <= 23200;
    inputs_.range_mm = inputs_.range_valid ? static_cast<uint16_t>(pulse * 10UL / 58UL) : 0;
  }
  uint8_t line = (digitalRead(A1) << 2) | (digitalRead(A2) << 1) | digitalRead(A3);
  inputs_.line = hardware::black_reads_high ? line : (line ^ 7);
  uint32_t adc = 0;
  for (uint8_t n = 0; n < 4; ++n) adc += analogRead(A0);
  inputs_.battery_mv = static_cast<uint16_t>((adc / 4) * hardware::adc_full_scale_mv / 1023UL);
  inputs_.sampled_ms = millis();
  inputs_.sample_valid = true;
  return inputs_;
}

void Fnk0041Io::write(Drive drive) {
  wheel(hardware::invert_left_motor ? -drive.left : drive.left, left_dir, left_pwm, false, left_sign_);
  wheel(hardware::invert_right_motor ? -drive.right : drive.right, right_dir, right_pwm, true, right_sign_);
}
}
