#!/usr/bin/env python3
"""离线分析 Mirroring Scroll Lab 的字段记录轮次

用法:
    analyze-round.py <轮次目录或 frames.jsonl> [更多轮次...] [--json 输出路径]

单个轮次输出捕获侧标定、输出侧字段补齐、帧节奏与会话表; 传入多个轮次时额外打印对照表,
用于 P1 的 V / M0 / M1 / T0 / T1 分组比较。脚本只读记录, 不做任何判定结论。
"""

import argparse
import json
import os
import statistics as st
import sys
from collections import Counter, defaultdict


def load(target):
    path = target
    if os.path.isdir(path):
        path = os.path.join(path, "frames.jsonl")
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    meta = {}
    for name in ("round.json", "config.json", "services.json"):
        candidate = os.path.join(os.path.dirname(path), name)
        if os.path.exists(candidate):
            with open(candidate, encoding="utf-8") as fh:
                meta[name.split(".")[0]] = json.load(fh)
    return rows, meta


def med(values):
    values = [v for v in values if v is not None]
    return round(st.median(values), 4) if values else None


def sign(v):
    return (v > 0) - (v < 0)


def sign_agreement(pairs):
    """一致率: 两列同号或同为零的比例"""
    if not pairs:
        return None
    hit = sum(1 for a, b in pairs if sign(a) == sign(b))
    return round(hit / len(pairs), 3)


def median_ratio(num, den):
    pairs = [(a, b) for a, b in zip(num, den) if b]
    if not pairs:
        return None, None
    ratios = [a / b for a, b in pairs]
    return med(ratios), sign_agreement(pairs)


def by_sender(rows):
    """捕获侧的字段对照, 按 sender 分组。只统计真正交给引擎或原地改写的物理事件"""
    groups = defaultdict(list)
    for r in rows:
        if r.get("kind") != "captured":
            continue
        if not str(r.get("decision", "")).startswith(("repost", "rewrite")):
            continue
        groups[r.get("sender")].append(r)
    out = {}
    for sender, items in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        raws = [i.get("raw_y") for i in items]
        pts = [i.get("point_y") for i in items]
        accs = [i.get("accel_y") for i in items]
        raw_pt, raw_pt_agr = median_ratio(raws, pts)
        acc_pt, acc_pt_agr = median_ratio(accs, pts)
        ns = [(i.get("ns_scroll_y"), i.get("point_y")) for i in items if i.get("ns_scroll_y") is not None]
        out[sender] = {
            "count": len(items),
            "continuous": Counter(i.get("is_continuous") for i in items).most_common(1)[0][0],
            "line_y_med": med([i.get("line_y") for i in items]),
            "point_y_med": med(pts),
            "point_max": max((abs(p) for p in pts if p is not None), default=None),
            "accel_y_med": med(accs),
            "raw_y_med": med(raws),
            "raw_fill_rate": round(sum(1 for v in raws if v) / len(items), 3),
            "accel_fill_rate": round(sum(1 for v in accs if v) / len(items), 3),
            "raw_per_point": raw_pt,
            "raw_per_point_sign_agreement": raw_pt_agr,
            "accel_per_point": acc_pt,
            "accel_per_point_sign_agreement": acc_pt_agr,
            "ns_vs_point_sign_agreement": sign_agreement(ns),
            "ns_scroll_y_med": med([i.get("ns_scroll_y") for i in items]),
            "phases": dict(Counter(i.get("phase") for i in items)),
            "momentum": dict(Counter(i.get("momentum") for i in items)),
            "inverted": dict(Counter(i.get("inverted") for i in items)),
            "x_axis_nonzero": round(sum(1 for i in items if i.get("point_x")) / len(items), 3),
        }
    return out


