# Battery-powered calibration

[中文](calibration.md) | [README](../README.en.md)

Work in this order and change one parameter at a time. Record the firmware commit, settings, surface, and observations. Prepare a ruler, light-colored test surface, black tape, and a stable support that lifts all four wheels.

## 1. Establish the vendor hardware baseline

Check polarity, plugs, and switches against the [assembly checklist](bring-up.md). Disconnect power before changing wiring, and remove Bluetooth before uploading. Keep wheels lifted, the ultrasonic head unobstructed, and the power switch accessible.

1. Upload `servo_center`, observe actual centering, then disconnect power and secure the head facing forward.
2. Prefer the project `motor_check` with all wheels lifted. It waits 3 seconds after boot, commands one vendor-baseline PWM 200 forward pulse for 1 second, and then stops permanently without reading the ultrasonic or other sensors. Use the vendor `motor_test`, which automatically repeats motion, only for later fault isolation.
3. Run `tracking_sensor` and cover each sensor individually with black and light surfaces.
4. Run `ultrasonic_test` against a flat, reflective target. This vendor sketch automatically sweeps the servo.

Resolve baseline wiring, power, or mounting problems before changing the project control algorithm.

No visible movement with `servo_center` may mean the servo was already centered; it proves neither success nor failure. After reconfirming wiring, power state, and port, the project diagnostic [`servo_check`](../firmware/servo_check/servo_check.ino) holds both motor PWM pins low and makes one small sweep around the candidate center documented in its source per boot/reset, then holds that center after about 7.5 seconds. Disconnect battery power for upload. For the test, unplug USB and reconnect the battery plug to the upper board with both switches off, keep wheels lifted and the head clear, then power on, observe for about 8 seconds, and switch off. Serial output reports commanded angles, not measured position; opening serial may reset the board and repeat motion. Cut power immediately for binding/buzzing, sustained jitter, heating, or unexpected wheel motion; never force the servo by hand.

`motor_check` also runs once on every power-up or reset. For upload, turn both switches off, disconnect the round battery-power plug, and connect only the lower-board USB-C. For the test, unplug USB, keep all four wheels securely lifted with hands, clothing, and cables clear, then reconnect the battery and turn on both switches. After the 3-second warning, observe the 1-second pulse and switch power off; record whether all wheels turn and whether their ground-contact points move in the same forward direction. This diagnostic temporarily replaces the final firmware, so upload `robot_car` again after the check.

On this car, the first physical run with the vendor-positive polarity started all four wheels at PWM 200, but the top of each wheel moved toward the rear, which is reverse travel. The project firmware therefore inverts both motor sides, and the diagnostic now uses the same calibrated polarity. This is a hardware adaptation for this car; the vendor snapshot remains unchanged.

Inspect actual pin engagement, not only wire colors: all three SERVO pins, `SIG[2]`, `5V`, and `GND`, must enter their matching connector sockets. Pay particular attention to the outer signal pin. During bring-up, a missed signal pin caused no servo movement despite normal board lights; reseating the connector with power disconnected restored motion.

If the servo moves but the head finishes off-center, first mount the horn on the spline position nearest to straight ahead. If the spline cannot align it exactly, finish with a small software trim; the vendor calibration path limits this trim to about `-10..+10` degrees. The first physical trial at `+8` degrees, a `98` degree center, increased the error. Reversing the trim to `-8` degrees, an `82` degree center, produced a physical result that is approximately aligned with the vehicle centerline, so the project now uses `82` degrees as its center; the diagnostic sweeps only `5` degrees on either side. With all power removed, install the servo's original smallest center retaining screw. Do not force the shaft, use a large software offset to mask the wrong spline, or open the servo case. Visual alignment does not replace range validation; verify readings against a flat target directly ahead.

## 2. Upload the project controller

`robot_car` centers the servo at boot but keeps the wheels stopped until armed. Keep the wheels lifted and allow head travel. Upload with the car POWER switch off using the vendor procedure, then connect the correct battery supply and switch the car on.

