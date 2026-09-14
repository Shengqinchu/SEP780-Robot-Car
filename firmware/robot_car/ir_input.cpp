#include "ir_input.h"

namespace robot {
bool IrInput::decode(uint32_t code, uint32_t now, uint8_t speed, Command& out) {
  // NEC repeat frames can renew movement only, never repeat an ARM operation.
  const bool repeated = code == 0xFFFFFFFFUL;
  if (repeated) {
    if (!last_code_ || now - last_ms_ > 180) return false;
    code = last_code_;
  } else last_code_ = code;
  last_ms_ = now;
  Command command;
  if (code == 0xFFA25DUL || code == 0xFF6897UL || code == 0xFFA857UL || code == 0xFFB04FUL) {
    command.type = CommandType::Stop;
  } else if (code == 0xFF30CFUL && !repeated) command.type = CommandType::ArmLine;
  else if (code == 0xFF18E7UL && !repeated) command.type = CommandType::ArmManual;
  else {
    command.type = CommandType::Drive;
    switch (code) {
      case 0xFF02FDUL: command.left = speed; command.right = speed; break;
      case 0xFF9867UL: command.left = -speed; command.right = -speed; break;
      case 0xFFE01FUL: command.left = -speed; command.right = speed; break;
      case 0xFF906FUL: command.left = speed; command.right = -speed; break;
      default: return false;
    }
  }
  out = command;
  return true;
}
}
