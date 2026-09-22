#ifndef SEP780_IO_H
#define SEP780_IO_H
#include "controller.h"
#include <Servo.h>
namespace robot {
class Fnk0041Io {
 public:
  void begin();
  Inputs read();
  void write(Drive drive);
  void setBuzzer(bool obstacle_alert, bool manual_horn);
 private:
  Servo head_;
  Inputs inputs_;
  uint32_t boot_ms_ = 0;
  uint32_t sonar_ms_ = 0;
  uint32_t alert_ms_ = 0;
  int8_t left_sign_ = 0;
  int8_t right_sign_ = 0;
  bool alert_active_ = false;
  bool horn_active_ = false;
  bool buzzer_on_ = false;
};
}
#endif
