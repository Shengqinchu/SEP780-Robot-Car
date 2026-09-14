from pathlib import Path
from contextlib import redirect_stdout
import io
import json
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "host"))
import serial_tool as tool


class Clock:
    def __init__(self):
        self.value = 0.0

    def now(self):
        return self.value

    def advance(self, seconds):
        self.value += seconds


class FakePort:
    def __init__(self, clock, frames=(), answer=True):
        self.clock = clock
        self.frames = list(frames)
        self.pending = b""
        self.answer = answer
        self.writes = []
        self.closed = False

    def read(self, size):
        self.clock.advance(0.05)
        self.frames.sort(key=lambda frame: frame[0])
        while self.frames and self.frames[0][0] <= self.clock.now():
            self.pending += self.frames.pop(0)[1]
        data, self.pending = self.pending[:size], self.pending[size:]
        return data

    def write(self, data):
        self.writes.append(data)
        if self.answer:
            self.frames.append((self.clock.now() + 0.05, tool.ACK + b"\n"))
        return len(data)

    def close(self):
        self.closed = True


class SafetyTests(unittest.TestCase):
    def test_windows_normalization(self):
        self.assertEqual(tool.canonical_port("com5"), "COM5")

    def test_linux_port(self):
        self.assertEqual(tool.canonical_port("/dev/ttyUSB0"), "/dev/ttyUSB0")

    def test_invalid_ports(self):
        for port in ("", "COM0", " COM5", "COM5 ", "COM5\n", "loop://", "rfc2217://host:1234", "file.txt", "/dev/TTYUSB0"):
            with self.subTest(port=port), self.assertRaises(tool.SafetyError):
                tool.canonical_port(port)

    def test_confirmation_before_open(self):
        opener = Mock()
        with self.assertRaises(tool.SafetyError):
            tool.run_session("usb-check", "COM5", False, opener=opener)
        opener.assert_not_called()

    def test_invalid_duration(self):
        for seconds in (0, 61, float("nan"), float("inf")):
            with self.subTest(seconds=seconds), self.assertRaises(tool.SafetyError):
                tool.validate_session("capture", "COM5", True, seconds, 128)

    def test_invalid_byte_limit(self):
        for limit in (127, 65537, 128.5, True):
            with self.subTest(limit=limit), self.assertRaises(tool.SafetyError):
                tool.validate_session("capture", "COM5", True, 1, limit)

    def test_unknown_action(self):
        with self.assertRaises(tool.SafetyError):
            tool.validate_session("drive", "COM5", True, 1, 128)

    def test_list_does_not_open(self):
        with patch.object(tool.list_ports, "comports", return_value=[]), patch.object(tool.serial, "Serial") as opener:
            self.assertEqual(tool.inventory()["ports"], [])
            opener.assert_not_called()

    def test_inactive_lines_before_open(self):
        connection = Mock()
        def check_open():
            self.assertFalse(connection.dtr)
            self.assertFalse(connection.rts)
            self.assertEqual(connection.port, "COM5")
        connection.open.side_effect = check_open
        with patch.object(tool.serial, "Serial", return_value=connection) as factory:
            self.assertIs(tool.open_usb("COM5"), connection)
        self.assertIsNone(factory.call_args.kwargs["port"])
        self.assertEqual(factory.call_args.kwargs["timeout"], 0.05)

    def test_failed_open_is_closed(self):
        connection = Mock()
        connection.open.side_effect = tool.serial.SerialException("disconnected")
        with patch.object(tool.serial, "Serial", return_value=connection), self.assertRaises(tool.serial.SerialException):
            tool.open_usb("COM5")
        connection.close.assert_called_once()


class FramerTests(unittest.TestCase):
    def test_split_line(self):
        framer = tool.LineFramer()
        self.assertEqual(framer.feed(b"ONE"), [])
        self.assertEqual(framer.feed(b"\r\nTWO\n"), [b"ONE", b"TWO"])

    def test_oversized_line_resynchronizes(self):
        framer = tool.LineFramer(8)
        self.assertEqual(framer.feed(b"x" * 100), [])
        self.assertEqual(len(framer.buffer), 0)
        self.assertEqual(framer.feed(b"BAD\nOK\n"), [b"OK"])
        self.assertEqual(framer.dropped_lines, 1)

    def test_exact_limit(self):
        self.assertEqual(tool.LineFramer(4).feed(b"1234\n"), [b"1234"])

    def test_binary_not_decoded_into_commands(self):
        evidence = tool.UsbEvidence()
        evidence.observe(b"\xff" + tool.READY)
        self.assertFalse(evidence.ready_seen)


