"""Summarize and graph captures from Probe.swift using the Python standard library."""

import csv
from collections import defaultdict
import json
import math
from pathlib import Path
from statistics import median


CLOCK_NAMES = {
    "cvdisplaylink": "CVDisplayLink",
    "timer": "DispatchSourceTimer",
    "nsscreen": "NSScreen.displayLink",
}


def write_table(path, rows):
    with path.open("w") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]), delimiter="\t", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def make_report(path):
    with path.open() as file:
        runs = [json.loads(line) for line in file]
    if not runs or len({row["mode"] for row in runs}) != 1:
        raise ValueError("Expected a nonempty capture of one benchmark mode")
    if any(row["clock"] != row["requestedClock"] for row in runs):
        raise ValueError("Clock fallback detected. See trials.jsonl and probe.log.")
    if runs[0]["mode"] == "cpu":
        cpu_report(runs, path.parent)
    elif runs[0]["mode"] == "normalization":
        normalization_report(runs, path.parent)
    elif runs[0]["mode"] == "starts":
        start_report(runs, path.parent)
    elif runs[0]["mode"] == "curves":
        curve_report(runs, path.parent)
    else:
        raise ValueError(f"Unsupported mode: {runs[0]['mode']}")


def cpu_sample(run):
    start, end = run["measurementStart"], run["measurementEnd"]
    events = [s for s in run["samples"]
              if s["stream"] == "output" and (s["y"] or s["x"]) and start <= s["timestamp"] < end]
    if not events or end <= start or run["inputs"] != 240 or run["drops"] or not run.get("clockDisplay"):
        raise ValueError("Incomplete sustained scrolling sample. See trials.jsonl.")
    wall = end - start
    cpu = run["cpuSeconds"]
    return {
        "revision": run["revision"], "round": run["round"],
        "bound_display": run["clockDisplay"]["name"], "display_hz": run["clockDisplay"]["hz"],
        "wall_s": wall, "cpu_pct_one_core": 100 * cpu / wall,
        "cpu_us_per_output": 1e6 * cpu / len(events), "outputs_per_s": len(events) / wall,
        "points_per_s": sum(s["y"] for s in events) / wall,
    }


def cpu_report(runs, directory):
    by_variant = defaultdict(list)
    bound = {
        (r["clockDisplay"]["id"], r["clockDisplay"]["hz"])
        for r in runs if r.get("clockDisplay") is not None
    }
    if len(bound) != 1 or any(r.get("clockDisplay") is None for r in runs):
        raise ValueError("The runs used different or unidentified display clocks")
    for run in runs:
        if run["clock"] != "cvdisplaylink" or run["normalized"]:
            raise ValueError("The CPU comparison requires CVDisplayLink with normalization off")
        by_variant[run["variant"]].append({"variant": run["variant"], **cpu_sample(run)})
    rounds = sorted(row["round"] for row in next(iter(by_variant.values())))
    if any(sorted(row["round"] for row in v) != rounds for v in by_variant.values()):
        raise ValueError("The CPU capture is missing one or more rounds")
    variants = [label for label in ("legacy", "extracted", "candidate") if label in by_variant]
    if "legacy" not in variants or "candidate" not in variants:
        raise ValueError("The CPU capture requires both legacy and candidate results")
    baseline = {row["round"]: row for row in by_variant["legacy"]}
    summary = []
    for label in variants:
        group = by_variant[label]
        delta = [row["cpu_pct_one_core"] - baseline[row["round"]]["cpu_pct_one_core"] for row in group]
        summary.append({
            "variant": label, "revision": group[0]["revision"], "rounds": len(group),
            "cpu_pct_median": median(row["cpu_pct_one_core"] for row in group),
            "cpu_pct_min": min(row["cpu_pct_one_core"] for row in group),
            "cpu_pct_max": max(row["cpu_pct_one_core"] for row in group),
            "cpu_us_per_output_median": median(row["cpu_us_per_output"] for row in group),
            "outputs_per_s_median": median(row["outputs_per_s"] for row in group),
            "points_per_s_median": median(row["points_per_s"] for row in group),
            "paired_cpu_delta_pp_median": median(delta),
            "paired_cpu_delta_pp_min": min(delta), "paired_cpu_delta_pp_max": max(delta),
        })
    write_table(directory / "cpu-runs.tsv", [r for label in variants for r in by_variant[label]])
    write_table(directory / "cpu-summary.tsv", summary)
    nominal = next(iter(bound))[1]
    rates = [row["outputs_per_s_median"] for row in summary]
    if max(rates) - min(rates) > max(1.0, nominal * 0.03):
        raise ValueError("Output rates differ across variants. Check cpu-runs.tsv before interpreting CPU.")
    for row in summary:
        print(f"{row['variant']:>10}  {row['cpu_pct_median']:.3f}%"
              f"  ({row['cpu_pct_min']:.3f}–{row['cpu_pct_max']:.3f}%)"
              f"  {row['cpu_us_per_output_median']:.1f} µs/output"
              f"  {row['outputs_per_s_median']:.1f} outputs/s"
              f"  paired Δ {row['paired_cpu_delta_pp_median']:+.3f} pp")


