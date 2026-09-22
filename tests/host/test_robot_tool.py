import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "host"))
import robot_protocol as protocol
import robot_tool
import simulate
import export_telemetry


def telemetry(ms=1000, mode=0, state=0):
    return f"SEP780 v=1 ms={ms} mode={mode} state={state} owner=0 line=2 mm=800 mv=7400 l=0 r=0\r\n".encode()


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class FakeSerial:
    """UART peer fixture, not a physics or firmware implementation."""
    def __init__(self, clock, known=True, reject=None, drop=None, partial=False, reset=False, fail=False,
                 interrupt=False, ready_after=0.0):
        self.clock = clock
        self.known, self.reject, self.drop, self.partial, self.reset, self.fail = known, reject, drop, partial, reset, fail
        self.pending = []
        self.writes = []
        self.closed = False
        self.mode = 0
        self.interrupt = interrupt
        self.ready_after = ready_after
        self.last_report = -1.0

    def write(self, data):
        self.writes.append(data)
        fields = data.decode().strip().split()
        sequence, action = fields[1], fields[2]
        if self.partial:
            return len(data) - 1
        if self.fail and action == "DRIVE":
            raise OSError("Simulated unplug")
        if self.interrupt and action == "DRIVE":
            self.interrupt = False
            raise KeyboardInterrupt()
        if action == "ARM":
            self.mode = 1 if fields[3] == "LINE" else 2
        if action == "STOP":
            self.mode = 0
        if action != self.drop:
            kind = "ERR" if action == self.reject else "ACK"
            self.pending.append(f"{kind} {sequence}\n".encode())
        return len(data)

    def read(self, size):
        self.clock.now += 0.02
        if self.pending:
            return self.pending.pop(0)
        if self.reset and self.mode:
            self.reset = False
            return b"SEP780 ROBOT READY v=1\n"
        if self.clock.now - self.last_report >= 0.2:
            self.last_report = self.clock.now
            sample = telemetry(int(1000 + self.clock.now * 1000), self.mode,
                               2 if self.mode == 1 else 3 if self.mode == 2 else 0)
            if self.clock.now < self.ready_after:
                sample = sample.replace(b"mm=800", b"mm=0")
            return sample if self.known else b"HEARTBEAT ms=1000\n"
        return b""

    def close(self):
        self.closed = True


class ProtocolTests(unittest.TestCase):
    def test_decodes_valid_telemetry(self):
        value = protocol.parse_telemetry(telemetry().strip())
        self.assertEqual(value["battery_mv"], 7400)
        self.assertEqual(value["state"], "idle")

    def test_rejects_wrong_firmware(self):
        self.assertIsNone(protocol.parse_telemetry(b"HEARTBEAT ms=1"))

    def test_rejects_out_of_range_fields(self):
        valid = telemetry().strip()
        for before, after in [(b"ms=1000", b"ms=4294967296"), (b"state=0", b"state=99"),
                              (b"mm=800", b"mm=9999"), (b"mv=7400", b"mv=99999"), (b"l=0", b"l=-999")]:
            self.assertIsNone(protocol.parse_telemetry(valid.replace(before, after)))

    def test_rejects_extra_fields(self):
        self.assertIsNone(protocol.parse_telemetry(telemetry().strip() + b" extra=1"))

    def test_sequence_and_command_encoding(self):
        self.assertEqual(protocol.encode(7, "line"), b"S 7 ARM LINE\n")
        self.assertEqual(protocol.encode(9, "drive", -80, 90), b"S 9 DRIVE -80 90\n")
        self.assertEqual(protocol.encode(10, "remote", -200, 200), b"S 10 R -200 200\n")
        self.assertEqual(protocol.encode(11, "horn_on"), b"S 11 H 1\n")
        self.assertEqual(protocol.encode(12, "horn_off"), b"S 12 H 0\n")
        self.assertEqual(protocol.encode(10, "speed", speed=50), b"S 10 SPEED 50\n")
        self.assertEqual(protocol.encode(10, "speed", speed=130), b"S 10 SPEED 130\n")

    def test_invalid_sequence(self):
        for value in (0, 65536, -1, True, 1.5):
            with self.assertRaises(ValueError): protocol.encode(value, "stop")

    def test_pwm_and_command_injection_rejected(self):
        for left in (201, -201, True, "0\nS 2 ARM LINE"):
            with self.assertRaises(ValueError): protocol.encode(1, "drive", left, 0)
        for speed in (40, 55, 201, True, "100\nS 2 ARM LINE"):
            with self.assertRaises(ValueError): protocol.encode(1, "speed", speed=speed)
        with self.assertRaises(ValueError): protocol.encode(1, "stop\nARM LINE")


