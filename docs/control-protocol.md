# Serial control protocol v1

[README](../README.en.md) · [Calibration](calibration.en.md)

`robot_car` uses 115200 baud, 8N1, ASCII, and newline-delimited commands. The separate `usb_check` sketch has a different protocol; `Robot.ps1` will not arm it.

## Commands and acknowledgements

```text
S 101 STATUS
S 102 STOP
S 103 ARM LINE
S 104 PING
S 105 STOP
S 106 ARM MANUAL
S 107 DRIVE 80 80
S 108 STOP
```

These are wire-format examples, not a script to send unattended. Use the bounded host API and the physical setup sequence in the calibration guide.

| Command | Meaning |
| --- | --- |
| `STATUS` | Emit current telemetry; does not extend a lease |
| `STOP` | Set wheel output to zero and clear the active mode; any source may stop |
| `ARM LINE` | Start line following from idle with valid readings and clearance |
| `ARM MANUAL` | Enable manual commands from idle; initial wheel output remains zero |
| `DRIVE left right` | Signed PWM; renews the manual and serial leases |
| `PING` | Renew the serial-owner lease only; cannot sustain an old manual movement |

Sequences are integers in 1..65535. Replies are `ACK 101` or `ERR 101`. An invalid frame produces `ERR 0 FRAME` and stops the controller. ARM is rejected while already armed, on invalid inputs, or without sufficient clearance. Rejected valid commands do not steal an existing control owner. Out-of-range manual PWM stops its owner.

Host PWM is restricted to -150..150. The parser accepts -180..180, then the controller enforces its configured maximum. A complete command must arrive within 200 ms and fit in a 63-byte payload. Overlong, non-ASCII, or expired partial commands are discarded through the next newline. LF and CRLF are accepted; commands are case-sensitive. Sequence numbers correlate replies, not authentication or exactly-once delivery; the host does not automatically retry movement commands.

## Telemetry

```text
SEP780 ROBOT READY v=1
SEP780 v=1 ms=1200 mode=1 state=2 owner=0 line=2 mm=800 mv=7400 l=90 r=90
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
