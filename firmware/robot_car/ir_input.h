#ifndef SEP780_IR_INPUT_H
#define SEP780_IR_INPUT_H
#include "protocol.h"
namespace robot {
class IrInput {
 public:
  bool decode(uint32_t code, uint32_t now, uint8_t speed, Command& command);
 private:
  uint32_t last_code_ = 0;
  uint32_t last_ms_ = 0;
};
}
#endif