class EvidenceTests(unittest.TestCase):
    def test_stale_ack_ignored(self):
        evidence = tool.UsbEvidence()
        evidence.observe(tool.ACK)
        self.assertFalse(evidence.query_ack)

    def test_heartbeat_alone_is_not_pass(self):
        evidence = tool.UsbEvidence()
        evidence.observe(b"HEARTBEAT ms=1000")
        evidence.observe(b"HEARTBEAT ms=2000")
        self.assertFalse(evidence.passed)

    def test_duplicate_heartbeat_ignored(self):
        evidence = tool.UsbEvidence()
        evidence.observe(b"HEARTBEAT ms=1000")
        evidence.observe(b"HEARTBEAT ms=1000")
        self.assertEqual(evidence.heartbeat_count, 1)

    def test_unsigned_wrap(self):
        evidence = tool.UsbEvidence()
        evidence.observe(b"HEARTBEAT ms=4294967000")
        evidence.observe(b"HEARTBEAT ms=704")
        self.assertEqual(evidence.heartbeat_count, 2)
        self.assertFalse(evidence.reset_during_check)

    def test_clock_reversal(self):
        evidence = tool.UsbEvidence()
        evidence.observe(b"HEARTBEAT ms=9000")
        evidence.observe(b"HEARTBEAT ms=1000")
        self.assertTrue(evidence.reset_during_check)

    def test_uptime_limits(self):
        evidence = tool.UsbEvidence()
        for line in (b"HEARTBEAT ms=-1", b"HEARTBEAT ms=4294967296", b"HEARTBEAT ms=2000 x"):
            evidence.observe(line)
        self.assertEqual(evidence.heartbeat_count, 0)

    def test_reset_after_query(self):
        evidence = tool.UsbEvidence()
        evidence.query_sent = True
        evidence.observe(tool.READY)
        self.assertTrue(evidence.reset_during_check)


