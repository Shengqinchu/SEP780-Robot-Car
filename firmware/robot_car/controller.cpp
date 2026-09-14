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
  if (in.battery_mv < config_.battery_min_mv) return State::LowBattery;
  return State::Ready;
}

bool Controller::arm(Mode mode, Source source, const Inputs& in, uint32_t now) {
  // Re-arming cannot silently steal control or keep a stale movement alive.
  if (armed() || (mode != Mode::Line && mode != Mode::Manual)) return false;
  const State fault = inputFault(in, now);
  if (fault != State::Ready) { stop(fault); return false; }
  if (in.range_mm < config_.obstacle_resume_mm) { stop(State::Obstacle); return false; }
  if (mode == Mode::Line && !trackable(in.line)) {
    stop(in.line == 0 ? State::LineLost : State::AmbiguousLine); return false;
  }
  mode_ = mode;
  owner_ = source;
  state_ = State::Ready;
  output_ = Drive();
  requested_ = Drive();
  command_ms_ = drive_ms_ = now;
  lost_ = blocked_ = false;
  clear_samples_ = 0;
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

bool Controller::ping(Source source, uint32_t now) {
  if (!armed() || owner_ != source) return false;
  if (owner_ == Source::Serial && elapsed(now, command_ms_) >= config_.serial_lease_ms) {
    stop(State::RemoteTimeout); return false;
  }
  command_ms_ = now;
  return true;
}

void Controller::stop(State reason) {
  mode_ = Mode::Idle;
  state_ = reason;
  output_ = Drive();
  requested_ = Drive();
  lost_ = blocked_ = false;
  clear_samples_ = 0;
}

Drive Controller::output(int16_t left, int16_t right, State state) {
  state_ = state;
  output_.left = trim(left, config_.left_trim_pwm, config_.max_pwm);
  output_.right = trim(right, config_.right_trim_pwm, config_.max_pwm);
  return output_;
}

Drive Controller::tick(const Inputs& in, uint32_t now) {
  if (!armed()) return output_;
  const State fault = inputFault(in, now);
  if (fault != State::Ready) { stop(fault); return output_; }
  if ((owner_ == Source::Serial && elapsed(now, command_ms_) >= config_.serial_lease_ms) ||
      (mode_ == Mode::Manual && elapsed(now, drive_ms_) >= config_.manual_lease_ms)) {
    stop(State::RemoteTimeout); return output_;
  }

  if (mode_ == Mode::Line) {
    if (in.line == 0) {
      if (!lost_) { lost_ = true; lost_ms_ = now; }
      if (elapsed(now, lost_ms_) >= config_.line_lost_ms) { stop(State::LineLost); return output_; }
    } else {
      lost_ = false;
      if (!trackable(in.line)) { stop(State::AmbiguousLine); return output_; }
    }
  }

  if (in.range_mm <= config_.obstacle_stop_mm) {
    if (mode_ == Mode::Manual) { stop(State::Obstacle); return output_; }
    blocked_ = true;
    clear_samples_ = 0;
    return output(0, 0, State::Obstacle);
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
      return output(0, 0, State::ClearWait);
    }
    blocked_ = false;
  }

  if (mode_ == Mode::Manual) return output(requested_.left, requested_.right, State::Manual);
  if (lost_) return output(0, 0, State::LineLost);
  const int16_t cruise = config_.cruise_pwm;
  const int16_t gentle = cruise - config_.turn_reduction_pwm;
  switch (in.line) {
    case 4: return output(0, cruise, State::Following);
    case 6: return output(gentle, cruise, State::Following);
    case 1: return output(cruise, 0, State::Following);
    case 3: return output(cruise, gentle, State::Following);
    default: return output(cruise, cruise, State::Following);
  }
}
}
