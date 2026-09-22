// FNK0041 motor mapping: Freenove 01.1.3_Car_Move_and_Turn.
// Upstream a035ca380a9218d0a88aab635a58b9a3c738940f, CC BY-NC-SA 3.0.
// One bounded forward pulse per boot; no servo or sensor input is used.
#include <Arduino.h>

const uint8_t kDirectionLeft = 4;
const uint8_t kDirectionRight = 3;
const uint8_t kMotorPwmLeft = 6;
const uint8_t kMotorPwmRight = 5;
const uint8_t kDrivePwm = 200;
const unsigned long kWarningMs = 3000;
const unsigned long kRunMs = 1000;

void stopMotors() {
  analogWrite(kMotorPwmLeft, 0);
  analogWrite(kMotorPwmRight, 0);
}

void setup() {
  digitalWrite(kMotorPwmLeft, LOW);
  digitalWrite(kMotorPwmRight, LOW);
  pinMode(kMotorPwmLeft, OUTPUT);
  pinMode(kMotorPwmRight, OUTPUT);

  // Physical calibration found that this chassis needs both vendor polarities inverted.
  digitalWrite(kDirectionLeft, HIGH);
  digitalWrite(kDirectionRight, LOW);
  pinMode(kDirectionLeft, OUTPUT);
  pinMode(kDirectionRight, OUTPUT);

  pinMode(LED_BUILTIN, OUTPUT);
  digitalWrite(LED_BUILTIN, LOW);
  digitalWrite(A0, LOW);
  pinMode(A0, INPUT);  // A0 is shared with the buzzer; INPUT with pull-up off is silent.
  stopMotors();

  Serial.begin(115200);
  Serial.println(F("MOTOR_CHECK: stopped; forward pulse begins in 3 seconds"));
  for (uint8_t step = 0; step < 6; ++step) {
    digitalWrite(LED_BUILTIN, step % 2 == 0 ? HIGH : LOW);
    delay(kWarningMs / 6);
  }

  Serial.println(F("RUN: left=200 right=200 for 1 second"));
  digitalWrite(LED_BUILTIN, HIGH);
  analogWrite(kMotorPwmLeft, kDrivePwm);
  analogWrite(kMotorPwmRight, kDrivePwm);
  delay(kRunMs);

  stopMotors();
  digitalWrite(LED_BUILTIN, LOW);
  Serial.println(F("DONE: motors stopped permanently until reset"));
}

void loop() {
  stopMotors();
}
