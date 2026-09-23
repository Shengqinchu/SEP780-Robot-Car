# Serial control protocol v1

[README](../README.en.md) · [Calibration](calibration.en.md)

`robot_car` uses 115200 baud, 8N1, ASCII, and newline-delimited commands. The separate `usb_check` sketch has a different protocol; `Robot.ps1` will not arm it.

## Commands and acknowledgements

```text
S 101 STATUS
S 102 STOP
S 103 SPEED 100
S 104 LINE PULSE
S 105 ARM LINE
S 106 PING
S 107 STOP
S 108 LINE CONTINUOUS
S 109 ARM LINE
S 110 STOP
S 111 LINE HYBRID
S 112 ARM LINE
S 113 STOP
S 114 SPEED 120
S 115 ARM MANUAL
S 116 DRIVE 120 120
S 117 STOP
S 118 R 200 -200
S 119 R 0 0
S 120 H 1
S 121 H 0
```

These are wire-format examples, not a script to send unattended. Use the bounded host API and the physical setup sequence in the calibration guide.

| Command | Meaning |
| --- | --- |
| `STATUS` | Emit current telemetry; does not extend a lease |
| `STOP` | Set wheel output to zero and clear the active mode; any source may stop |
| `SPEED pwm` | While idle, set the legacy manual/IR cruise preference to 50..200 in steps of 10; it does not change the fixed line pulse or Android joystick limit |
| `LINE PULSE` | While idle and owned by serial/BLE, select PWM 120 with 80 ms drive / 80 ms coast for the next line run |
| `LINE CONTINUOUS` | Diagnostic profile: while idle, select continuous PWM 120 for every valid line pattern; not exposed by the final app |
| `LINE HYBRID` | App Normal profile: pulse at PWM 120 on `010`, continuously correct at PWM 150 on `110/011`, and counter-rotate at `±150` on `100/001`; stop interlocks are unchanged |
| `ARM LINE` | Enter line-follow standby from idle after base sensor and battery validation |
| `ARM MANUAL` | Enable manual commands from idle; initial wheel output remains zero |
| `DRIVE left right` | Legacy signed PWM after `ARM MANUAL`; renews the manual and serial leases |
| `R left right` | Atomic Android remote command: take serial manual control if needed, then apply signed wheel PWM; `R 0 0` stops motion idempotently |
| `H 1` / `H 0` | Start/renew or stop the manual horn; the on request expires after 1.5 seconds without renewal |
| `PING` | Renew the serial-owner lease only; cannot sustain an old manual movement |

Sequences are integers in 1..65535. Replies are `ACK 101` or `ERR 101`. An invalid frame produces `ERR 0 FRAME` and stops the controller. ARM is rejected while already armed or on invalid base inputs. Line mode may arm while blocked or off-line, but requests zero until a valid line and clearance are present. `SPEED` and all `LINE` profile commands are rejected while armed or from the infrared source; `SPEED` enforces 50..200 in 10-point steps. The Android app sends STOP, `LINE PULSE` or `LINE HYBRID`, and then `ARM LINE`. All line profiles share the same sensor, obstacle, low-voltage, lease, and STOP interlocks. Pulse uses PWM 120; Hybrid also uses 120 while centered but raises only continuous side corrections and counter-rotation to 150. Infrared button `1` always restores Pulse. Values below the measured motor-start threshold may be accepted without producing motion. Rejected valid commands do not steal an existing control owner. Out-of-range manual PWM stops its owner.

Manual PWM in the wire protocol is restricted to -200..200. The Android UI offers a selectable 110..180 limit with a default value of 150 because this chassis could not reliably start at 50..100, and the motor I/O clips physical writes to 180. `R` removes the old STOP/SPEED/ARM/DRIVE timing race: a nonzero frame performs takeover and update atomically, while zero always succeeds as a motion stop. At a front obstacle, net forward manual requests produce zero output without dropping the manual session; reverse and counter-rotation remain available for escape. Low voltage, stale/invalid sensors, communication leases, malformed input, and STOP still latch zero output. The worst-case compact frame `S 65535 R -200 -200\n` is exactly 20 bytes.

The active buzzer shares A0 with battery sensing. `H 1` therefore uses a 120 ms on / 30 ms quiet pattern so the ADC can still sample. The controller requires renewal within 1.5 seconds, and `STOP` silences it. It is an active buzzer with on/off control, so rhythmic alerts are supported but pitched melodies are not.

A complete command must arrive within 200 ms and fit in a 63-byte payload. Overlong, non-ASCII, or expired partial commands are discarded through the next newline. LF and CRLF are accepted; commands are case-sensitive. Sequence numbers correlate replies, not authentication or exactly-once delivery; the host does not automatically retry movement commands.

## Telemetry

```text
SEP780 ROBOT READY v=1
SEP780 v=1 ms=1200 mode=1 state=2 owner=0 line=2 mm=800 mv=7400 l=120 r=120
```

| Field | Meaning |
| --- | --- |
| `ms` | Unsigned 32-bit uptime; normal wrap is supported |
| `mode` | 0 idle, 1 line, 2 manual |
| `state` | State index below |
| `owner` | 0 serial, 1 infrared; when idle this is the previous/default owner |
| `line` | Three black-detection bits, left in bit 2, center in bit 1, right in bit 0 |
| `mm` | Forward distance in millimeters; 0 means no valid echo |
| `mv` | Estimated battery millivolts from A0 |
| `l` / `r` | Requested signed wheel PWM after controller limits/trim, not measured wheel speed |

State indices: 0 idle, 1 ready, 2 following, 3 manual, 4 obstacle, 5 clear_wait, 6 line_lost, 7 ambiguous_line, 8 sensor_fault, 9 low_battery, 10 remote_timeout, 11 command_error, 12 stopped, 13 bad_config. A state such as line_lost may briefly remain armed; use `mode` to distinguish a temporary pause from a latched stop.

## Host API

`host/robot_tool.py` provides `run_session(action, port, ...)` for `observe`, `line`, `drive`, and `stop`. Importing it never opens a port. Physical sessions require `confirmed=True`; line/drive also require `motion_clear=True`. `scripts/Robot.ps1` exposes these as explicit switches.

Observe is receive-only. Before writing, the host requires valid v1 telemetry, then uses a fresh sequence and waits for the matching acknowledgement. Motion sessions STOP first, ARM once, refresh PING every 250 ms or DRIVE every 100 ms, and STOP on normal completion or error. It does not re-arm after faults or retry a lost movement acknowledgement.

The active interval is 1..30 seconds. Discovery is separately bounded to 3 seconds, each command acknowledgement to 300 ms, and final STOP acknowledgement to 400 ms; the serial write timeout is 500 ms. Reads have a 65536-byte budget and a 128-byte line limit. A reset, oversized frame, failed write, rejection, or missing acknowledgement fails the session. Physical stop is not inferred from an ACK; `stop_acknowledged` records only the firmware reply.

Upload and host sessions share the repository port lock. Only one process should own a port, and external IDE monitors must be closed. Raw RX/TX, parsed telemetry, and the final summary are saved under `artifacts/local/`. Convert telemetry JSONL to CSV with `host/export_telemetry.py`.
