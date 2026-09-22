#include "protocol.h"
#include <string.h>

namespace robot {
namespace {
bool number(const char* text, int32_t minimum, int32_t maximum, int32_t& result) {
  bool negative = false;
  if (*text == '-') { negative = true; ++text; }
  if (!*text) return false;
  int32_t value = 0;
  while (*text) {
    if (*text < '0' || *text > '9') return false;
    value = value * 10 + (*text++ - '0');
    if (value > 65535) return false;
  }
  result = negative ? -value : value;
  return result >= minimum && result <= maximum;
}

bool parse(char* line, Command& command) {
  char* fields[6] = {};
  uint8_t count = 0;
  char* context = nullptr;
  for (char* field = strtok_r(line, " ", &context); field; field = strtok_r(nullptr, " ", &context)) {
    if (count == 6) return false;
    fields[count++] = field;
  }
  if (count < 3 || strcmp(fields[0], "S") != 0) return false;
  int32_t seq = 0;
  if (!number(fields[1], 1, 65535, seq)) return false;
  Command candidate;
  candidate.sequence = static_cast<uint16_t>(seq);
  if (count == 3 && strcmp(fields[2], "STOP") == 0) candidate.type = CommandType::Stop;
  else if (count == 3 && strcmp(fields[2], "PING") == 0) candidate.type = CommandType::Ping;
  else if (count == 3 && strcmp(fields[2], "STATUS") == 0) candidate.type = CommandType::Status;
  else if (count == 4 && strcmp(fields[2], "ARM") == 0 && strcmp(fields[3], "LINE") == 0) candidate.type = CommandType::ArmLine;
  else if (count == 4 && strcmp(fields[2], "ARM") == 0 && strcmp(fields[3], "MANUAL") == 0) candidate.type = CommandType::ArmManual;
  else if (count == 4 && strcmp(fields[2], "LINE") == 0 && strcmp(fields[3], "PULSE") == 0) candidate.type = CommandType::LinePulse;
  else if (count == 4 && strcmp(fields[2], "LINE") == 0 && strcmp(fields[3], "CONTINUOUS") == 0) candidate.type = CommandType::LineContinuous;
  else if (count == 4 && strcmp(fields[2], "LINE") == 0 && strcmp(fields[3], "HYBRID") == 0) candidate.type = CommandType::LineHybrid;
  else if (count == 4 && strcmp(fields[2], "H") == 0 && strcmp(fields[3], "1") == 0) candidate.type = CommandType::HornOn;
  else if (count == 4 && strcmp(fields[2], "H") == 0 && strcmp(fields[3], "0") == 0) candidate.type = CommandType::HornOff;
  else if (count == 4 && strcmp(fields[2], "SPEED") == 0) {
    int32_t speed = 0;
    if (!number(fields[3], 0, 255, speed)) return false;
    candidate.type = CommandType::Speed;
    candidate.speed = static_cast<uint8_t>(speed);
  }
  else if (count == 5 && (strcmp(fields[2], "DRIVE") == 0 || strcmp(fields[2], "R") == 0)) {
    int32_t left = 0, right = 0;
    if (!number(fields[3], -200, 200, left) || !number(fields[4], -200, 200, right)) return false;
    candidate.type = strcmp(fields[2], "R") == 0 ? CommandType::RemoteDrive : CommandType::Drive;
    candidate.left = static_cast<int16_t>(left);
    candidate.right = static_cast<int16_t>(right);
  } else return false;
  command = candidate;
  return true;
}
}

bool CommandParser::expire(uint32_t now) {
  if (used_ && now - started_ms_ >= 200) {
    used_ = 0;
    discarding_ = true;
    return true;
  }
  return false;
}

ParseResult CommandParser::feed(char value, uint32_t now, Command& result) {
  const bool expired = expire(now);
  if (value == '\n') {
    if (discarding_) { discarding_ = false; return expired ? ParseResult::Invalid : ParseResult::None; }
    if (!used_) return ParseResult::None;
    if (buffer_[used_ - 1] == '\r') --used_;
    if (!used_) return ParseResult::None;
    buffer_[used_] = '\0';
    used_ = 0;
    return parse(buffer_, result) ? ParseResult::Ready : ParseResult::Invalid;
  }
  if (discarding_) return expired ? ParseResult::Invalid : ParseResult::None;
  if ((value < 32 && value != '\r') || value > 126 || used_ == sizeof(buffer_) - 1 ||
      (used_ && buffer_[used_ - 1] == '\r')) {
    used_ = 0;
    discarding_ = true;
    return ParseResult::Invalid;
  }
  if (used_ == 0) started_ms_ = now;
  buffer_[used_++] = value;
  return ParseResult::None;
}

bool execute(Controller& controller, const Command& command, Source source, const Inputs& inputs, uint32_t now) {
  controller.tick(inputs, now);
  switch (command.type) {
    case CommandType::Stop: controller.stop(); return true;
    case CommandType::ArmLine: return controller.arm(Mode::Line, source, inputs, now);
    case CommandType::ArmManual: return controller.arm(Mode::Manual, source, inputs, now);
    case CommandType::LinePulse: return controller.setLineDriveProfile(LineDriveProfile::Pulse, source);
    case CommandType::LineContinuous: return controller.setLineDriveProfile(LineDriveProfile::Continuous, source);
    case CommandType::LineHybrid: return controller.setLineDriveProfile(LineDriveProfile::Hybrid, source);
    case CommandType::Speed: return controller.setCruisePwm(command.speed, source);
    case CommandType::Drive: return controller.drive(command.left, command.right, source, now);
    case CommandType::RemoteDrive:
      return controller.remoteDrive(command.left, command.right, source, inputs, now);
    case CommandType::HornOn: return controller.horn(true, source, now);
    case CommandType::HornOff: return controller.horn(false, source, now);
    case CommandType::Ping: return controller.ping(source, now);
    case CommandType::Status: return true;
  }
  return false;
}
}
