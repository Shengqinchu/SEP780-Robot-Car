"""Export robot-tool JSONL telemetry to CSV for calibration and plots."""
import argparse
import csv
import json
from pathlib import Path

FIELDS = ("elapsed_ms", "ms", "mode", "state", "owner", "line", "range_mm", "battery_mv", "left_pwm", "right_pwm")


def export(source, output):
    source, output = Path(source), Path(output)
    if source.resolve() == output.resolve():
        raise ValueError("Output must not overwrite the source trace.")
    rows = []
    with source.open(encoding="utf-8-sig") as handle:
        for line in handle:
            event = json.loads(line)
            if event.get("event") == "telemetry":
                rows.append({key: event[key] for key in FIELDS})
    if not rows:
        raise ValueError("The trace has no robot telemetry events.")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    return len(rows)


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("source")
    cli.add_argument("output")
    args = cli.parse_args()
    print(f"Exported {export(args.source, args.output)} telemetry samples.")
