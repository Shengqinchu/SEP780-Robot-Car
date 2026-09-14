#ifndef SEP780_CONTROLLER_H
#define SEP780_CONTROLLER_H

#include "config.h"

namespace robot {
enum class Mode : uint8_t { Idle, Line, Manual };
enum class Source : uint8_t { Serial, Infrared };
enum class State : uint8_t {
  Idle, Ready, Following, Manual, Obstacle, ClearWait, LineLost,
  AmbiguousLine, SensorFault, LowBattery, RemoteTimeout, CommandError, Stopped, BadConfig
};

struct Inputs {
  uint32_t sampled_ms = 0;
  uint32_t range_ms = 0;
  uint16_t range_mm = 0;
  uint16_t battery_mv = 0;
  uint8_t line = 0;
  bool sample_valid = false;
  bool range_valid = false;
  bool head_ready = false;
};

struct Drive { int16_t left = 0; int16_t right = 0; };

class Controller {
 public:
  explicit Controller(const Config& config = Config());
  bool arm(Mode mode, Source source, const Inputs& inputs, uint32_t now);
  bool drive(int16_t left, int16_t right, Source source, uint32_t now);
  bool ping(Source source, uint32_t now);
  void stop(State reason = State::Stopped);
  Drive tick(const Inputs& inputs, uint32_t now);
  Mode mode() const { return mode_; }
  State state() const { return state_; }
  Source owner() const { return owner_; }
  bool armed() const { return mode_ != Mode::Idle; }
  Drive output() const { return output_; }
  const Config& config() const { return config_; }

 private:
  State inputFault(const Inputs& inputs, uint32_t now) const;
  Drive output(int16_t left, int16_t right, State state);
  Config config_;
  Mode mode_ = Mode::Idle;
  Source owner_ = Source::Serial;
  State state_ = State::Idle;
  Drive output_;
  Drive requested_;
  uint32_t command_ms_ = 0;
  uint32_t drive_ms_ = 0;
  uint32_t lost_ms_ = 0;
  uint32_t clear_ms_ = 0;
  uint32_t clear_sample_ms_ = 0;
  uint8_t clear_samples_ = 0;
  bool lost_ = false;
  bool blocked_ = false;
};
}
#endif
