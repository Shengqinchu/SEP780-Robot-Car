#ifndef TEST_SERVO_H
#define TEST_SERVO_H
#include "Arduino.h"
class Servo {
 public:
  void write(int angle) { fake::angle = angle; }
  void attach(int pin) { fake::servo_pin = pin; }
};
#endif
