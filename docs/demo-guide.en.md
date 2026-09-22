# Project Demo Guide

[Bilingual script](demo-script-bilingual.md) | [中文](demo-guide.md) | [README](../README.en.md) | [Test plan](test-plan.md)

## Readiness status

The software feature set is complete enough to begin demo preparation. The new phone remote and horn are installed, and the user reports that powered integration is usable overall; occasional `command rejected` responses remain a known issue. Two evidence gates remain on the fixed white-background course:

1. real-car validation of Chinese or English voice stop, timed directional movement, and line-follow start;
2. at least five Normal runs on the same complete route at straight/turn PWM 120/150, with successes, failures, and evidence recorded. If a command is rejected during rehearsal, preserve the app state, ACK, and telemetry.

The available course files assign 35% to the `Project Presentation and Report`. The learning plan places `Demo and Report` in the week of December 3, 2026. The local material does not state a video duration, report length, or detailed rubric. This guide is written for a recorded demo. Confirm the final duration, format, and upload requirements in Avenue.

## What the demo must prove

The video does not need to repeat every engineering test. Use one continuous main shot plus a close view of the app to establish five points:

| Objective | Visible evidence |
| --- | --- |
| Safe startup | The wheels remain stopped after power-up and both requested outputs remain zero after connection |
| Phone control | The Bluetooth indicator turns blue and battery, range, and three line sensors update |
| Racing remote | The joystick continuously controls throttle and steering, release returns to zero, and the speed limit and manual horn are usable |
| Voice control | A bounded bilingual vocabulary is converted into time-limited safe commands |
| Autonomous line and obstacle behavior | The car follows the line, stops and beeps within 20 cm, then resumes only after clearance exceeds 30 cm for 600 ms |
| Fail-safe behavior | Line loss, ambiguous line input, lost communication, low voltage, or invalid ranging does not leave the car driving blindly |

The left and right PWM fields are controller requests, not encoder-measured wheel speeds. Do not describe them as closed-loop speed feedback.

## Course layout

### Recommended layout

- Use matte white poster board, foam board, or a white table with one matte black line.
- Begin with a straight section at least two car lengths long, followed by one broad curve. Do not add intersections, sharp corners, or active obstacle avoidance.
- Reserve a straight section for the obstacle. Use a flat vertical board that reflects ultrasound; do not keep a hand in front of the moving car.
- Place the car at the center of the start line. The normalized sensor pattern should be `010` before launch.
- Leave stopping space after the finish. Avoid direct sunlight, reflective tape, wood grain, and unsupported table edges.

```text
             obstacle zone
                 [#]
                  |
START =========\     /========= FINISH
                \___/

matte white base, one black line, one broad curve, obstacle on a straight
```

With no near obstacle, the car still requires a valid forward echo at roughly 30 cm to 4 m. If the course is too open and ranging remains invalid, reorient the course or add a distant flat backdrop. Do not disable the sensor-fault rule.

### Equipment

- Two charged, undamaged 18650 cells and the correct battery holder;
- the Android phone with the SEP780 app installed;
- the stock IR remote as a backup stop path;
- white course material, matte black tape, and a flat obstacle;
- a phone stand or second phone for continuous recording;
- a USB data cable and computer for recovery only, not tethered driving.

## Pre-demo acceptance

Mark the demo `Ready` only after every row passes.

| Gate | Pass criterion | Result |
| --- | --- | --- |
| Default stop | No unintended wheel motion on five consecutive power cycles | [ ] |
| Line profile | Normal first passes lifted straight PWM 120 and left/right turn PWM 150 checks, then completes five starts, straight sections, and broad turns on the same course | [ ] |
| Phone connection | Indicator turns blue, telemetry updates, and initial outputs are zero | [ ] |
| Manual drive and horn | Lifted tests pass every joystick direction, release-to-zero, reverse escape near a front obstacle, and hold/release horn | [ ] |
| Voice stop | “stop” or “停止” prevents subsequent motion in five consecutive trials | [ ] |
| Voice direction | Forward, reverse, left, and right each run once and stop after about one second | [ ] |
| Voice line follow | “follow line” or “开始循迹” starts the mode and the app maintains its lease | [ ] |
| Obstacle interlock | Five trials stop before contact, beep, and resume only after valid clearance | [ ] |
| Line-loss safety | Requested PWM returns to zero on invalid line patterns and recovers as designed | [ ] |
| Complete route | Five runs on one unchanged layout are recorded without reset or uncontrolled motion | [ ] |
| Emergency stop | App Stop, IR `0`, and physical power-off paths have all been checked | [ ] |

PWM 50–100 are recorded as unable to start reliably. The app joystick limit is 110–200 and defaults to 150; it affects manual and voice directions only. Production line mode ignores that limit. Pulse uses PWM 120 with 80/80 ms timing. Normal keeps that centered pulse and uses continuous PWM 150 only for side correction or counter-rotation. Repeat-accept Normal on the fixed course and do not tune parameters on demo day.

## Recording procedure

### Ten minutes before recording

1. Place the car at the start with both power switches off. Inspect the cells, tires, servo retaining screw, Bluetooth orientation, and connectors.
2. Secure the route and obstacle positions. Run one unrecorded rehearsal under the same lighting.
3. Disable phone battery restrictions and interruptions, keep the screen awake, and verify Bluetooth, nearby-device, and microphone permissions.
4. Select one UI language before connecting. Changing language while connected intentionally stops and disconnects the car.
5. Power on, identify the target by toggling only the car's Bluetooth power, and connect to it. Confirm a blue connection indicator, zero requested PWM, and plausible distance and line values.
6. Select an accepted manual limit; the app defaults to 150 and allows 110–200. Line speed is not controlled by this slider: centered travel uses the vehicle-side PWM 120 pulse and Normal turns use 150.
7. Press the fixed Stop button once. One teammate should remain close to the physical switches without reaching into the motion area.