class SessionTests(unittest.TestCase):
    def exercise(self, frames=(), action="usb-check", answer=True, limit=8192):
        clock = Clock()
        port = FakePort(clock, frames, answer)
        with tempfile.TemporaryDirectory() as directory:
            result = tool.run_session(action, "COM5", True, 4, limit,
                                      lock_root=directory, opener=lambda name: port,
                                      clock=clock.now, pause=clock.advance)
            self.assertEqual(list(Path(directory).iterdir()), [])
        self.assertTrue(port.closed)
        return result, port

    def test_usb_success(self):
        frames = [(0, tool.READY + b"\n"), (1.5, b"HEARTBEAT ms=1000\n"), (2.5, b"HEARTBEAT ms=2000\n")]
        result, port = self.exercise(frames)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(port.writes, [b"?"])

    def test_already_running_without_banner(self):
        result, port = self.exercise([(0, b"HEARTBEAT ms=8000\n"), (1.5, b"HEARTBEAT ms=9000\n")])
        self.assertEqual(result["status"], "passed")
        self.assertFalse(result["usb_evidence"]["ready_seen"])
        self.assertEqual(port.writes, [b"?"])

    def test_unknown_firmware_not_written(self):
        result, port = self.exercise([(0, b"Factory firmware\n")])
        self.assertEqual(result["status"], "timeout")
        self.assertEqual(port.writes, [])

    def test_silence_is_bounded(self):
        result, port = self.exercise()
        self.assertEqual(result["status"], "timeout")
        self.assertLess(result["elapsed_ms"], 4200)
        self.assertEqual(port.writes, [])

    def test_capture_never_writes(self):
        result, port = self.exercise([(0, tool.READY + b"\n")], action="capture")
        self.assertEqual(result["status"], "captured")
        self.assertEqual(port.writes, [])

    def test_no_ack_not_pass(self):
        result, _ = self.exercise([(0, tool.READY + b"\nHEARTBEAT ms=1000\nHEARTBEAT ms=2000\n")], answer=False)
        self.assertEqual(result["status"], "timeout")

    def test_pre_query_ack_not_pass(self):
        data = tool.READY + b"\n" + tool.ACK + b"\nHEARTBEAT ms=1000\nHEARTBEAT ms=2000\n"
        result, _ = self.exercise([(0, data)], answer=False)
        self.assertEqual(result["status"], "timeout")

    def test_receive_budget(self):
        result, port = self.exercise([(0, b"x" * 1000)], limit=128)
        self.assertEqual(result["status"], "byte_limit")
        self.assertEqual(result["received_bytes"], 128)
        self.assertEqual(port.writes, [])

    def test_reset_during_check_fails(self):
        result, _ = self.exercise([(0, tool.READY + b"\n"), (1.5, tool.READY + b"\n")])
        self.assertEqual(result["status"], "reset_detected")

    def test_disconnect_closes_and_unlocks(self):
        port = Mock()
        port.read.side_effect = tool.serial.SerialException("unplugged")
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(tool.serial.SerialException):
                tool.run_session("capture", "COM5", True, lock_root=directory, opener=lambda name: port)
            self.assertEqual(list(Path(directory).iterdir()), [])
        port.close.assert_called_once()

    def test_interrupt_closes_and_unlocks(self):
        port = Mock()
        port.read.side_effect = KeyboardInterrupt()
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(KeyboardInterrupt):
                tool.run_session("capture", "COM5", True, lock_root=directory, opener=lambda name: port)
            self.assertEqual(list(Path(directory).iterdir()), [])
        port.close.assert_called_once()

    def test_opener_failure_unlocks(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(tool.serial.SerialException):
                tool.run_session("capture", "COM5", True, lock_root=directory,
                                 opener=Mock(side_effect=tool.serial.SerialException("busy")))
            self.assertEqual(list(Path(directory).iterdir()), [])


class LockTests(unittest.TestCase):
    def test_conflicting_owner_prevents_open(self):
        opener = Mock()
        with tempfile.TemporaryDirectory() as directory:
            with tool.PortLock("COM5", Path(directory)):
                with self.assertRaises(tool.PortBusyError):
                    tool.run_session("capture", "com5", True, lock_root=directory, opener=opener)
                opener.assert_not_called()

    def test_never_remove_changed_owner(self):
        with tempfile.TemporaryDirectory() as directory:
            with tool.PortLock("COM5", Path(directory)) as lock:
                lock.path.write_text(json.dumps({"token": "new-owner"}), encoding="utf-8")
            self.assertTrue(lock.path.exists())

    def test_failed_operation_releases_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(RuntimeError):
                with tool.PortLock("COM5", Path(directory)):
                    raise RuntimeError("failed")
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_lock_name_is_canonical(self):
        self.assertEqual(tool.port_lock_name("COM5"), tool.port_lock_name("com5"))


class SoftwareLoopbackTests(unittest.TestCase):
    def test_pyserial_memory_loopback(self):
        self.assertEqual(tool.loopback_test()["status"], "passed")


class CliTests(unittest.TestCase):
    def test_refused_cli_creates_no_record(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "records"
            with patch.object(tool, "RECORD_ROOT", target), patch.object(tool, "run_session") as session:
                output = io.StringIO()
                with redirect_stdout(output):
                    code = tool.main(["usb-check", "--port", "COM5"])
                self.assertEqual(code, 1)
                self.assertEqual(json.loads(output.getvalue())["error"], "SafetyError")
                session.assert_not_called()
                self.assertFalse(target.exists())

    def test_error_summary_and_trace_saved(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            records = root / "artifacts" / "local"
            with patch.object(tool, "PROJECT_ROOT", root), patch.object(tool, "RECORD_ROOT", records), \
                    patch.object(tool, "run_session", side_effect=tool.serial.SerialException("fake unplug")):
                output = io.StringIO()
                with redirect_stdout(output):
                    code = tool.main(["capture", "--port", "COM5", "--confirm-usb-isolated"])
                result = json.loads(output.getvalue())
                self.assertEqual(code, 1)
                self.assertEqual(result["status"], "error")
                self.assertTrue((root / result["trace"]).is_file())
                self.assertEqual(json.loads((root / result["summary"]).read_text())["error"], "SerialException")

    def test_success_record_links_are_relative(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(tool, "PROJECT_ROOT", root), patch.object(tool, "RECORD_ROOT", root / "artifacts/local"), \
                    patch.object(tool, "run_session", return_value={"action": "usb-check", "status": "passed"}):
                output = io.StringIO()
                with redirect_stdout(output):
                    code = tool.main(["usb-check", "--port", "COM5", "--confirm-usb-isolated"])
                result = json.loads(output.getvalue())
                self.assertEqual(code, 0)
                self.assertFalse(Path(result["trace"]).is_absolute())
                self.assertTrue((root / result["summary"]).is_file())

    def test_firmware_contract_matches_source(self):
        source = (tool.PROJECT_ROOT / "firmware/usb_check/usb_check.ino").read_text()
        self.assertIn(tool.READY.decode(), source)
        self.assertIn(tool.ACK.decode(), source)
        self.assertIn('HEARTBEAT ms=', source)
        self.assertIn('Serial.begin(115200)', source)


if __name__ == "__main__":
    unittest.main()
