// FNK0041 pin mapping: Freenove 00.0_Servo_90 and 01.1.3_Car_Move_and_Turn.
// Upstream a035ca380a9218d0a88aab635a58b9a3c738940f, CC BY-NC-SA 3.0.
// One bounded diagnostic pass per reset; serial messages report commands only.
#include <Arduino.h>
#include <Servo.h>

const uint8_t kServoPin = 2;
const uint8_t kMotorPwmRight = 5;
const uint8_t kMotorPwmLeft = 6;
// This car's first +8-degree trial increased the observed mounting error.
// Reverse the trial trim while keeping it inside Freenove's +/-10-degree range.
// The accepted physical center is mirrored in robot_car/config.h.
const int8_t kServoTrimDegrees = -8;
const uint8_t kServoCenterDegrees = 90 + kServoTrimDegrees;
const uint8_t kSweepDegrees = 5;
const uint8_t kAngles[] = {
  kServoCenterDegrees,
  kServoCenterDegrees - kSweepDegrees,
  kServoCenterDegrees,
  kServoCenterDegrees + kSweepDegrees,
  kServoCenterDegrees
};
Servo head;

void setup() {
  // Disable both motor channels before attaching the servo.
  digitalWrite(kMotorPwmRight, LOW);
  digitalWrite(kMotorPwmLeft, LOW);
  pinMode(kMotorPwmRight, OUTPUT);
  pinMode(kMotorPwmLeft, OUTPUT);
  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
  Serial.begin(115200);
  Serial.println(F("SERVO_CHECK: one pass per reset; motor PWM disabled"));

  head.attach(kServoPin);
  for (uint8_t step = 0; step < sizeof(kAngles) / sizeof(kAngles[0]); ++step) {
    head.write(kAngles[step]);
    digitalWrite(LED_BUILTIN, step % 2 == 0 ? HIGH : LOW);
    Serial.print(F("COMMAND_DEGREES="));
    Serial.println(kAngles[step]);
    delay(1500);
  }
  digitalWrite(LED_BUILTIN, HIGH);
  Serial.print(F("DONE: holding calibrated center at "));
  Serial.print(kServoCenterDegrees);
  Serial.println(F(" degrees; verify actual direction visually"));
}

void loop() {
  // Hold the center command without repeating the diagnostic sweep.
}
