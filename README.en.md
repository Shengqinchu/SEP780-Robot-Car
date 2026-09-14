# SEP780 Robot Car

[中文](README.md) | **English**

An Arduino 4WD robot built on the Freenove FNK0041 kit. It follows a black line, waits when an obstacle blocks the path, and resumes when the route is clear. The supplied IR remote or a computer serial connection controls the robot; telemetry can be recorded, replayed, and analyzed.

## Features

| Feature | Behavior |
| --- | --- |
| Line following | Three reflective sensors guide independent left/right wheel speeds |
| Obstacle stop | Stops drive output near an obstacle; resumes line following after sustained clearance |
| Lost-line handling | Stops immediately, tolerates brief loss, and requires a restart after prolonged loss or an ambiguous pattern |
| Manual control | IR buttons or serial commands select forward, reverse, and turns; expired commands stop movement |
| Fault handling | Missing echoes, stale readings, low voltage, and malformed commands stop the controller |
| Debugging | Serial telemetry, CSV export, and offline scenarios running the same C++ controller |

The hardware uses the existing kit: an Uno-compatible board, four motors, three-channel tracking board, ultrasonic sensor, servo, and IR remote. This version needs no camera, Raspberry Pi, or additional modules.

## Quick start

Use **PowerShell 7** and **Python 3.10+** on x64 Windows or Linux. Run these commands from the repository root. No robot connection is needed.

```powershell
git clone https://github.com/Shengqinchu/SEP780-Robot-Car.git
cd SEP780-Robot-Car

./scripts/Setup-Toolchain.ps1
./scripts/Setup-Host.ps1
./scripts/Setup-Native.ps1

./scripts/Build.ps1 -Program robot_car
./tests/Test-Control.ps1
./tests/Test-Host.ps1
./scripts/Simulate.ps1
```

Setup downloads pinned tools on the first run. Afterwards, use the build and test commands directly. Members of this private repository need to authenticate with GitHub before cloning.

The replay reads [line_course.csv](scenarios/line_course.csv), exercising turns, obstacle waiting, recovery, lost lines, missing echoes, and timeouts. Results are written to `artifacts/local/line-course-replay.csv`:

```text
following -> obstacle -> clear_wait -> following
following -> line_lost -> following
manual    -> remote_timeout
```

This is a sensor-input logic replay. Vehicle speed and stopping distance are measured during physical calibration.

## Run on the robot

After the batteries arrive, follow the [calibration guide](docs/calibration.en.md) to center the servo and check wheel directions and sensors, then upload `robot_car`. On boot, the firmware centers the ultrasonic head and keeps the wheels stopped until an explicit start command.

| IR button | Action |
| --- | --- |
| `1` | Enter line-following mode from a stopped state |
| `2` | Enter manual mode from a stopped state |
| Direction buttons | Hold to drive forward, reverse, or turn in place in manual mode |
| Power / `0` / center play-pause / `OK` | Stop; stop before changing modes as well |

Use `scripts/Robot.ps1` for telemetry and time-limited computer control. Wiring, upload steps, command examples, and tuning are in the [calibration guide](docs/calibration.en.md). Wire-format details are in the [protocol reference](docs/control-protocol.md).

## Development and tests

```powershell
./tests/Check-Repository.ps1
./tests/Test-Control.ps1
./tests/Test-Host.ps1
./tests/Test-Docs.ps1
./scripts/Simulate.ps1
./scripts/Build.ps1 -All
```

- **C++ / Unity:** production decision logic, command framing, IR inputs, and mocked hardware I/O.
- **Python / unittest:** serial sessions, timeouts, interrupted sessions, port locks, and data exports.
- **Arduino CLI:** every vendor example and project sketch.
- **GitHub Actions:** repeats software checks on Linux; see the [runs](https://github.com/Shengqinchu/SEP780-Robot-Car/actions/workflows/compile.yml).

**Progress:** USB upload and communication have passed on the actual controller. The custom control software has passed offline checks; battery-powered calibration is next.

## Repository layout

```text
firmware/robot_car/    Controller, protocol, and FNK0041 hardware adapter
firmware/usb_check/    Standalone USB connectivity check
host/                 Python serial API, replay, and CSV export
scripts/              Setup, build, upload, and operation entry points
tests/                C++, Python, and documentation checks
scenarios/            Repeatable sensor-input scenarios
vendor/               Pinned vendor examples and Unity
docs/                 Calibration, architecture, protocol, and test guides
```

Tune [config.h](firmware/robot_car/config.h) for speed, wheel trim, distance thresholds, and timeouts. Hardware I/O is separated from decision logic so controller changes can be tested on the computer first.

## Further reading

- [Calibration](docs/calibration.en.md): the sequence to follow when the batteries arrive.
- [Controller design](docs/controller.md): states, pins, and parameters.
- [Test plan](docs/test-plan.md): software coverage and on-car acceptance checks.
- [Development log](DEVLOG.md): implementation, problems, fixes, and verification records.
- [Third-party sources](THIRD_PARTY.md): vendor code, pinned dependencies, and licenses.
