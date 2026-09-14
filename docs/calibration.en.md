# Battery-powered calibration

[中文](calibration.md) | [README](../README.en.md)

Work in this order and change one parameter at a time. Record the firmware commit, settings, surface, and observations. Prepare a ruler, light-colored test surface, black tape, and a stable support that lifts all four wheels.

## 1. Establish the vendor hardware baseline

Check polarity, plugs, and switches against the [assembly checklist](bring-up.md). Disconnect power before changing wiring, and remove Bluetooth before uploading. Keep wheels lifted, the ultrasonic head unobstructed, and the power switch accessible.

1. Upload `servo_center`, observe actual centering, then disconnect power and secure the head facing forward.
2. Run `motor_test` with wheels lifted. The vendor sketch automatically repeats movements; check that all wheel directions agree.
3. Run `tracking_sensor` and cover each sensor individually with black and light surfaces.
4. Run `ultrasonic_test` against a flat, reflective target. This vendor sketch automatically sweeps the servo.

Resolve baseline wiring, power, or mounting problems before changing the project control algorithm.

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

Arming requires a valid forward echo at roughly 30 cm to 4 m. Missing echoes appear as `range_mm=0` and stop the controller; they are not treated as unlimited clearance. The initial software battery window is 6.6 V to 9.0 V, not a substitute for cell protection or a charger.

Start with a one-second lifted-wheel command:

```powershell
./scripts/Robot.ps1 -Action drive -Port $port -Left 70 -Right 70 -Seconds 1 -ConfirmHardwareReady -ConfirmMotionClear
./scripts/Robot.ps1 -Action stop -Port $port -ConfirmHardwareReady
```

If low PWM does not move the wheels, check power, plugs, and direction before gradually increasing it. Keep initial ground tests short and slow.

## 4. Tune line following and obstacle stops

Use one black line on a light surface. Begin with straight sections, then broad curves. Avoid direct sunlight on the tracking sensors.

| Parameter | Initial value | Tune for |
| --- | --- | --- |
| `cruise_pwm` | 90 | Reliable starts without overshooting curves |
| `turn_reduction_pwm` | 50 | Steering when two adjacent sensors see the line |
| `max_pwm` | 150 | Output ceiling, not a speed measurement |
| `obstacle_stop_mm` | 200 | Clearance after accounting for measurement error and coasting distance |
| `obstacle_resume_mm` | 300 | A larger threshold to prevent repeated start/stop at the boundary |
| `clear_hold_ms` | 600 | Sustained clearance with at least three distinct measurements |
| `line_lost_ms` | 400 | Immediate zero output on line loss; prolonged loss requires another start |

On the IR remote, `1` starts line following and `0` or Power stops it. For manual mode, press `2` and hold a direction button. Releasing the button expires the movement command after the default 350 ms. Stop before changing modes.

For a bounded computer-controlled run:

```powershell
./scripts/Robot.ps1 -Action line -Port $port -Seconds 5 -ConfirmHardwareReady -ConfirmMotionClear
```

Computer sessions send STOP on completion or error. A serial-owned line-following session stops after 1200 ms without valid control traffic; IR-started line following runs independently of the computer. Use IR for untethered ground tests and keep USB cables away from wheels.

This version waits for front obstacles; it does not plan a detour. The front guard stops all manual movement, including reverse. There is no rear/side obstacle sensing. A stop sets PWM to zero; it does not guarantee instantaneous mechanical braking.

## 5. Record and repeat

Repeat each applicable item in the [test plan](test-plan.md) at least five times. Record success counts, failures, distances, and resets. Leave unperformed items untested.

Robot traces are saved as `artifacts/local/robot-*.jsonl`. Export a selected session:

```powershell
. ./scripts/Common.ps1
$trace = Read-Host 'Enter the robot JSONL trace path'
& (Get-HostPython) -X utf8 ./host/export_telemetry.py $trace ./artifacts/local/calibration.csv
```

Use the [hardware test template](templates/hardware-test.md), then append measured findings and parameter changes to [DEVLOG.md](../DEVLOG.md). Repeat the same route with the final settings and compare vendor and project firmware.
