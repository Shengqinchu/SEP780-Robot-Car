"""Bounded USB bring-up operations. Importing this module never opens a port."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sys
import time
from datetime import datetime, timezone
from uuid import uuid4

import serial
from serial.tools import list_ports


PROJECT_ROOT = Path(__file__).resolve().parents[1]
LOCK_ROOT = PROJECT_ROOT / ".local" / "port-locks"
RECORD_ROOT = PROJECT_ROOT / "artifacts" / "local"
READY = b"SEP780 USB CHECK READY"
ACK = b"OK board=arduino:avr:uno mode=USB_CHECK actuators=UNCONTROLLED"
HEARTBEAT = re.compile(rb"HEARTBEAT ms=([0-9]{1,10})")


class SafetyError(ValueError):
    pass


class PortBusyError(RuntimeError):
    pass


def canonical_port(port: str) -> str:
    if re.fullmatch(r"COM[1-9][0-9]{0,3}", port, re.IGNORECASE):
        return port.upper()
    if re.fullmatch(r"/dev/tty(?:ACM|USB)[0-9]+", port):
        return port
    raise SafetyError("Specify a local COMn or /dev/ttyACMn/ttyUSBn port; URLs are not allowed.")


def port_lock_name(port: str) -> str:
    digest = hashlib.sha256(canonical_port(port).encode("utf-8")).hexdigest()[:16]
    return f"port-{digest}.lock"


class PortLock:
    """Shared with Common.ps1. A crash leaves a lock for manual inspection."""

    def __init__(self, port: str, directory: Path = LOCK_ROOT):
        self.port = canonical_port(port)
        self.path = directory / port_lock_name(self.port)
        self.token = uuid4().hex

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        try:
            handle = self.path.open("x", encoding="utf-8")
        except FileExistsError as exc:
            raise PortBusyError("Project port lock exists. Close the owner or inspect a stale lock; no port opened.") from exc
        with handle:
            json.dump({"token": self.token, "pid": os.getpid(), "port": self.port}, handle)
        return self

    def __exit__(self, *_):
        try:
            owner = json.loads(self.path.read_text(encoding="utf-8-sig"))
            if owner.get("token") == self.token:
                self.path.unlink()
        except (FileNotFoundError, ValueError):
            pass


class LineFramer:
    def __init__(self, max_line: int = 128):
        self.max_line = max_line
        self.buffer = bytearray()
        self.discarding = False
        self.dropped_lines = 0

    def feed(self, data: bytes) -> list[bytes]:
        lines = []
        for value in data:
            if value == 10:
                if not self.discarding:
                    lines.append(bytes(self.buffer).removesuffix(b"\r"))
                self.buffer.clear()
                self.discarding = False
            elif not self.discarding:
                if len(self.buffer) == self.max_line:
                    self.buffer.clear()
                    self.discarding = True
                    self.dropped_lines += 1
                else:
                    self.buffer.append(value)
        return lines


class UsbEvidence:
    def __init__(self):
        self.ready_seen = False
        self.query_sent = False
        self.query_ack = False
        self.heartbeat_count = 0
        self.last_uptime = None
        self.reset_during_check = False

    def observe(self, line: bytes):
        if line == READY:
            self.ready_seen = True
            if self.query_sent:
                self.reset_during_check = True
        elif line == ACK:
            if self.query_sent:
                self.query_ack = True
        elif match := HEARTBEAT.fullmatch(line):
            uptime = int(match[1])
            if uptime > 0xFFFFFFFF:
                return
            if self.last_uptime is not None:
                delta = (uptime - self.last_uptime) & 0xFFFFFFFF
                if delta == 0:
                    return
                if delta >= 0x80000000:
                    self.reset_during_check = True
                    return
            self.last_uptime = uptime
            self.heartbeat_count += 1

    @property
    def passed(self) -> bool:
        return self.query_sent and self.query_ack and self.heartbeat_count >= 2 and not self.reset_during_check

    def summary(self) -> dict:
        return {
            "ready_seen": self.ready_seen,
            "query_sent": self.query_sent,
            "query_ack": self.query_ack,
            "heartbeat_count": self.heartbeat_count,
            "last_uptime_ms": self.last_uptime,
            "reset_during_check": self.reset_during_check,
        }


def validate_session(action: str, port: str, confirmed: bool, seconds: float, max_bytes: int):
    if action not in {"capture", "usb-check"}:
        raise SafetyError("Unsupported serial action.")
    if not confirmed:
        raise SafetyError("USB isolation confirmation is required before opening a port; opening may reset the MCU.")
    canonical_port(port)
    if not math.isfinite(seconds) or not 1 <= seconds <= 60:
        raise SafetyError("Duration must be finite and between 1 and 60 seconds.")
    if not isinstance(max_bytes, int) or isinstance(max_bytes, bool) or not 128 <= max_bytes <= 65536:
        raise SafetyError("Byte limit must be an integer between 128 and 65536.")


def open_usb(port: str):
    connection = serial.Serial(port=None, baudrate=115200, timeout=0.05, write_timeout=0.5)
    try:
        # Apply the requested inactive lines before open. OS/driver glitches can still reset Uno.
        connection.dtr = False
        connection.rts = False
        if os.name != "nt":
            connection.exclusive = True
        connection.port = port
        connection.open()
        return connection
    except BaseException:
        connection.close()
        raise


def collect(connection, action: str, seconds: float, max_bytes: int, emit, clock=time.monotonic, pause=time.sleep):
    start = clock()
    deadline = start + seconds
    framer = LineFramer()
    evidence = UsbEvidence()
    received = 0
    status = "timeout" if action == "usb-check" else "captured"
    while clock() < deadline:
        chunk = connection.read(min(256, max_bytes - received))
        if chunk:
            received += len(chunk)
            emit({"event": "rx", "elapsed_ms": round((clock() - start) * 1000), "hex": chunk.hex()})
            for line in framer.feed(chunk):
                evidence.observe(line)
        if evidence.reset_during_check and action == "usb-check":
            status = "reset_detected"
            break
        if evidence.passed and action == "usb-check":
            status = "passed"
            break
        if received >= max_bytes:
            status = "byte_limit"
            break
        # Never send even '?' until this firmware's banner or heartbeat has been observed.
        if (action == "usb-check" and not evidence.query_sent and clock() - start >= 1.0
                and (evidence.ready_seen or evidence.heartbeat_count > 0) and clock() < deadline):
            if connection.write(b"?") != 1:
                raise serial.SerialTimeoutException("The query byte was not fully written.")
            evidence.query_sent = True
            emit({"event": "tx", "elapsed_ms": round((clock() - start) * 1000), "hex": "3f"})
        if not chunk:
            pause(0.005)
    return {
        "action": action,
        "status": status,
        "elapsed_ms": round((clock() - start) * 1000),
        "received_bytes": received,
        "dropped_lines": framer.dropped_lines,
        "partial_line_bytes": len(framer.buffer),
        "usb_evidence": evidence.summary(),
    }


def run_session(action: str, port: str, confirmed: bool, seconds=8.0, max_bytes=8192,
                emit=lambda event: None, lock_root=LOCK_ROOT, opener=open_usb,
                clock=time.monotonic, pause=time.sleep) -> dict:
    validate_session(action, port, confirmed, seconds, max_bytes)
    port = canonical_port(port)
    with PortLock(port, Path(lock_root)):
        connection = opener(port)
        try:
            emit({"event": "open", "port": port, "baudrate": 115200})
            result = collect(connection, action, seconds, max_bytes, emit, clock, pause)
            result["port"] = port
            result["scope"] = "USB serial check only; not actuator/sensor/board-identity validation"
            return result
        finally:
            connection.close()
            emit({"event": "close", "port": port})


def loopback_test() -> dict:
    payload = b"SEP780 SOFTWARE LOOPBACK\n"
    with serial.serial_for_url("loop://", timeout=0.5, write_timeout=0.5) as connection:
        written = connection.write(payload)
        received = connection.read(len(payload))
    return {"action": "self-test", "status": "passed" if written == len(payload) and received == payload else "failed",
            "scope": "pySerial in-memory loopback only; no physical port opened"}


def inventory() -> dict:
    return {"action": "list", "scope": "OS enumeration only; no serial port opened", "ports": [
        {"port": p.device, "description": p.description, "vid": p.vid, "pid": p.pid}
        for p in sorted(list_ports.comports(), key=lambda p: p.device)
    ]}


def parser() -> argparse.ArgumentParser:
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(dest="action", required=True)
    commands.add_parser("list")
    commands.add_parser("self-test")
    for action in ("capture", "usb-check"):
        command = commands.add_parser(action)
        command.add_argument("--port", required=True)
        command.add_argument("--confirm-usb-isolated", action="store_true")
        command.add_argument("--seconds", type=float, default=8.0)
        command.add_argument("--max-bytes", type=int, default=8192)
    return cli


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    try:
        if serial.VERSION != "3.5":
            raise SafetyError("pySerial version must match host/requirements.lock (3.5).")
        if args.action == "list":
            result = inventory()
        elif args.action == "self-test":
            result = loopback_test()
        else:
            validate_session(args.action, args.port, args.confirm_usb_isolated, args.seconds, args.max_bytes)
            RECORD_ROOT.mkdir(parents=True, exist_ok=True)
            name = datetime.now(timezone.utc).strftime("serial-%Y%m%dT%H%M%SZ-") + uuid4().hex[:8]
            trace_path = RECORD_ROOT / (name + ".jsonl")
            summary_path = RECORD_ROOT / (name + ".json")
            with trace_path.open("x", encoding="utf-8") as trace:
                def emit(event):
                    trace.write(json.dumps(event, ensure_ascii=True) + "\n")
                    trace.flush()
                try:
                    result = run_session(args.action, args.port, args.confirm_usb_isolated,
                                         args.seconds, args.max_bytes, emit)
                except (SafetyError, PortBusyError, serial.SerialException, OSError) as exc:
                    emit({"event": "error", "type": type(exc).__name__, "message": str(exc)})
                    result = {"action": args.action, "status": "error", "error": type(exc).__name__, "message": str(exc)}
                except KeyboardInterrupt:
                    emit({"event": "interrupted"})
                    result = {"action": args.action, "status": "interrupted"}
            result["recorded_at_utc"] = datetime.now(timezone.utc).isoformat()
            result["trace"] = trace_path.relative_to(PROJECT_ROOT).as_posix()
            result["summary"] = summary_path.relative_to(PROJECT_ROOT).as_posix()
            with summary_path.open("x", encoding="utf-8") as summary:
                json.dump(result, summary, indent=2)
    except (SafetyError, PortBusyError, serial.SerialException, OSError) as exc:
        result = {"action": args.action, "status": "error", "error": type(exc).__name__, "message": str(exc)}
    print(json.dumps(result, ensure_ascii=True))
    return 0 if result.get("status", "enumerated") in {"passed", "captured", "enumerated"} else 1


if __name__ == "__main__":
    sys.exit(main())