class SessionTests(unittest.TestCase):
    def invoke(self, action="observe", **options):
        clock = Clock()
        peer = FakeSerial(clock, **options)
        events = []
        with tempfile.TemporaryDirectory() as directory:
            result = robot_tool.run_session(action, "COM5", True, action in {"line", "drive"}, 1,
                80 if action == "drive" else 0, 80 if action == "drive" else 0, emit=events.append,
                lock_root=Path(directory), opener=lambda port: peer, clock=clock, pause=clock.sleep)
            self.assertFalse(list(Path(directory).glob("*.lock")))
        self.assertTrue(peer.closed)
        self.assertEqual(events[-1]["event"], "close")
        return result, peer, events, clock

    def test_observe_never_writes(self):
        result, peer, _, _ = self.invoke()
        self.assertEqual(result["status"], "completed")
        self.assertFalse(peer.writes)
        self.assertGreater(result["telemetry_count"], 1)

    def test_unknown_firmware_never_receives_commands(self):
        result, peer, _, clock = self.invoke("line", known=False)
        self.assertEqual(result["status"], "failed")
        self.assertFalse(peer.writes)
        self.assertLess(clock.now, 3.1)

    def test_line_arms_refreshes_and_stops(self):
        result, peer, _, _ = self.invoke("line")
        commands = [p.decode().split()[2] for p in peer.writes]
        self.assertEqual(commands[:2], ["STOP", "ARM"])
        self.assertIn("PING", commands)
        self.assertEqual(commands[-1], "STOP")
        self.assertTrue(result["stop_acknowledged"])
        self.assertEqual(result["status"], "completed")

    def test_motion_waits_for_valid_post_reset_range_before_arm(self):
        result, peer, events, _ = self.invoke("line", ready_after=0.5)
        arm_index = next(i for i, event in enumerate(events)
                         if event.get("event") == "tx" and event.get("action") == "line")
        ready_index = next(i for i, event in enumerate(events) if event.get("event") == "motion_ready")
        self.assertLess(ready_index, arm_index)
        self.assertGreaterEqual(events[ready_index]["range_mm"], 20)
        self.assertEqual(result["status"], "completed")

    def test_motion_never_arms_without_valid_post_reset_range(self):
        result, peer, _, clock = self.invoke("line", ready_after=99.0)
        self.assertEqual(result["status"], "failed")
        self.assertIn("no ARM sent", result["error"])
        self.assertNotIn(b" ARM ", b"".join(peer.writes))
        self.assertTrue(result["stop_acknowledged"])
        self.assertLess(clock.now, 3.5)

    def test_drive_refreshes_at_bounded_intervals(self):
        result, peer, _, clock = self.invoke("drive")
        self.assertGreater(sum(b" DRIVE " in p for p in peer.writes), 4)
        self.assertTrue(result["stop_acknowledged"])
        self.assertLess(clock.now, 2)

    def test_standalone_stop_does_not_arm(self):
        result, peer, _, _ = self.invoke("stop")
        self.assertEqual(len(peer.writes), 1)
        self.assertIn(b" STOP\n", peer.writes[0])
        self.assertTrue(result["stop_acknowledged"])

    def test_rejected_arm_still_sends_stop(self):
        result, peer, _, _ = self.invoke("line", reject="ARM")
        self.assertEqual(result["status"], "failed")
        self.assertNotIn(b"PING", b"".join(peer.writes))
        self.assertTrue(result["stop_acknowledged"])

    def test_lost_arm_ack_still_sends_stop(self):
        result, peer, _, _ = self.invoke("line", drop="ARM")
        self.assertEqual(result["status"], "failed")
        self.assertTrue(result["stop_acknowledged"])
        self.assertEqual(sum(b" ARM " in p for p in peer.writes), 1)

    def test_missing_stop_ack_not_reported_as_success(self):
        result, _, _, _ = self.invoke("line", drop="STOP")
        self.assertEqual(result["status"], "failed")
        self.assertFalse(result["stop_acknowledged"])

    def test_partial_write_fails(self):
        result, _, _, _ = self.invoke("line", partial=True)
        self.assertEqual(result["status"], "failed")
        self.assertIn("Incomplete", result["error"])

    def test_reset_fails_and_stops(self):
        result, peer, _, _ = self.invoke("line", reset=True)
        self.assertEqual(result["status"], "failed")
        self.assertIn("restarted", result["error"])
        self.assertIn(b" STOP\n", peer.writes[-1])

    def test_unplug_fails_and_releases(self):
        result, peer, _, _ = self.invoke("drive", fail=True)
        self.assertEqual(result["status"], "failed")
        self.assertIn("unplug", result["error"])
        self.assertIn(b" STOP\n", peer.writes[-1])

    def test_requires_confirmation_before_open(self):
        opener = Mock()
        with self.assertRaises(ValueError): robot_tool.run_session("observe", "COM5", opener=opener)
        opener.assert_not_called()

    def test_keyboard_interrupt_stops_and_releases(self):
        result, peer, _, _ = self.invoke("drive", interrupt=True)
        self.assertEqual(result["status"], "failed")
        self.assertIn("KeyboardInterrupt", result["error"])
        self.assertTrue(result["stop_acknowledged"])
        self.assertIn(b" STOP\n", peer.writes[-1])

    def test_motion_requires_separate_confirmation(self):
        opener = Mock()
        with self.assertRaises(ValueError): robot_tool.run_session("line", "COM5", True, opener=opener)
        opener.assert_not_called()

    def test_invalid_limits_and_ports_before_open(self):
        for seconds in (0, 31, float("nan"), float("inf"), True):
            with self.assertRaises(ValueError): robot_tool.validate("observe", "COM5", True, False, seconds, 0, 0)
        for port in ("loop://", "COM5\n", "COM0"):
            with self.assertRaises(ValueError): robot_tool.validate("observe", port, True, False, 1, 0, 0)

    def test_observe_rejects_wheel_arguments(self):
        with self.assertRaises(ValueError): robot_tool.validate("observe", "COM5", True, False, 1, 80, 0)

    def test_opener_failure_releases_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(OSError):
                robot_tool.run_session("observe", "COM5", True, lock_root=Path(directory), opener=Mock(side_effect=OSError("offline")))
            self.assertFalse(list(Path(directory).glob("*.lock")))

    def test_link_requires_identity(self):
        with self.assertRaises(robot_tool.SessionError): robot_tool.RobotLink(Mock(), lambda event: None).request("stop")

    def test_old_ack_not_accepted(self):
        clock = Clock()
        peer = FakeSerial(clock, drop="STOP")
        link = robot_tool.RobotLink(peer, lambda event: None, clock, clock.sleep, sequence=10)
        link.identify()
        peer.pending.append(b"ACK 9\n")
        with self.assertRaises(robot_tool.SessionError): link.request("stop")

    def test_uptime_rollover_and_reset(self):
        clock = Clock()
        peer = FakeSerial(clock)
        peer.pending = [telemetry(0xFFFFFFF0), telemetry(16), telemetry(0)]
        link = robot_tool.RobotLink(peer, lambda event: None, clock, clock.sleep)
        link.receive(); link.receive()
        with self.assertRaises(robot_tool.SessionError): link.receive()

    def test_oversized_frame_rejected(self):
        clock = Clock(); peer = FakeSerial(clock); peer.pending = [b"x" * 129]
        link = robot_tool.RobotLink(peer, lambda event: None, clock, clock.sleep)
        with self.assertRaises(robot_tool.SessionError): link.receive()

    def test_receive_byte_budget(self):
        clock = Clock(); peer = FakeSerial(clock); peer.pending = [b"\n"]
        link = robot_tool.RobotLink(peer, lambda event: None, clock, clock.sleep); link.received = 65536
        with self.assertRaises(robot_tool.SessionError): link.receive()


