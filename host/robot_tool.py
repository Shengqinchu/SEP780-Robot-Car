"""Bounded project-firmware sessions. No upload and no port access on import."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import secrets
import time
from uuid import uuid4

from robot_protocol import encode, parse_telemetry
from serial_tool import LineFramer, PortLock, SafetyError, LOCK_ROOT, RECORD_ROOT, canonical_port, open_usb


class SessionError(RuntimeError):
    pass


class RobotLink:
    def __init__(self, connection, emit, clock=time.monotonic, pause=time.sleep, sequence=None):
        self.connection, self.emit, self.clock, self.pause = connection, emit, clock, pause
        self.sequence = sequence if sequence is not None else secrets.randbelow(60000) + 1
        self.framer = LineFramer()
        self.last = None
        self.received = 0
        self.telemetry_count = 0
        self.identified = False
        self.last_uptime = None

    def receive(self):
        chunk = self.connection.read(256)
        if not chunk:
            self.pause(0.005)
            return []
        self.received += len(chunk)
        self.emit({"event": "rx", "hex": chunk.hex()})
        if self.received > 65536:
            raise SessionError("Receive byte budget exceeded.")
        lines = self.framer.feed(chunk)
        if self.framer.dropped_lines:
            raise SessionError("Oversized telemetry frame.")
        for line in lines:
            sample = parse_telemetry(line)
            if sample:
                if self.last_uptime is not None and ((sample["ms"] - self.last_uptime) & 0xFFFFFFFF) >= 0x80000000:
                    raise SessionError("Controller reset or out-of-order telemetry detected.")
                self.last_uptime = sample["ms"]
                self.last = sample
                self.identified = True
                self.telemetry_count += 1
                self.emit({"event": "telemetry", **sample})
            elif line == b"SEP780 ROBOT READY v=1" and self.identified:
                raise SessionError("Controller restarted during the session.")
        return lines

    def identify(self):
        deadline = self.clock() + 3
        while self.clock() < deadline:
            self.receive()
            if self.identified:
                return
        raise SessionError("No project-firmware v1 telemetry. No command sent.")

    def wait_motion_ready(self, timeout=3.0):
        """Wait out a serial-open reset without sending an ARM command."""
        if not self.identified:
            raise SessionError("Firmware identity is required before readiness checks.")
        started = self.clock()
        deadline = started + timeout
        while self.clock() < deadline:
            if self.last is not None and 20 <= self.last["range_mm"] <= 4000:
                self.emit({"event": "motion_ready", "waited_ms": round((self.clock() - started) * 1000),
                           "range_mm": self.last["range_mm"]})
                return
            self.receive()
        raise SessionError("No valid ultrasonic range after controller startup; no ARM sent.")

    def request(self, action, left=0, right=0, timeout=0.30):
        if not self.identified:
            raise SessionError("Firmware identity is required before writing.")
        seq = self.sequence
        self.sequence = seq % 65535 + 1
        payload = encode(seq, action, left, right)
        if self.connection.write(payload) != len(payload):
            raise SessionError("Incomplete serial write.")
        self.emit({"event": "tx", "hex": payload.hex(), "action": action, "sequence": seq})
        deadline = self.clock() + timeout
        while self.clock() < deadline:
            for line in self.receive():
                if line == f"ACK {seq}".encode("ascii"):
                    return
                if line == f"ERR {seq}".encode("ascii") or line.startswith(b"ERR 0 "):
                    raise SessionError(f"Controller rejected {action}; inspect telemetry.")
        raise SessionError(f"No acknowledgement for {action}; no automatic retry.")


def validate(action, port, confirmed, motion_clear, seconds, left, right):
    if action not in {"observe", "line", "drive", "stop"}:
        raise SafetyError("Unknown robot action.")
    canonical_port(port)
    if not confirmed:
        raise SafetyError("Confirm actual board, power and free servo travel before opening a robot session.")
    if action in {"line", "drive"} and not motion_clear:
        raise SafetyError("Movement requires explicit clear-area confirmation.")
    if type(seconds) not in (int, float) or not math.isfinite(seconds) or not 1 <= seconds <= 30:
        raise SafetyError("Session duration must be 1..30 seconds.")
    encode(1, "drive", left, right)
    if action != "drive" and (left or right):
        raise SafetyError("Wheel PWM is only accepted for drive.")


def run_session(action, port, confirmed=False, motion_clear=False, seconds=5, left=0, right=0,
                emit=lambda event: None, lock_root=LOCK_ROOT, opener=open_usb, clock=time.monotonic, pause=time.sleep):
    validate(action, port, confirmed, motion_clear, seconds, left, right)
    port = canonical_port(port)
    result = dict(action=action, status="failed", stop_acknowledged=False,
                  scope="Serial commands and telemetry; not independent physical motion verification")
    with PortLock(port, Path(lock_root)):
        connection = opener(port)
        link = RobotLink(connection, emit, clock, pause)
        movement_requested = False
        try:
            emit({"event": "open", "port": port, "baudrate": 115200})
            link.identify()
            if action == "stop":
                link.request("stop")
                result["stop_acknowledged"] = True
            else:
                if action in {"line", "drive"}:
                    # Mark before ARM: a lost acknowledgement must still lead to STOP.
                    movement_requested = True
                    link.request("stop")
                    # Opening an Uno serial port can reset the MCU. Its first telemetry frame
                    # arrives before the servo settles and before the first valid sonar echo.
                    link.wait_motion_ready()
                    link.request("line" if action == "line" else "manual")
                end = clock() + seconds
                refresh = clock()
                while clock() < end:
                    if action in {"line", "drive"} and clock() >= refresh:
                        sent_at = clock()
                        link.request("ping" if action == "line" else "drive", left, right)
                        refresh = sent_at + (0.25 if action == "line" else 0.10)
                    else:
                        link.receive()
            result["status"] = "completed"
        except (Exception, KeyboardInterrupt) as exc:
            result["error"] = f"{type(exc).__name__}: {exc}"
        finally:
            if movement_requested:
                try:
                    link.request("stop", timeout=0.4)
                    result["stop_acknowledged"] = True
                except (Exception, KeyboardInterrupt) as exc:
                    result["status"] = "failed"
                    result["stop_error"] = f"{type(exc).__name__}: {exc}"
            connection.close()
            emit({"event": "close", "port": port})
            result.update(received_bytes=link.received, telemetry_count=link.telemetry_count, last_telemetry=link.last)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("observe", "line", "drive", "stop"))
    parser.add_argument("--port", required=True)
    parser.add_argument("--seconds", type=float, default=5)
    parser.add_argument("--left", type=int, default=0)
    parser.add_argument("--right", type=int, default=0)
    parser.add_argument("--confirm-hardware-ready", action="store_true")
    parser.add_argument("--confirm-motion-clear", action="store_true")
    args = parser.parse_args()
    validate(args.action, args.port, args.confirm_hardware_ready, args.confirm_motion_clear, args.seconds, args.left, args.right)
    RECORD_ROOT.mkdir(parents=True, exist_ok=True)
    name = "robot-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid4().hex[:8]
    start = time.monotonic()
    with (RECORD_ROOT / (name + ".jsonl")).open("w", encoding="utf-8") as trace:
        def emit(event):
            trace.write(json.dumps({"elapsed_ms": round((time.monotonic() - start) * 1000), **event}) + "\n")
            trace.flush()
        result = run_session(args.action, args.port, args.confirm_hardware_ready, args.confirm_motion_clear,
                             args.seconds, args.left, args.right, emit=emit)
    result["recorded_at_utc"] = datetime.now(timezone.utc).isoformat()
    result["trace"] = "artifacts/local/" + name + ".jsonl"
    (RECORD_ROOT / (name + ".json")).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "completed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
