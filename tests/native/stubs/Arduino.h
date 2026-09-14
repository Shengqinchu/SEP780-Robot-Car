#ifndef TEST_ARDUINO_H
#define TEST_ARDUINO_H
#include <stdint.h>
#define HIGH 1
#define LOW 0
#define INPUT 0
#define OUTPUT 1
#define A0 14
#define A1 15
#define A2 16
#define A3 17
#define constrain(value, lower, upper) ((value) < (lower) ? (lower) : (value) > (upper) ? (upper) : (value))
uint32_t millis();
void pinMode(uint8_t pin, uint8_t mode);
void digitalWrite(uint8_t pin, uint8_t value);
int digitalRead(uint8_t pin);
void analogWrite(uint8_t pin, int value);
int analogRead(uint8_t pin);
void delayMicroseconds(unsigned int duration);
uint32_t pulseIn(uint8_t pin, uint8_t state, uint32_t timeout);
namespace fake {
extern uint32_t now, pulse, timeout;
extern int pwm[20], digital[20], modes[20], adc, angle, servo_pin;
void reset();
}
#endif