class DataTests(unittest.TestCase):
    def test_scenario_schema_and_commands(self):
        rows, stream = simulate.load_scenario(ROOT / "scenarios/line_course.csv")
        self.assertEqual(len(rows), 35)
        self.assertTrue(stream.startswith("1000 2 800 1 7400 1 0 0\n"))

    def test_wrong_csv_schema_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bad.csv"; source.write_text("ms,line\n1,2\n")
            with self.assertRaises(ValueError): simulate.load_scenario(source)

    def test_nonadvancing_csv_time_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bad.csv"
            source.write_text((ROOT / "scenarios/line_course.csv").read_text().replace("1100,6", "1000,6"))
            with self.assertRaises(ValueError): simulate.load_scenario(source)

    def test_export_real_trace_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            source, target = Path(directory)/"trace.jsonl", Path(directory)/"trace.csv"
            value = dict(event="telemetry", elapsed_ms=10, **protocol.parse_telemetry(telemetry().strip()))
            source.write_text(json.dumps(dict(event="open")) + "\n" + json.dumps(value) + "\n")
            self.assertEqual(export_telemetry.export(source,target),1)
            with target.open() as handle: rows=list(csv.DictReader(handle))
            self.assertEqual(rows[0]["state"],"idle")

    def test_export_cannot_overwrite_input(self):
        with self.assertRaises(ValueError): export_telemetry.export("same.jsonl", "same.jsonl")

    def test_export_rejects_empty_telemetry(self):
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/"trace.jsonl"; source.write_text('{"event":"open"}\n')
            with self.assertRaises(ValueError): export_telemetry.export(source,Path(directory)/"out.csv")


if __name__ == "__main__":
    unittest.main()