def emitted_summary(rows):
    groups = defaultdict(list)
    for r in rows:
        if r.get("kind") == "emitted":
            groups[r.get("event")].append(r)
    out = {}
    for name, items in sorted(groups.items()):
        raws = [i.get("raw_y") for i in items]
        accs = [i.get("accel_y") for i in items]
        pts = [i.get("point_y") for i in items]
        out[name] = {
            "count": len(items),
            "modes": dict(Counter(i.get("mode") for i in items)),
            "targets": dict(Counter(str(i.get("target")) for i in items)),
            "outcomes": dict(Counter(str(i.get("outcome")) for i in items)),
            "senders": dict(Counter(i.get("sender") for i in items)),
            "raw_fill_rate": round(sum(1 for v in raws if v) / len(items), 3),
            "accel_fill_rate": round(sum(1 for v in accs if v) / len(items), 3),
            "sum_point_y": sum(v for v in pts if v is not None),
            "sum_raw_y": round(sum(v for v in raws if v is not None), 3),
            "point_max": max((abs(v) for v in pts if v is not None), default=None),
            "phases": dict(Counter(i.get("phase") for i in items)),
            "momentum": dict(Counter(i.get("momentum") for i in items)),
            "zero_frame_rate": round(sum(1 for v in pts if v == 0) / len(items), 3),
            "frame_age_med": med([i.get("frame_age") for i in items]),
            "frame_age_max": max((v for v in (i.get("frame_age") for i in items) if v is not None), default=None),
        }
    return out


def frames_summary(rows):
    frames = [r for r in rows if r.get("kind") == "frame"]
    per_gesture = defaultdict(list)
    for r in frames:
        per_gesture[r.get("gesture")].append(r)
    out = {}
    for gesture, items in sorted(per_gesture.items(), key=lambda kv: str(kv[0])):
        times = sorted(t for t in (i.get("tick_t") for i in items) if t)
        intervals = [b - a for a, b in zip(times, times[1:])]
        dys = [i.get("dy") for i in items if i.get("dy") is not None]
        out[gesture] = {
            "frames": len(items),
            "tick_hz_med": round(1 / med(intervals), 1) if intervals and med(intervals) else None,
            "interval_max_ms": round(1000 * max(intervals), 2) if intervals else None,
            "sum_dy": round(sum(dys), 3),
            "max_abs_dy": round(max((abs(d) for d in dys), default=0), 3),
            "zero_frames": sum(1 for d in dys if d == 0),
        }
    return out


def summarize(target):
    rows, meta = load(target)
    config = meta.get("config") or meta.get("round", {}).get("config", {})
    services = meta.get("services", {})
    captured = [r for r in rows if r.get("kind") == "captured"]
    return {
        "target": target,
        "label": os.path.basename(os.path.normpath(target)),
        "mode": config.get("mode"),
        "tap": config.get("tapLocation"),
        "scope": config.get("scope"),
        "post_target": config.get("postTarget"),
        "sender_mode": config.get("sender"),
        "consume_original": config.get("consumeOriginal"),
        "fill_raw_fields": config.get("fillRawFields"),
        "rows": len(rows),
        "kinds": dict(Counter(r.get("kind") for r in rows)),
        "decisions": dict(Counter(str(r.get("decision")) for r in captured)),
        "captured": by_sender(rows),
        "emitted": emitted_summary(rows),
        "frames": frames_summary(rows),
        "observed_own": sum(1 for r in captured if r.get("decision") == "own_observed"),
        "services": {
            "registry_ids": {str(s.get("registry_id")): s.get("product") or s.get("name")
                             for s in services.get("services", []) if s.get("input_device")},
            "senders": {k: services.get(k) for k in
                        ("learned_trackpad_sender", "learned_mouse_sender", "own_senders",
                         "virtual_magic_trackpad_senders", "multitouch_sender")},
        },
    }


HEADLINE = [
    ("输入事件", lambda s: sum(v["count"] for v in s["captured"].values())),
    ("输出事件", lambda s: sum(v["count"] for v in s["emitted"].values())),
    ("帧", lambda s: sum(v["frames"] for v in s["frames"].values())),
    ("raw 补齐率", lambda s: (max((v["raw_fill_rate"] for v in s["emitted"].values()), default=None)
                              if s["emitted"] else None)),
    ("自身事件观测", lambda s: s["observed_own"]),
    ("投递失败", lambda s: sum(v["outcomes"].get("dropped_no_target", 0) for v in s["emitted"].values())),
    ("单帧最大位移", lambda s: max((v["max_abs_dy"] for v in s["frames"].values()), default=None)),
]