def normalization_report(runs, directory):
    groups = defaultdict(list)
    for run in runs:
        if run["clock"] != "cvdisplaylink":
            raise ValueError("Normalization CPU measurements require CVDisplayLink")
        sample = {"comparison": run["comparison"], "normalized": run["normalized"], **cpu_sample(run)}
        groups[(run["comparison"], run["normalized"])].append(sample)
    matched = [run["clockDisplay"] for run in runs if run["comparison"] == "matched"]
    if not matched or any(display != matched[0] for display in matched):
        raise ValueError("Matched runs must use the same display clock")
    summary = []
    for comparison in ("auto", "matched"):
        off = {sample["round"]: sample for sample in groups[(comparison, False)]}
        on = {sample["round"]: sample for sample in groups[(comparison, True)]}
        if not off or off.keys() != on.keys():
            raise ValueError("Normalization results are missing paired rounds")
        off_rate = median(sample["outputs_per_s"] for sample in off.values())
        on_rate = median(sample["outputs_per_s"] for sample in on.values())
        if comparison == "matched" and abs(off_rate - on_rate) > max(1.0, matched[0]["hz"] * .03):
            raise ValueError("Matched runs emitted at different rates")
        deltas = [on[index]["cpu_pct_one_core"] - off[index]["cpu_pct_one_core"] for index in sorted(off)]
        summary.append({
            "comparison": comparison, "rounds": len(deltas),
            "off_display": next(iter(off.values()))["bound_display"], "on_display": next(iter(on.values()))["bound_display"],
            "off_outputs_per_s": off_rate, "on_outputs_per_s": on_rate,
            "off_cpu_pct_median": median(sample["cpu_pct_one_core"] for sample in off.values()),
            "on_cpu_pct_median": median(sample["cpu_pct_one_core"] for sample in on.values()),
            "off_cpu_us_per_output": median(sample["cpu_us_per_output"] for sample in off.values()),
            "on_cpu_us_per_output": median(sample["cpu_us_per_output"] for sample in on.values()),
            "paired_delta_pp_median": median(deltas), "paired_delta_pp_min": min(deltas), "paired_delta_pp_max": max(deltas),
        })
    write_table(directory / "normalization-runs.tsv", [row for group in groups.values() for row in group])
    write_table(directory / "normalization-summary.tsv", summary)

    selection_path = directory / "selection.json"
    if selection_path.exists():
        timings = json.loads(selection_path.read_text())
        timings_summary = []
        for state in ("off", "on"):
            first = [r["firstSelection"] for r in runs if r["comparison"] == "auto" and r["normalized"] == (state == "on")]
            for phase, readings in (("first", first), ("reused-binding", timings[state][1:])):
                timings_summary.append({
                    "normalization": state, "selection": phase, "samples": len(readings),
                    "plan_us_median": median(row["planUs"] for row in readings),
                    "binding_us_median": median(row["bindingUs"] for row in readings),
                    "total_us_median": median(row["planUs"] + row["bindingUs"] for row in readings),
                })
        write_table(directory / "selection-summary.tsv", timings_summary)
    for row in summary:
        print(f"{row['comparison']:>7}  off {row['off_cpu_pct_median']:.3f}%  on {row['on_cpu_pct_median']:.3f}%"
              f"  paired Δ {row['paired_delta_pp_median']:+.3f} pp"
              f"  ({row['off_outputs_per_s']:.1f} to {row['on_outputs_per_s']:.1f} outputs/s)")


def start_report(runs, directory):
    groups = defaultdict(list)
    for run in runs:
        selection = run["selection"]
        groups[run["phase"]].append({
            "phase": run["phase"], "revision": run["revision"], "round": run["round"],
            "clock_display_id": run["clockDisplayID"], "target_hz": run["targetHz"],
            "plan_us": selection["planUs"], "binding_us": selection["bindingUs"],
            "selection_us": selection["planUs"] + selection["bindingUs"],
            "submit_us": run["submitUs"], "first_tick_ms": run["firstTickMs"],
            "first_movement_ms": run["firstMovementMs"],
        })
    summary = []
    for phase, group in groups.items():
        if len({(row["clock_display_id"], row["target_hz"]) for row in group}) != 1:
            raise ValueError(f"The clock source or rate changed within the {phase} samples")
        timings = ("plan_us", "binding_us", "selection_us", "submit_us", "first_tick_ms", "first_movement_ms")
        row = {"phase": phase, "samples": len(group)}
        row.update({key + "_median": median(sample[key] for sample in group) for key in timings})
        summary.append(row)
        print(f"{phase:>11}  selection {row['selection_us_median']:.2f} µs"
              f"  submit {row['submit_us_median']:.2f} µs  first movement {row['first_movement_ms_median']:.2f} ms")
    write_table(directory / "first-frame-runs.tsv", [row for group in groups.values() for row in group])
    write_table(directory / "first-frame-summary.tsv", summary)


