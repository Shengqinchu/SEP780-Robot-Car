#ifndef SEP780_CONTROLLER_H
#define SEP780_CONTROLLER_H

#include "config.h"

namespace robot {
enum class Mode : uint8_t { Idle, Line, Manual };
enum class Source : uint8_t { Serial, Infrared };
enum class LineDriveProfile : uint8_t { Pulse, Continuous, Hybrid };
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
  bool setCruisePwm(uint8_t pwm, Source source);
  bool setLineDriveProfile(LineDriveProfile profile, Source source);
  bool drive(int16_t left, int16_t right, Source source, uint32_t now);
  bool remoteDrive(int16_t left, int16_t right, Source source,
                   const Inputs& inputs, uint32_t now);
  bool horn(bool active, Source source, uint32_t now);
  bool ping(Source source, uint32_t now);
  void stop(State reason = State::Stopped);
  Drive tick(const Inputs& inputs, uint32_t now);
  Mode mode() const { return mode_; }
  State state() const { return state_; }
  Source owner() const { return owner_; }
  LineDriveProfile lineDriveProfile() const { return line_drive_profile_; }
  bool armed() const { return mode_ != Mode::Idle; }
  bool hornActive() const { return horn_active_; }
  Drive output() const { return output_; }
  const Config& config() const { return config_; }

 private:
  State inputFault(const Inputs& inputs, uint32_t now) const;
  Drive output(int16_t left, int16_t right, State state);
  void stopMotion(State reason);
  Drive lineOutput(int16_t left, int16_t right, uint32_t now, bool pulsed);
  Drive stopLinePulse(State state);
  Config config_;
  Mode mode_ = Mode::Idle;
  Source owner_ = Source::Serial;
  LineDriveProfile line_drive_profile_ = LineDriveProfile::Pulse;
  State state_ = State::Idle;
  Drive output_;
  Drive requested_;
  uint32_t command_ms_ = 0;
  uint32_t drive_ms_ = 0;
  uint32_t clear_ms_ = 0;
  uint32_t clear_sample_ms_ = 0;
  uint32_t low_battery_ms_ = 0;
  uint32_t line_pulse_ms_ = 0;
  uint32_t horn_ms_ = 0;
  uint8_t clear_samples_ = 0;
  bool blocked_ = false;
  bool low_battery_pending_ = false;
  bool line_pulse_active_ = false;
  bool horn_active_ = false;
};
}
#endif