```powershell
./scripts/List-Boards.ps1
$port = Read-Host 'Enter the verified robot serial port'
./scripts/Upload.ps1 -Program robot_car -Port $port -ConfirmHardwareReady
./scripts/Robot.ps1 -Action observe -Port $port -Seconds 10 -ConfirmHardwareReady
```

`observe` sends no commands and records line bits, distance, voltage, mode, and commanded wheel PWM. Opening serial can reset the board and recenter the head. Close other serial monitors first.

## 3. Check readings and directions

Edit [config.h](../firmware/robot_car/config.h), rebuild, test, and explicitly upload after changes.

| Check | Method | Setting |
| --- | --- | --- |
| Head center | Confirm that nominal 90 degrees points forward; correct horn mounting first | `hardware::servo_center_degrees` |
| Battery reading | Compare telemetry with a meter at the battery; inspect wiring/divider if substantially different | `hardware::adc_full_scale_mv`, initially 20000 |
| Black/white polarity | Verify each sensor; vendor convention is black = 1 | `hardware::black_reads_high` |
| Motor polarity | Short, lifted-wheel commands; positive values must mean forward on both sides | `hardware::invert_left_motor`, `invert_right_motor` |
| Wheel mismatch | Repeat short low-speed straight runs, then make small corrections | `left_trim_pwm`, `right_trim_pwm` |

Arming requires a valid forward echo at roughly 30 cm to 4 m. Missing echoes appear as `range_mm=0` and stop the controller; they are not treated as unlimited clearance. The initial software battery window is 6.6 V to 9.0 V. Low voltage rejects ARM immediately, while a running controller requires 300 ms of continuous undervoltage before latching a stop so that one motor-start ADC transient is not mistaken for an exhausted pack. This remains a software check, not a substitute for cell protection or a charger.

Start with a one-second lifted-wheel command:

```powershell
./scripts/Robot.ps1 -Action drive -Port $port -Left 70 -Right 70 -Seconds 1 -ConfirmHardwareReady -ConfirmMotionClear
./scripts/Robot.ps1 -Action stop -Port $port -ConfirmHardwareReady
```

If low PWM does not move the wheels, check power, plugs, and direction before gradually increasing it. Keep initial ground tests short and slow.

## 4. Tune line following and obstacle stops

Use one matte black line on a matte white surface. Begin with straight sections, then broad curves, and avoid direct sunlight on the tracking sensors. Wood-colored floors, visible grain, and glossy surfaces are not stable references. If the floor cannot be changed, lay down white poster paper, foam board, or a sufficiently wide strip of white tape before adding the black center line. Expected stationary readings are `000` on all white, `010` with only the center sensor over black, and `100`/`001` with only the left/right sensor over black. If the wood floor and black line produce the same binary value, the current three digital inputs contain no contrast for software to recover; change the background or add a separately validated analog-sensing hardware path.

| Parameter | Initial value | Tune for |
| --- | --- | --- |
| `cruise_pwm` | 100 | Default for compatible firmware commands; the new app does not use it as the joystick limit |
| `min_runtime_pwm` | 50 | Firmware compatibility floor; physical observation found that 50–100 could not start reliably, so the app starts at 110 |
| `line_pulse_pwm` | 120 | Fixed amplitude for Pulse and centered Normal travel; the app manual limit does not change it |
| `line_turn_pwm` | 150 | Continuous Normal correction amplitude; it does not increase straight speed |
| `line_pulse_on_ms` / `line_pulse_off_ms` | 80 / 80 | Drive, then coast at zero PWM; turns and inertia must be accepted on the fixed white course |
| `turn_reduction_pwm` | 120 | Normal zeros the inner wheel on `110/011`; `100/001` further reverses the inner wheel |
| `max_pwm` | 200 | Firmware and app output ceiling; PWM is not a physical speed measurement |
| `obstacle_stop_mm` | 200 | Clearance after accounting for measurement error and coasting distance |
| `obstacle_resume_mm` | 300 | A larger threshold to prevent repeated start/stop at the boundary |
| `clear_hold_ms` | 600 | Sustained clearance with at least three distinct measurements |