### Roles

| Role | Responsibility |
| --- | --- |
| Presenter | Explains the objective, improvements, evidence, and limitations |
| Operator | Manages the app, voice commands, obstacle, and stop action |
| Recorder | Captures one continuous video, times the demo, and records five-run results; the presenter can cover this in a two-person team |

Only one person operates the car. If anyone calls “Stop,” use App Stop first, then IR `0`, then physical power if needed.

## Recorded-demo script

Use the [side-by-side bilingual script](demo-script-bilingual.md). It gives the timing, camera action, short Chinese text, and matching English text. It also introduces our Android app, native Java, the Android SDK, BLE GATT, system speech recognition, and the on-screen indicators.

## Extending to five minutes

If the instructor explicitly allows about five minutes, add two short sections after the core demo:

1. **Architecture, about 45 seconds:** show the signal path from sensors to the Arduino state machine, actuators, BLE serial bridge, Android app, and telemetry log.
2. **Validation, about 45 seconds:** show the five-run table, offline test results, and one real limitation. A good example is the unreliable contrast on wood flooring and why a matte white reference surface is an engineering control rather than a software workaround.

Do not fill time by uploading firmware, exercising every direction, or switching languages during the live run. Leave time for questions.

## Short answers to likely questions

**What did you change from the stock car?**
We retained the hardware and integrated line following, obstacle handling, fail-safe stops, bilingual phone and voice control, telemetry, and reproducible tests under one protocol and state machine. We also calibrated motor polarity, servo center, and the reliable PWM range for this chassis.

**Why does it stop instead of driving around the obstacle?**
The car has one forward range sensor and no reliable side or rear map. Stop, warn, and resume after verified clearance is consistent with the available sensing; a blind detour is not.

**Why use a white background?**
The three digital reflectance channels only expose thresholded black/white states. Wood grain and black tape can collapse to the same digital value. Software cannot recover optical contrast that was never measured.

**Can a voice error leave the car moving?**
No. Unknown phrases do not send movement, stop takes precedence, direction commands expire after about one second, line following requires a live lease, and the vehicle stops on lost communication.

**Is the dashboard reporting wheel speed?**
No. It reports requested PWM. The current car has no wheel encoders, so the report does not claim closed-loop speed measurement.

**Why can the app select PWM 50?**
It is retained as a manual experimental range. Hardware testing already found that 50–100 could not start reliably, so centered line travel uses fixed PWM 120. Pulse uses 80/80 ms output while Normal uses continuous PWM 150 only during side correction or counter-rotation. Protocol acceptance does not prove motor motion.

## Recovery plan

| Symptom | Immediate action | Explanation |
| --- | --- | --- |
| Voice not recognized | Press Stop, then continue with the on-screen control or IR remote | No valid vocabulary match means no movement command is sent |
| Bluetooth disconnects | Stop, use IR `0`, reconnect, and verify zero outputs | The vehicle stops when the communication lease expires |
| Car refuses to start | Do not spam ARM; inspect range, line, battery, and state | Start is rejected when a safety gate is not valid |
| One or both sides stall at a low manual setting | Stop and use the accepted manual limit; do not treat the joystick limit as line speed | Startup threshold depends on battery, motor, and load variation |
| Line is lost | Stop, return to the start, and inspect surface, tape, and lighting | Digital line sensing requires stable optical contrast |
| No resume after obstacle | Keep stopped; verify more than 30 cm clearance, a valid line, and stable echo | Recovery uses distance hysteresis and a 600 ms hold |
| Any uncontrolled behavior | App Stop -> IR `0` -> both physical switches off | Do not reach for moving wheels |

A failed live run should not be hidden. A safe refusal or stop is itself evidence of a guard. Briefly identify the gate, reset safely, and use the saved continuous successful run as supporting evidence.

## Evidence package

Save the following under the Git-ignored `artifacts/local/` directory and cite only selected results in the report:

1. one uninterrupted wide video showing the route, car, obstacle, and operator;
2. one phone close-up or screen recording showing connection, selected speed, range, line state, and requested PWM;
3. a five-run table with date, firmware commit, app APK hash, manual speed, line-pulse settings, starting and ending battery, result, failure location, and resets;
4. one overhead photograph of the final route and one photograph of the obstacle position;
5. all relevant failure clips and logs, not only successful samples.

Suggested run sheet:

| Run | Manual PWM | Line pulse | Start voltage | Line follow | Stop/beep | Resume | Voice stop | Fault/notes |
| --- | ---: | --- | ---: | --- | --- | --- | --- | --- |
| 1 |  | Profile: ____, straight/turn PWM 120/150 |  |  |  |  |  |  |
| 2 |  | Profile: ____, straight/turn PWM 120/150 |  |  |  |  |  |  |
| 3 |  | Profile: ____, straight/turn PWM 120/150 |  |  |  |  |  |  |
| 4 |  | Profile: ____, straight/turn PWM 120/150 |  |  |  |  |  |  |
| 5 |  | Profile: ____, straight/turn PWM 120/150 |  |  |  |  |  |  |

## One-page cue card

```text
BEFORE: route fixed -> batteries checked -> language selected -> power on
CONNECT: power-toggle-identified car BLE -> blue status -> valid telemetry -> PWM 0/0 -> STOP
DEMO: “forward” -> “stop” -> align on line -> “follow line”
OBSTACLE: <=20 cm stop + beep -> remove beyond 30 cm -> wait -> resume
FINISH: “stop” -> confirm PWM 0/0 -> power off
EMERGENCY: App STOP -> IR 0 -> both physical switches OFF
```