def curve_report(runs, directory):
    displays = {str(row["display"]["id"]): row["display"] for row in runs}
    targets = sorted({row["requestedTarget"] for row in runs if "requestedTarget" in row})
    names = {str(rate): f"CVDisplayLink → {rate} Hz" for rate in targets} if targets else CLOCK_NAMES
    states = ("true",) if targets else ("false", "true")
    groups = defaultdict(list)
    for run in runs:
        if not run["naturalStop"] or run["drops"] or run["inputs"] != 6:
            raise ValueError("Incomplete curve capture. See trials.jsonl and probe.log.")
        output = [s for s in run["samples"] if s["stream"] == "output"]
        ticks = [s["timestamp"] for s in run["samples"] if s["stream"] == "clock"]
        paced = [s["timestamp"] for s in run["samples"] if s["stream"] == "paced"] or ticks
        inputs = [s for s in run["samples"] if s["stream"] == "input"]
        if len(ticks) < 2 or len(paced) < 2 or len(inputs) != 6 or not output:
            raise ValueError("Missing clock, input, or output samples")
        clock_display = run.get("clockDisplay")
        if run["clock"] == "nsscreen" and clock_display != run["display"]:
            raise ValueError("NSScreen did not bind to the input display")
        if any(s["y"] < 0 or s["x"] != 0 for s in output):
            raise ValueError("The visualization expects the positive-Y input fixture")
        origin = run["firstInput"]
        total = sum(s["y"] for s in output)
        if total <= 0:
            raise ValueError("The curve capture produced no movement")
        cumulative = 0
        points = []
        t90 = None
        for sample in output:
            time = (sample["timestamp"] - origin) * 1000
            cumulative += sample["y"]
            points.append([time, sample["y"], cumulative])
            if t90 is None and cumulative >= total * .9:
                t90 = time
        moving = [sample[0] for sample in points if sample[1]]
        gaps = [[b, b - a] for a, b in zip(moving, moving[1:])]
        intervals = sorted(gap for _, gap in gaps)
        if not intervals:
            raise ValueError("The curve capture needs multiple movement frames")
        group = (str(run["display"]["id"]), str(run["normalized"]).lower(),
                 str(run["requestedTarget"]) if targets else run["clock"])
        groups[group].append({
            "round": run["round"], "points": points, "gaps": gaps,
            "inputs": [(s["timestamp"] - origin) * 1000 for s in inputs],
            "t90": t90, "total": total, "frames": sum(s["y"] != 0 for s in output),
            "hz": (len(ticks) - 1) / (ticks[-1] - ticks[0]), "bound": clock_display,
            "pacedHz": (len(paced) - 1) / (paced[-1] - paced[0]), "targetHz": run.get("targetHz"),
            "gapP50": median(intervals), "gapP95": intervals[math.ceil(.95 * len(intervals)) - 1],
        })

    if any((display, normalized, clock) not in groups
           for display in displays for normalized in states for clock in names):
        raise ValueError("The curve capture is missing a display, clock, or normalization combination")
    if len({len(samples) for samples in groups.values()}) != 1:
        raise ValueError("The curve capture has incomplete rounds")

    summary = []
    visual = {"clockNames": names, "displays": sorted(displays.values(), key=lambda d: (-d["hz"], d["name"])),
              "groups": {}, "pacing": bool(targets)}
    for (display, normalized, clock), samples in sorted(groups.items()):
        runs_by_speed = sorted(samples, key=lambda row: row["t90"])
        representative = runs_by_speed[len(runs_by_speed) // 2]
        visual["groups"].setdefault(display, {}).setdefault(normalized, {})[clock] = representative
        summary.append({
            "input_display": displays[display]["name"], "input_display_hz": displays[display]["hz"],
            "normalized": normalized, "clock": "cvdisplaylink" if targets else clock,
            "clock_display": representative["bound"]["name"] if representative["bound"] else "",
            "clock_hz_median": median(row["hz"] for row in samples),
            "paced_hz_median": median(row["pacedHz"] for row in samples), "target_hz": representative["targetHz"],
            "t90_ms_median": median(row["t90"] for row in samples),
            "total_points_median": median(row["total"] for row in samples),
            "output_gap_ms_p50_median": median(row["gapP50"] for row in samples),
            "output_gap_ms_p95_median": median(row["gapP95"] for row in samples),
            "rounds": len(samples), "representative_round": representative["round"],
        })
    write_table(directory / "curve-summary.tsv", summary)
    template = Path(__file__).with_name("curves.html").read_text()
    payload = json.dumps(visual, ensure_ascii=False, separators=(",", ":")).replace("<", "\\u003c")
    (directory / "curves.html").write_text(template.replace("__CAPTURE__", payload))
    print(f"Captured {len(runs)} trials. Open {directory / 'curves.html'}.")
