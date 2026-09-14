#include "Arduino.h"
#include <string.h>
namespace fake {
uint32_t now, pulse, timeout;
int pwm[20], digital[20], modes[20], adc, angle, servo_pin;
void reset() {
  now = pulse = timeout = 0;
  memset(pwm, 0, sizeof(pwm)); memset(digital, 0, sizeof(digital)); memset(modes, 0, sizeof(modes));
  adc = 380; angle = servo_pin = -1;
}
}
uint32_t millis() { return fake::now; }
void pinMode(uint8_t pin, uint8_t mode) { fake::modes[pin] = mode; }
void digitalWrite(uint8_t pin, uint8_t value) { fake::digital[pin] = value; }
int digitalRead(uint8_t pin) { return fake::digital[pin]; }
void analogWrite(uint8_t pin, int value) { fake::pwm[pin] = value; }
int analogRead(uint8_t) { return fake::adc; }
void delayMicroseconds(unsigned int) {}
uint32_t pulseIn(uint8_t, uint8_t, uint32_t timeout) {
  fake::timeout = timeout;
  fake::now += (fake::pulse ? fake::pulse : timeout) / 1000;
  return fake::pulse;
}
