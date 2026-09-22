#ifndef SEP780_PROTOCOL_H
#define SEP780_PROTOCOL_H

#include "controller.h"

namespace robot {
enum class CommandType : uint8_t {
  Stop, ArmLine, ArmManual, LinePulse, LineContinuous, LineHybrid, Speed,
  Drive, RemoteDrive, HornOn, HornOff, Ping, Status
};
struct Command {
  uint16_t sequence = 0;
  CommandType type = CommandType::Stop;
  int16_t left = 0;
  int16_t right = 0;
  uint8_t speed = 0;
};
enum class ParseResult : uint8_t { None, Ready, Invalid };

class CommandParser {
 public:
  ParseResult feed(char value, uint32_t now, Command& result);
  bool expire(uint32_t now);
 private:
  char buffer_[64] = {};
  uint8_t used_ = 0;
  uint32_t started_ms_ = 0;
  bool discarding_ = false;
};
bool execute(Controller& controller, const Command& command, Source source, const Inputs& inputs, uint32_t now);
}
#endif