def print_round(s):
    print(f"\n===== {s['label']} =====")
    print(f"模式 {s['mode']}  捕获层 {s['tap']}  范围 {s['scope']}  投递 {s['post_target']}  "
          f"sender 策略 {s['sender_mode']}  吞掉原始 {s['consume_original']}  补齐 175-178 {s['fill_raw_fields']}")
    print(f"记录行 {s['rows']}  明细 {s['kinds']}")
    print(f"捕获决定 {s['decisions']}")
    print(f"设备映射 (注册表 ID -> 设备): {s['services']['registry_ids']}")
    print(f"sender 记录: {s['services']['senders']}")

    print("\n-- 捕获侧标定 (按 sender) --")
    if not s["captured"]:
        print("  无合格输入样本 (需要 decision 为 repost / rewrite 的事件)")
    for sender, v in s["captured"].items():
        print(f"  sender {sender}: {v['count']} 个, 连续={v['continuous']}")
        print(f"    line_y 中位 {v['line_y_med']}  point_y 中位 {v['point_y_med']} (最大 {v['point_max']})"
              f"  accel_y 中位 {v['accel_y_med']}  raw_y 中位 {v['raw_y_med']}")
        print(f"    raw 非零率 {v['raw_fill_rate']}  accel 非零率 {v['accel_fill_rate']}")
        print(f"    raw/point 中位 {v['raw_per_point']} (同号率 {v['raw_per_point_sign_agreement']})"
              f"  accel/point 中位 {v['accel_per_point']} (同号率 {v['accel_per_point_sign_agreement']})")
        print(f"    NSEvent 与 point 同号率 {v['ns_vs_point_sign_agreement']}  ns_scroll_y 中位 {v['ns_scroll_y_med']}")
        print(f"    phase {v['phases']}  momentum {v['momentum']}  inverted {v['inverted']}  横轴非零率 {v['x_axis_nonzero']}")

    print("\n-- 输出侧 --")
    if not s["emitted"]:
        print("  无 CGEvent 输出 (虚拟设备输出只在 frame 记录中留帧号)")
    for name, v in s["emitted"].items():
        print(f"  {name}: {v['count']} 个, 投递 {v['targets']}, 结果 {v['outcomes']}, sender {v['senders']}")
        print(f"    raw 补齐率 {v['raw_fill_rate']}  accel 补齐率 {v['accel_fill_rate']}  "
              f"零位移帧比例 {v['zero_frame_rate']}")
        print(f"    point_y 合计 {v['sum_point_y']}  raw_y 合计 {v['sum_raw_y']}  单帧最大 {v['point_max']}")
        print(f"    phase {v['phases']}  momentum {v['momentum']}")
        print(f"    帧龄 中位 {v['frame_age_med']}s 最大 {v['frame_age_max']}s")

    print("\n-- 帧节奏 --")
    for gesture, v in s["frames"].items():
        print(f"  会话 {gesture}: {v['frames']} 帧, 中位 {v['tick_hz_med']} Hz, 最大间隔 {v['interval_max_ms']} ms, "
              f"位移合计 {v['sum_dy']}, 单帧最大 {v['max_abs_dy']}, 零位移帧 {v['zero_frames']}")


def print_compare(summaries):
    print("\n===== 对照表 =====")
    header = "轮次".ljust(28) + "".join(name.ljust(14) for name, _ in HEADLINE)
    print(header)
    for s in summaries:
        line = s["label"][:27].ljust(28)
        for _, fn in HEADLINE:
            try:
                value = fn(s)
            except (TypeError, KeyError, ValueError):
                value = None
            line += ("-" if value is None else str(value)).ljust(14)
        print(line)


def main():
    parser = argparse.ArgumentParser(description="分析 Mirroring Scroll Lab 的字段记录轮次")
    parser.add_argument("targets", nargs="+", help="轮次目录或 frames.jsonl")
    parser.add_argument("--json", dest="json_out", help="把汇总写入该 JSON 文件")
    args = parser.parse_args()

    summaries = []
    for target in args.targets:
        if not os.path.exists(target):
            print(f"跳过不存在的目标: {target}", file=sys.stderr)
            continue
        summaries.append(summarize(target))
    for s in summaries:
        print_round(s)
    if len(summaries) > 1:
        print_compare(summaries)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(summaries, fh, ensure_ascii=False, indent=2, sort_keys=True)
        print(f"\n汇总已写入 {args.json_out}")


if __name__ == "__main__":
    main()
