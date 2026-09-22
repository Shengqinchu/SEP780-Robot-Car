"""SEP780 robot protocol v1. Pure parsing/encoding; no I/O."""
import re

MODES = ("idle", "line", "manual")
STATES = ("idle", "ready", "following", "manual", "obstacle", "clear_wait", "line_lost",
          "ambiguous_line", "sensor_fault", "low_battery", "remote_timeout", "command_error", "stopped", "bad_config")
TELEMETRY = re.compile(
    rb"SEP780 v=1 ms=(\d{1,10}) mode=([0-2]) state=(\d{1,2}) owner=([01]) "
    rb"line=([0-7]) mm=(\d{1,4}) mv=(\d{1,5}) l=(-?\d{1,3}) r=(-?\d{1,3})")


def parse_telemetry(line: bytes):
    match = TELEMETRY.fullmatch(line)
    if not match:
        return None
    ms, mode, state, owner, bits, mm, mv, left, right = map(int, match.groups())
    if ms > 0xFFFFFFFF or state >= len(STATES) or mm > 4000 or mv > 20000 or abs(left) > 200 or abs(right) > 200:
        return None
    return dict(ms=ms, mode=MODES[mode], state=STATES[state], owner=("serial", "infrared")[owner],
                line=bits, range_mm=mm, battery_mv=mv, left_pwm=left, right_pwm=right)


def encode(sequence: int, action: str, left: int = 0, right: int = 0, speed: int = 100) -> bytes:
    if type(sequence) is not int or not 1 <= sequence <= 65535:
        raise ValueError("Sequence must be an integer in 1..65535.")
    if any(type(value) is not int or not -200 <= value <= 200 for value in (left, right)):
        raise ValueError("Wheel PWM must be integer values in -200..200.")
    if type(speed) is not int or not 50 <= speed <= 200 or (speed - 50) % 10:
        raise ValueError("Speed must be in 50..200 in steps of 10.")
    commands = {"stop": "STOP", "line": "ARM LINE", "manual": "ARM MANUAL", "ping": "PING", "status": "STATUS",
                "speed": f"SPEED {speed}", "drive": f"DRIVE {left} {right}",
                "remote": f"R {left} {right}", "horn_on": "H 1", "horn_off": "H 0"}
    if action not in commands:
        raise ValueError("Unknown robot command.")
    return f"S {sequence} {commands[action]}\n".encode("ascii")
