#include "controller.h"

namespace robot {
namespace {
uint32_t elapsed(uint32_t now, uint32_t then) { return now - then; }
bool trackable(uint8_t bits) { return bits == 1 || bits == 2 || bits == 3 || bits == 4 || bits == 6; }
int16_t trim(int16_t pwm, int8_t correction, uint8_t ceiling) {
  if (pwm == 0) return 0;
  const bool reverse = pwm < 0;
  int16_t magnitude = (reverse ? -pwm : pwm) + correction;
  if (magnitude < 0) magnitude = 0;
  if (magnitude > ceiling) magnitude = ceiling;
  return reverse ? -magnitude : magnitude;
}
}

Controller::Controller(const Config& config) : config_(config) {
  if (!config_.valid()) state_ = State::BadConfig;
}

State Controller::inputFault(const Inputs& in, uint32_t now) const {
  if (!config_.valid()) return State::BadConfig;
  if (!in.sample_valid || !in.head_ready || in.line > 7 ||
      elapsed(now, in.sampled_ms) >= config_.input_max_age_ms || !in.range_valid ||
      elapsed(now, in.range_ms) >= config_.range_max_age_ms || in.range_mm < 20 ||
      in.range_mm > 4000 || in.battery_mv > config_.battery_max_mv) return State::SensorFault;
  return State::Ready;
}

bool Controller::arm(Mode mode, Source source, const Inputs& in, uint32_t now) {
  // Re-arming cannot silently steal control or keep a stale movement alive.
  if (armed() || (mode != Mode::Line && mode != Mode::Manual)) return false;
  const State fault = inputFault(in, now);
  if (fault != State::Ready) { stop(fault); return false; }
  if (in.battery_mv < config_.battery_min_mv) { stop(State::LowBattery); return false; }
  mode_ = mode;
  owner_ = source;
  if (mode == Mode::Line && source == Source::Infrared) {
    line_drive_profile_ = LineDriveProfile::Pulse;
  }
  state_ = State::Ready;
  output_ = Drive();
  requested_ = Drive();
  command_ms_ = drive_ms_ = now;
  blocked_ = false;
  clear_samples_ = 0;
  low_battery_pending_ = false;
  line_pulse_active_ = false;
  return true;
}

bool Controller::setCruisePwm(uint8_t pwm, Source source) {
  if (armed() || source != Source::Serial || pwm < config_.min_runtime_pwm ||
      pwm > config_.max_pwm) return false;
  config_.cruise_pwm = pwm;
  return true;
}

bool Controller::setLineDriveProfile(LineDriveProfile profile, Source source) {
  if (armed() || source != Source::Serial) return false;
  line_drive_profile_ = profile;
  line_pulse_active_ = false;
  return true;
}

bool Controller::drive(int16_t left, int16_t right, Source source, uint32_t now) {
  if (mode_ != Mode::Manual || owner_ != source) return false;
  if (elapsed(now, drive_ms_) >= config_.manual_lease_ms ||
      (owner_ == Source::Serial && elapsed(now, command_ms_) >= config_.serial_lease_ms)) {
    stop(State::RemoteTimeout); return false;
  }
  if (left < -config_.max_pwm || left > config_.max_pwm || right < -config_.max_pwm || right > config_.max_pwm) {
    stop(State::CommandError); return false;
  }
  requested_.left = left;
  requested_.right = right;
  drive_ms_ = command_ms_ = now;
  return true;
}

bool Controller::remoteDrive(int16_t left, int16_t right, Source source,
                             const Inputs& in, uint32_t now) {
  if (source != Source::Serial) return false;
  if (left < -config_.max_pwm || left > config_.max_pwm ||
      right < -config_.max_pwm || right > config_.max_pwm) {
    stop(State::CommandError);
    return false;
  }
  if (left == 0 && right == 0) {
    stopMotion(State::Stopped);
    return true;
  }
  if (mode_ != Mode::Manual || owner_ != source) {
    // A live joystick frame is an explicit takeover request. Make the
    // transition atomic so stale ARM/DRIVE pairs cannot race each other.
    stopMotion(State::Stopped);
    if (!arm(Mode::Manual, source, in, now)) return false;
  }
  return drive(left, right, source, now);
}

bool Controller::horn(bool active, Source source, uint32_t now) {
  if (source != Source::Serial) return false;
  horn_active_ = active;
  horn_ms_ = now;
  return true;
}

bool Controller::ping(Source source, uint32_t now) {
  if (!armed() || owner_ != source) return false;
  if (owner_ == Source::Serial && elapsed(now, command_ms_) >= config_.serial_lease_ms) {
    stop(State::RemoteTimeout); return false;
  }
  command_ms_ = now;
  return true;
}

void Controller::stop(State reason) {
  stopMotion(reason);
  horn_active_ = false;
}

void Controller::stopMotion(State reason) {
  mode_ = Mode::Idle;
  state_ = reason;
  output_ = Drive();
  requested_ = Drive();
  blocked_ = false;
  clear_samples_ = 0;
  low_battery_pending_ = false;
  line_pulse_active_ = false;
}

Drive Controller::output(int16_t left, int16_t right, State state) {
  state_ = state;
  output_.left = trim(left, config_.left_trim_pwm, config_.max_pwm);
  output_.right = trim(right, config_.right_trim_pwm, config_.max_pwm);
  return output_;
}

Drive Controller::stopLinePulse(State state) {
  line_pulse_active_ = false;
  return output(0, 0, state);
}

Drive Controller::lineOutput(int16_t left, int16_t right, uint32_t now, bool pulsed) {
  if (!pulsed) {
    line_pulse_active_ = false;
    return output(left, right, State::Following);
  }
  if (!line_pulse_active_) {
    line_pulse_active_ = true;
    line_pulse_ms_ = now;
  }
  const uint32_t cycle = static_cast<uint32_t>(config_.line_pulse_on_ms) +
    config_.line_pulse_off_ms;
  const uint32_t phase = elapsed(now, line_pulse_ms_) % cycle;
  if (phase >= config_.line_pulse_on_ms) return output(0, 0, State::Following);
  return output(left, right, State::Following);
}

Drive Controller::tick(const Inputs& in, uint32_t now) {
  if (horn_active_ && elapsed(now, horn_ms_) >= config_.horn_lease_ms) {
    horn_active_ = false;
  }
  if (!armed()) return output_;
  const State fault = inputFault(in, now);
  if (fault != State::Ready) { stop(fault); return output_; }
  if (in.battery_mv < config_.battery_min_mv) {
    if (!low_battery_pending_) {
      low_battery_pending_ = true;
      low_battery_ms_ = now;
    } else if (elapsed(now, low_battery_ms_) >= config_.battery_low_hold_ms) {
      stop(State::LowBattery);
      return output_;
    }
  } else {
    low_battery_pending_ = false;
  }
  if ((owner_ == Source::Serial && elapsed(now, command_ms_) >= config_.serial_lease_ms) ||
      (mode_ == Mode::Manual && elapsed(now, drive_ms_) >= config_.manual_lease_ms)) {
    stop(State::RemoteTimeout); return output_;
  }

  if (mode_ == Mode::Line) {
    if (in.line == 0) {
      return stopLinePulse(State::LineLost);
    }
    if (!trackable(in.line)) return stopLinePulse(State::AmbiguousLine);
  }

  if (mode_ == Mode::Manual) {
    // Keep the remote session alive at a front obstacle. Forward translation
    // is held at zero, while reverse and counter-rotation remain available.
    if (in.range_mm <= config_.obstacle_stop_mm &&
        static_cast<int32_t>(requested_.left) + requested_.right > 0) {
      return output(0, 0, State::Obstacle);
    }
    return output(requested_.left, requested_.right, State::Manual);
  }

  if (in.range_mm <= config_.obstacle_stop_mm) {
    blocked_ = true;
    clear_samples_ = 0;
    return stopLinePulse(State::Obstacle);
  }
  if (blocked_) {
    if (in.range_mm < config_.obstacle_resume_mm) {
      clear_samples_ = 0;
    } else if (clear_samples_ == 0) {
      clear_ms_ = now;
      clear_sample_ms_ = in.range_ms;
      clear_samples_ = 1;
    } else if (in.range_ms != clear_sample_ms_) {
      clear_sample_ms_ = in.range_ms;
      if (clear_samples_ < 3) ++clear_samples_;
    }
    if (clear_samples_ < 3 || elapsed(now, clear_ms_) < config_.clear_hold_ms) {
      return stopLinePulse(State::ClearWait);
    }
    blocked_ = false;
  }

  const int16_t cruise = config_.line_pulse_pwm;
  const int16_t turn = config_.line_turn_pwm;
  const int16_t gentle = cruise - config_.turn_reduction_pwm;
  int16_t left = cruise;
  int16_t right = cruise;
  bool pulsed = line_drive_profile_ != LineDriveProfile::Continuous;
  switch (in.line) {
    case 4:
      left = line_drive_profile_ == LineDriveProfile::Hybrid ? -turn : 0;
      if (line_drive_profile_ == LineDriveProfile::Hybrid) right = turn;
      if (line_drive_profile_ == LineDriveProfile::Hybrid) pulsed = false;
      break;
    case 6:
      left = gentle;
      if (line_drive_profile_ == LineDriveProfile::Hybrid) { right = turn; pulsed = false; }
      break;
    case 1:
      right = line_drive_profile_ == LineDriveProfile::Hybrid ? -turn : 0;
      if (line_drive_profile_ == LineDriveProfile::Hybrid) left = turn;
      if (line_drive_profile_ == LineDriveProfile::Hybrid) pulsed = false;
      break;
    case 3:
      right = gentle;
      if (line_drive_profile_ == LineDriveProfile::Hybrid) { left = turn; pulsed = false; }
      break;
    default: break;
  }
  return lineOutput(left, right, now, pulsed);
}
}
