# SEP780 Robot Car

[中文](README.md) | **English**

An Arduino 4WD robot built on the Freenove FNK0041 kit. It follows a black line, waits when an obstacle blocks the path, and resumes when the route is clear. The supplied IR remote, an Android voice app, or a computer serial connection controls the robot; telemetry can be recorded, replayed, and analyzed.

## Features

| Feature | Behavior |
| --- | --- |
| Line following | Three reflective sensors guide the wheels; the app selects Pulse or Normal hybrid drive under the same stop interlocks |
| Obstacle stop | Stops and emits a short repeating alert near an obstacle; resumes after sustained clearance |
| Lost-line handling | Stops and waits on a lost or ambiguous line, then resumes after a valid path returns; button `0` still latches a stop |
| Manual control | IR buttons or an Android analog joystick; differential mixing, ramped acceleration, release-to-stop, and a 110–200 PWM remote limit |
| Phone voice control | Android maps a finite Chinese/English vocabulary to the same safe serial protocol; directional actions are time-bounded |
| Manual horn | Hold in the app to sound and release to stop; the active buzzer supports alert rhythms, not pitched melodies |
| Fault handling | Missing echoes, stale readings, low voltage, and malformed commands stop the controller |
| Debugging | Serial telemetry, CSV export, and offline scenarios running the same C++ controller |

The hardware uses the existing kit: an Uno-compatible board, four motors, three-channel tracking board, ultrasonic sensor, servo, IR remote, and BT05 module. This version needs no camera, Raspberry Pi, or additional modules.

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

Build the Android app separately on x64 Windows:

```powershell
./scripts/Setup-Android.ps1
./scripts/Build-Android.ps1
```

The replay reads [line_course.csv](scenarios/line_course.csv), exercising turns, obstacle waiting, recovery, lost lines, missing echoes, and timeouts. Results are written to `artifacts/local/line-course-replay.csv`:

```text
following -> obstacle -> clear_wait -> following
following -> line_lost -> following
manual    -> remote_timeout
```

This is a sensor-input logic replay. Vehicle speed and stopping distance are measured during physical calibration.

## Run on the robot

Before a real run, follow the [calibration guide](docs/calibration.en.md) to confirm the servo center, wheel direction, and sensor readings before using `robot_car`. On boot, the firmware centers the ultrasonic head and keeps the wheels stopped until an explicit start command.

| IR button | Action |
| --- | --- |
| `1` | Enter line-following mode from a stopped state |
| `2` | Enter manual mode from a stopped state |
| Direction buttons | Hold to drive forward, reverse, or turn in place in manual mode |
| Power / `0` / center play-pause / `OK` | Stop; stop before changing modes as well |

See the [voice-control guide](docs/voice-control.en.md) for Android connection and vocabulary. Use `scripts/Robot.ps1` for telemetry and time-limited computer control. Wiring, upload steps, command examples, and tuning are in the [calibration guide](docs/calibration.en.md). Wire-format details are in the [protocol reference](docs/control-protocol.md).

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
- **Android / JUnit:** finite voice vocabulary, protocol encoding, differential mixing, acceleration limiting, telemetry parsing, and debug APK compilation.
- **GitHub Actions:** repeats vehicle-side software checks on Linux; see the [runs](https://github.com/Shengqinchu/SEP780-Robot-Car/actions/workflows/compile.yml).

**Progress:** Servo, ranging, wheel direction, BLE, and the Normal line profile have completed physical integration; on the same course, the user observed a substantially higher success rate in Normal than Pulse. Line behavior remains an 80/80 ms PWM 120 centered pulse with PWM 150 turns and is unchanged by this remote-control revision. The new controller uses one atomic `R` command, a 20 Hz latest-value queue, an analog differential joystick, a 110–200 limit with a 150 default, acceleration limiting, and neutral-before-reverse. It also adds a hold-to-sound horn with a 1.5-second disconnect lease. The revision passes 114 C++ tests, 80 host tests, 16 Android unit tests/Lint, and firmware compilation. On 2026-09-21 it was flashed to COM5 and installed over the previous Redmi app; both language layouts and the USB-only `idle / 0 / 0` safe default were accepted. The user then completed a powered integration session and reported that the current functions are usable overall. An occasional ignored input with `command rejected` remains; no failure-time ACK/telemetry trace has been captured, so it is retained as a known issue that does not block current demo preparation. Low-voltage, sensor-fault, emergency-stop, and communication-lease interlocks remain active.

## Repository layout

```text
firmware/robot_car/    Controller, protocol, and FNK0041 hardware adapter
firmware/usb_check/    Standalone USB connectivity check
firmware/motor_check/  One-shot lifted-wheel motor diagnostic without sensor gates
host/                 Python serial API, replay, and CSV export
mobile/android/       Native Android BLE and voice-control app
scripts/              Setup, build, upload, and operation entry points
tests/                C++, Python, and documentation checks
scenarios/            Repeatable sensor-input scenarios
vendor/               Pinned vendor examples and Unity
docs/                 Calibration, architecture, protocol, and test guides
```

Tune [config.h](firmware/robot_car/config.h) for speed, wheel trim, distance thresholds, and timeouts. Hardware I/O is separated from decision logic so controller changes can be tested on the computer first.

## Further reading

- [Calibration](docs/calibration.en.md): wiring, upload, and real-hardware calibration sequence.
- [Controller design](docs/controller.md): states, pins, and parameters.
- [Test plan](docs/test-plan.md): software coverage and on-car acceptance checks.
- [Android voice control](docs/voice-control.en.md): build, finite vocabulary, connection, and first acceptance run.
- [Project demo guide](docs/demo-guide.en.md): bilingual script, course layout, acceptance gates, and recovery plan.
- [Development log](DEVLOG.md): implementation, problems, fixes, and verification records.
- [Third-party sources](THIRD_PARTY.md): vendor code, pinned dependencies, and licenses.
