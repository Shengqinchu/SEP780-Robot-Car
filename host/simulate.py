"""Replay CSV sensor inputs through the compiled C++ controller; never opens serial."""
import argparse
import csv
import io
import json
from pathlib import Path
import subprocess

from robot_protocol import MODES, STATES

ACTIONS = {"none": 0, "arm_line": 1, "arm_manual": 2, "drive": 3, "ping": 4, "stop": 5}
FIELDS = ("ms", "line", "range_mm", "range_valid", "battery_mv", "command", "left", "right",
          "expected_state", "expected_left", "expected_right")


def load_scenario(path):
    with Path(path).open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames != list(FIELDS):
            raise ValueError("Scenario columns do not match the documented schema.")
        rows = list(reader)
    if not rows or len(rows) > 10000:
        raise ValueError("Scenario must contain 1..10000 samples.")
    previous = None
    encoded = []
    for row in rows:
        limits = {"ms": (0, 0xFFFFFFFF), "line": (0, 7), "range_mm": (0, 4000), "range_valid": (0, 1),
                  "battery_mv": (0, 20000), "left": (-150, 150), "right": (-150, 150),
                  "expected_left": (-180, 180), "expected_right": (-180, 180)}
        for key, (low, high) in limits.items():
            row[key] = int(row[key])
            if not low <= row[key] <= high:
                raise ValueError(f"Invalid {key}.")
        if row["command"] not in ACTIONS or row["expected_state"] not in STATES:
            raise ValueError("Unknown scenario command or expected state.")
        if previous is not None and not 0 < (row["ms"] - previous) & 0xFFFFFFFF < 0x80000000:
            raise ValueError("Scenario time must advance, allowing uint32 rollover.")
        previous = row["ms"]
        values = [row[k] for k in ("ms", "line", "range_mm", "range_valid", "battery_mv")]
        values += [ACTIONS[row["command"]], row["left"], row["right"]]
        encoded.append(" ".join(map(str, values)))
    return rows, "\n".join(encoded) + "\n"


def replay(executable, scenario, output):
    expected, encoded = load_scenario(scenario)
    process = subprocess.run([str(Path(executable).resolve()), "--replay"], input=encoded, text=True,
                             capture_output=True, check=True, timeout=30)
    rows = list(csv.DictReader(io.StringIO(process.stdout)))
    if len(rows) != len(expected):
        raise ValueError("Native runner returned an unexpected number of samples.")
    failures = []
    for index, (actual, want) in enumerate(zip(rows, expected), 2):
        actual["mode"] = MODES[int(actual["mode"])]
        actual["state"] = STATES[int(actual["state"])]
        if (int(actual["ms"]), actual["state"], int(actual["left_pwm"]), int(actual["right_pwm"]), int(actual["accepted"])) != (
                want["ms"], want["expected_state"], want["expected_left"], want["expected_right"], 1):
            failures.append(index)
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    return {"scope": "Synthetic sensor replay through production C++ logic; no physics or hardware simulation",
            "samples": len(rows), "passed": len(rows) - len(failures), "failed_csv_rows": failures}


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--executable", required=True)
    cli.add_argument("--scenario", required=True)
    cli.add_argument("--output", required=True)
    args = cli.parse_args()
    result = replay(args.executable, args.scenario, args.output)
    print(json.dumps(result, indent=2))
    return 1 if result["failed_csv_rows"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
