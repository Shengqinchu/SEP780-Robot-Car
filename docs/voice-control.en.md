# Android voice and Bluetooth control

[中文](voice-control.md) · [README](../README.en.md) · [Serial protocol](control-protocol.md)

## Scope and safety boundary

The Android app uses the kit's BT05/JDY-style BLE serial module to translate a finite voice vocabulary into the existing `S <seq> ...` protocol. It does not replace the vehicle state machine. Ultrasonic stopping, low-voltage protection, sensor faults, command leases, and maximum PWM remain enforced by `robot_car`.

The app starts with a PWM 150 remote limit. Its slider exposes ten levels from 110 to 200 in steps of 10. The lower bound follows the measured result that PWM 50–100 could not start this chassis reliably; firmware enforces the upper bound. The large analog stick maps vertical travel to throttle and horizontal travel to steering, then applies dead zones, response curves, and differential mixing. Nonzero dominant output launches at PWM 110, ramps upward, and passes through neutral before reversal. This limit affects joystick and voice directions only. Line following retains its separate PWM 120 centered pulse and PWM 150 turns.

- A stop hypothesis outranks every movement hypothesis in the same recognition result.
- Forward, reverse, left, and right voice actions last for one second and use the same atomic `R` command and 20 Hz scheduler as the joystick before returning to zero.
- Line mode sends STOP, the selected line profile, and then ARM LINE. The app sends `PING` every 500 ms; backgrounding, disconnecting, or closing the app ends renewal and sends `STOP`.
- Unknown phrases send no movement. A joystick release or touch cancellation sends priority `R 0 0`.
- The app produces controls at 20 Hz, and the BLE queue retains only the latest unsent joystick sample. Changing the remote limit stops first; line mode never receives the remote limit.
- Hold Horn renews a leased buzzer request and release sends off. A lost phone cannot leave it sounding for more than 1.5 seconds. This active buzzer supports on/off rhythms, not reliable pitched melodies.
- The app does not store recordings. The system recognition service may send audio to its provider. The BLE serial link has no project-level authentication and is intended only for a controlled, short-range course.

The finite vocabulary covers stop, follow line, forward, backward, left, and right in Chinese and English. Open-ended questions, continuous conversation, and arbitrary natural language are outside the first release.

## Build

On first use on x64 Windows:

```powershell
./scripts/Setup-Android.ps1
./scripts/Build-Android.ps1
```

Versions are pinned in `android-toolchain.lock.json`. The debug APK is written to the Git-ignored `artifacts/local/SEP780-Robot-Car-debug.apk`; it is not committed. Enable USB debugging and confirm the target phone before installation:

```powershell
./scripts/Install-Android.ps1 -ConfirmDeviceReady
```

The minimum OS is Android 8.0 (API 26). The Chinese / English selector persists the choice and selects the matching speech-recognition locale. Every primary control stays on one page: Bluetooth and the battery/range/line dashboard, Pulse / Normal, the remote-limit slider, a large analog joystick with live wheel outputs, Voice, hold-to-sound Horn, Line, and the fixed emergency Stop. Android 12 and newer request Nearby devices; older scans request location. The microphone permission is requested separately on the first voice action. An iOS client is not part of this release.

## First acceptance run

1. Power the car off, remove USB, and insert the Bluetooth module in the marked orientation. Never hot-plug or reverse it.
2. Lift all wheels and clear the vehicle before power-on. Tap Scan, toggle only this car's Bluetooth power, and identify the device that appears or disappears instead of relying on a fixed public device name.
3. Wait for telemetry and tap Stop. Keep the remote limit at 150, lift all wheels, and briefly check forward, reverse, differential turns, and counter-rotation. Release must return both outputs to zero. Briefly hold Horn and confirm it stops on release.
4. After the lifted checks pass, briefly test Normal on the white-background course: centered travel must pulse, side deviation must hold correction, and a single-side pattern must counter-rotate. Run the full curve only after direction is confirmed. The joystick limit does not change line mode; it remains available for reverse, left, right, and other manual/voice actions.
5. Say the equivalent of “follow line,” verify tracking, then say “stop.” Add a flat obstacle within 20 cm and verify vehicle-side stopping and the alert. Move it beyond 30 cm while retaining a valid line and verify recovery. The app sends intent only and cannot bypass vehicle-side safety gates.

Freenove requires the Bluetooth module to be removed during Arduino uploads; use the [calibration guide](calibration.en.md) for every firmware update. The worst-case compact `R` frame is exactly 20 bytes and needs no BLE split. Other long frames are chunked, while every complete frame remains subject to the 63-byte and 200 ms firmware limits.

## Evidence status

| Item | Status |
| --- | --- |
| Analog joystick, ten remote limits, atomic protocol, latest-value BLE queue, acceleration ramp, and horn lease | Implemented and offline-tested |
| Java unit tests, lint, and debug APK | 16/16 unit tests and lint pass; APK SHA-256 is `4f74015a72a8a77ef0558a355461363c8c431ef41e9e63c0614c2fee21861c7a` |
| Installed on an Android phone | This analog-joystick/horn APK is installed over the previous Redmi app; both language layouts launch without a crash |
| Production firmware | This revision's `R` / `H` / PWM 200 firmware is flashed to COM5; USB-only observation reports `idle / 0 / 0` |
| Connected to this car's BLE module with ACK/telemetry | Passed; the target was isolated by toggling only the car's Bluetooth power, while the public documentation omits its name and hardware address |
| Phone remote and line profile | A powered integration session is complete and the user reports overall usable behavior; an occasional ignored input with `command rejected` remains without a failure-time ACK/telemetry trace |
| System speech recognition, bilingual vocabulary, and safe scheduling | Integrated; vocabulary and stop-precedence unit tests pass, and microphone permission is requested on first use |
| Manual horn, voice direction, and remote obstacle interlock | The user reports the combined feature set as usable; no per-item repeat count or failure trace exists, so it is not described as 100% stable |

The powered result and intermittent rejection are recorded in `DEVLOG.md`. Run one complete rehearsal on the fixed course before recording; if the rejection recurs, retain the app state, ACK, and telemetry instead of diagnosing it from memory.