On the IR remote, `1` starts line following and `0` or Power stops it. For manual mode, press `2` and hold a direction button. Releasing the button expires the movement command after the default 350 ms. Stop before changing modes.

The app's Pulse / Normal selector chooses the line-output strategy. Pulse uses no `delay()` and applies PWM 120 for 80 ms drive / 80 ms coast to every valid pattern. Normal keeps the same rhythm on centered `010`, continuously applies PWM 150 to the outer wheel on `110/011`, and uses `-150/150` or `150/-150` on `100/001`. Both profiles immediately request zero for an obstacle, `000/101/111`, STOP, low voltage, or a sensor fault, and neither performs a blind lost-line search. Changing the profile stops first; IR button `1` always uses Pulse.

The new racing joystick controls manual mode only. Its selectable limit is 110–200, with 150 as the default. Stick magnitude and direction pass through dead zones, a response curve, differential mixing, and acceleration/deceleration limiting, with at most one frame every 50 ms. Release must immediately return to `0/0`. Lift the wheels and check small forward input, full forward, left/right arcs, counter-rotation, reverse, and direction reversal. Confirm telemetry requests and physical directions before a short ground test. Holding Horn should produce repeated short beeps; release, STOP, or disconnect must silence it. Because the buzzer and battery ADC share A0, also confirm that telemetry keeps updating and that horn use does not cause a false low-voltage latch.

The same-course A/B was completed on 2026-09-21: Pulse made periodic attempts but could not overcome the sharp-turn load, while fully Continuous drive was too fast on the straight and left the line. A later lifted observation found that a reversing side did not start reliably from rest at PWM 120 but could move after a centered forward transition. That is stronger evidence of reverse-direction starting torque than of a failed side. The vendor line example uses turns up to about `160/-140`, and this chassis already passed a bidirectional motor test at PWM 150, so the currently flashed revision raises only Normal turns to 150. Repeat from the same start: centered travel should remain pulsed, a side deviation should hold the correction, and a single-side pattern should counter-rotate. Stop immediately if it turns the wrong way, then verify the app's three-bit telemetry and physical left/right mapping. At `000/101/111`, the controller must stop rather than hide a course or coverage problem with blind motion. Change one parameter at a time and preserve five runs after selecting the final profile.

The controller's built-in `L` LED stays on only while a control mode is actually armed; it turns off after a stop or rejected start. Activity on the receiver board only means that an IR signal was seen and is not an armed-state indication.

For a bounded computer-controlled run:

```powershell
./scripts/Robot.ps1 -Action line -Port $port -Seconds 5 -ConfirmHardwareReady -ConfirmMotionClear
```

Computer sessions send STOP on completion or error. Opening serial can reset the controller, so a motion session waits up to 3 seconds for its first valid `20..4000 mm` range before sending ARM; a timeout leaves the car stopped and saves a failed trace. A serial-owned line-following session stops after 1200 ms without valid control traffic; IR-started line following runs independently of the computer. Use IR for untethered ground tests and keep USB cables away from wheels.

This version waits for front obstacles; it does not plan a detour. In manual mode, the front guard blocks net forward motion but preserves reverse and counter-rotation so the operator can escape. There is no rear/side obstacle sensing, so the operator must watch the reverse path. A stop sets PWM to zero; it does not guarantee instantaneous mechanical braking.

## 5. Record and repeat

Repeat each applicable item in the [test plan](test-plan.md) at least five times. Record success counts, failures, distances, and resets. Leave unperformed items untested.

Robot traces are saved as `artifacts/local/robot-*.jsonl`. Export a selected session:

```powershell
. ./scripts/Common.ps1
$trace = Read-Host 'Enter the robot JSONL trace path'
& (Get-HostPython) -X utf8 ./host/export_telemetry.py $trace ./artifacts/local/calibration.csv
```

Use the [hardware test template](templates/hardware-test.md), then append measured findings and parameter changes to [DEVLOG.md](../DEVLOG.md). Repeat the same route with the final settings and compare vendor and project firmware.
