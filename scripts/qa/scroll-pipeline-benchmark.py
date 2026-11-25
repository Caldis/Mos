#!/usr/bin/env python3
"""Run the real Mos scroll sender up to the Quartz delivery boundary."""

import argparse
import json
import os
import platform
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from itertools import product


ROOT = Path(__file__).resolve().parents[2]
SUPPORT = Path(__file__).with_name("scroll-pipeline")
BUILD_PATHS = ("Mos", "Mos.xcodeproj", "MosTests", "MosOnboardingExtras", "Config")
CLOCKS = ("cvdisplaylink", "timer", "nsscreen")


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT)


def replace_once(path, before, after):
    source = path.read_text()
    if source.count(before) != 1:
        raise ValueError(f"Cannot find a unique benchmark hook in {path.name}")
    path.write_text(source.replace(before, after, 1))


def append(path, source):
    with path.open("a") as file:
        file.write("\n" + source + "\n")


def copy_sources(destination, revision):
    destination.mkdir()
    if revision:
        commit = git("rev-parse", "--verify", revision + "^{commit}").decode().strip()
        subprocess.run(["/usr/bin/tar", "-xf", "-", "-C", str(destination)],
                       input=git("archive", commit, *BUILD_PATHS), check=True)
        return commit

    for name in git("ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *BUILD_PATHS).split(b"\0"):
        path = Path(os.fsdecode(name))
        if not name or "xcuserdata" in path.parts or path.name.endswith(".local.xcconfig"):
            continue
        source = ROOT / path
        if source.is_file():
            copy = destination / path
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, copy)
    return git("rev-parse", "HEAD").decode().strip() + " (worktree)"


def instrument(source, curves, normalization=False, pacing=False):
    mos = source / "Mos"
    core = mos / "ScrollCore"
    frame_clock = core / "FrameClock"
    poster = core / "ScrollPoster.swift"
    dispatch = core / "ScrollDispatchContext.swift"
    replace_once(dispatch, "snapshot.event.postToPid(snapshot.targetPID)",
                 "ScrollPipelineBenchmark.recordOutput(snapshot.event, targetPID: snapshot.targetPID)")
    shutil.copyfile(SUPPORT / "Probe.swift", mos / "main.swift")

    modern = frame_clock / "ScrollFrameClock.swift"
    selectable = modern.is_file() and "enum ScrollFrameClockKind: String" in modern.read_text()
    adaptive = (frame_clock / "ScrollFrameRate.swift").is_file()
    per_screen = (frame_clock / "ScrollDisplayLayout.swift").is_file()
    cached = "func invalidateFrameRatePlan()" in poster.read_text()
    plan_expression = "frameRatePlanForSession()" if cached else "ScrollFrameRatePlan(displays: displayRates())"
    plan_line = f"        let plan = normalizesTiming ? {plan_expression} : nil"
    binding_line = "        (clock as? DisplayLinkFrameClock)?.setPreferredDisplay(plan?.clockDisplay)"
    if per_screen:
        plan_line = "        let display = normalizesTiming && clock.kind == .displayLink ? displayForSession() : nil"
        binding_line = "        (clock as? DisplayLinkFrameClock)?.setPreferredDisplay(display)"
    if curves and not selectable:
        raise ValueError("curves requires a revision with the three selectable frame clocks")
    if normalization and not (adaptive or per_screen):
        raise ValueError("This benchmark requires scroll timing normalization")
    if pacing and not adaptive:
        raise ValueError("--targets requires a revision with a shared pacing target. Native per-display rates use curves without --targets.")

    video = frame_clock / "DisplayLinkFrameClock.swift"
    screen = frame_clock / "ScreenFrameClock.swift"
    if video.is_file():
        append(video, """extension DisplayLinkFrameClock {
    var benchmarkDisplay: CGDirectDisplayID? { link.map { CVDisplayLinkGetCurrentCGDisplay($0) } }
}""")
        display = "(clock as? DisplayLinkFrameClock)?.benchmarkDisplay"
        if screen.is_file():
            append(screen, """@available(macOS 14.0, *)
private extension ScreenFrameClock {
    var benchmarkDisplay: CGDirectDisplayID? { screen.frameClockDisplayID }
}

extension FrameClockFactory {
    static func benchmarkDisplay(_ clock: ScrollFrameClock) -> CGDirectDisplayID? {
        guard #available(macOS 14.0, *) else { return nil }
        return (clock as? ScreenFrameClock)?.benchmarkDisplay
    }
}""")
            display += " ?? FrameClockFactory.benchmarkDisplay(clock)"
        running = "clock.isRunning"
    else:
        display = "poster.map { CVDisplayLinkGetCurrentCGDisplay($0) }"
        running = "poster.map { CVDisplayLinkIsRunning($0) } ?? false"

    name = "clock.kind.rawValue" if selectable else '"cvdisplaylink"'
    selection = ("captureConfigSnapshotForTests(); configureFrameRateForSession()" if normalization
                 else 'preconditionFailure("Selection measurements require normalization mode")')
    invalidate = "return false"
    if per_screen:
        invalidate = "invalidateDisplayLayout(); return true"
    elif cached:
        invalidate = "invalidateFrameRatePlan(); return true"
    append(poster, f"""extension ScrollPoster {{
    var benchmarkDisplayID: CGDirectDisplayID? {{ {display} }}
    var benchmarkRunning: Bool {{ {running} }}
    var benchmarkClockName: String {{ {name} }}
    func measureBenchmarkSelection() {{ {selection} }}
    func invalidateBenchmarkFrameRate() -> Bool {{ {invalidate} }}
}}""")
    options = mos / "Options/Options.swift"
    set_normalization = ("withReadingLockForTests { scrollNormalizeTiming = normalized }" if selectable
                         else "precondition(!normalized)")
    append(options, f"""extension Options {{
    func configureBenchmark(normalized: Bool) {{
        {set_normalization}
    }}
}}""")

    if normalization:
        replace_once(video, "        if result == kCVReturnSuccess, let valid = created {",
                     """        if result == kCVReturnSuccess, let valid = created {
            if let pinned = ScrollPipelineBenchmark.pinnedDisplay {
                precondition(CVDisplayLinkSetCurrentCGDisplay(valid, pinned) == kCVReturnSuccess)
            }""")
        replace_once(poster, plan_line + "\n" + binding_line,
                     f"""        let start = CACurrentMediaTime()
{plan_line}
        let afterPlan = CACurrentMediaTime()
{binding_line}
        ScrollPipelineBenchmark.recordSelection(plan: afterPlan - start, binding: CACurrentMediaTime() - afterPlan)""")

    if pacing:
        replace_once(poster, plan_line, f"""        let plan: ScrollFrameRatePlan?
        if let target = ScrollPipelineBenchmark.testTargetHz, let source = ScrollPipelineBenchmark.inputDisplay {{
            var displays: [ScrollFrameRatePlan.Display] = [.init(id: source.id, hz: source.hz)]
            // The simulated screen must stay below the physical clock and outside the exact-rate tolerance.
            if target + 15 < source.hz {{ displays.append(.init(id: 0, hz: target + 15)) }}
            plan = ScrollFrameRatePlan(displays: displays)
        }} else {{
            plan = normalizesTiming ? {plan_expression} : nil
        }}""")

    if curves:
        if adaptive:
            replace_once(poster, "        let timing: FrameTiming",
                         """        ScrollPipelineBenchmark.recordTick(timestamp: tick.timestamp, interval: tick.interval)
        let timing: FrameTiming""")
            replace_once(poster, "            timing = FrameTiming(interval: paced.interval, enabled: true)",
                         """            ScrollPipelineBenchmark.recordPacedTick(timestamp: paced.timestamp, interval: paced.interval)
            timing = FrameTiming(interval: paced.interval, enabled: true)""")
            replace_once(poster, "        (clock as? DisplayLinkFrameClock)?.setPreferredDisplay(plan?.clockDisplay)",
                         """        ScrollPipelineBenchmark.targetHz = plan?.targetHz
        (clock as? DisplayLinkFrameClock)?.setPreferredDisplay(plan?.clockDisplay)""")
        else:
            timing = ("        let timing = config.normalizesTiming ? FrameTiming(interval: tick.interval, enabled: true) : .legacy"
                      if per_screen else "        let timing = FrameTiming(interval: tick.interval, enabled: config.normalizesTiming)")
            replace_once(poster, timing,
                         "        ScrollPipelineBenchmark.recordTick(timestamp: tick.timestamp, interval: tick.interval)\n" + timing)
            if per_screen:
                replace_once(poster, binding_line, "        ScrollPipelineBenchmark.targetHz = display?.hz\n" + binding_line)
        replace_once(poster, "            postFrame(shiftedValue)",
                     """            ScrollPipelineBenchmark.recordSmoothed(y: shiftedValue.y, x: shiftedValue.x)
            postFrame(shiftedValue)""")


def build(label, revision, directory, paths, options, curves=False):
    source = directory / "source"
    directory.mkdir()
    commit = copy_sources(source, revision)
    instrument(source, curves, normalization=options.command in ("normalization", "starts"),
               pacing=bool(getattr(options, "targets", None)))
    print(f"Building {label} at {commit}", file=sys.stderr, flush=True)
    derived = directory / "build"
    command = [
        "/usr/bin/xcodebuild", "-project", "Mos.xcodeproj", "-scheme", "Debug",
        "-configuration", "Debug", "-destination", f"platform=macOS,arch={platform.machine()}",
        "-derivedDataPath", str(derived), "-clonedSourcePackagesDirPath", str(paths),
        "-onlyUsePackageVersionsFromResolvedFile",
        "MACOSX_DEPLOYMENT_TARGET=13.0", "SWIFT_OPTIMIZATION_LEVEL=-O",
        "CODE_SIGNING_ALLOWED=NO", "ENABLE_CODE_COVERAGE=NO",
        "COMPILER_INDEX_STORE_ENABLE=NO", "build",
    ]
    log_path = options.out / f"build-{label}.log"
    with log_path.open("w") as log:
        try:
            subprocess.run(command, cwd=source, stdout=log, stderr=subprocess.STDOUT, check=True)
        except subprocess.CalledProcessError:
            raise ValueError(f"Build failed. See {log_path}") from None
    if "-profile-generate" in log_path.read_text():
        raise ValueError(f"The benchmark build contains profiling instructions. See {log_path}")
    products = sorted((derived / "Build/Products/Debug").glob("Mos*.app"))
    if len(products) != 1:
        raise ValueError(f"Expected one Mos app in {derived}")
    with (products[0] / "Contents/Info.plist").open("rb") as plist:
        executable = plistlib.load(plist)["CFBundleExecutable"]
    binary = products[0] / "Contents/MacOS" / executable
    images = [binary, *binary.parent.glob("*.dylib")]
    sections = subprocess.check_output(["/usr/bin/xcrun", "otool", "-l", *map(str, images)], text=True)
    if "__llvm_prf_cnts" in sections:
        raise ValueError(f"The benchmark executable contains profiling counters. See {log_path}")
    return {"label": label, "revision": commit, "binary": binary, "directory": directory}


def probe(build, *args, log_path):
    env = dict(os.environ, XCTestMosScrollBenchmark="1",
               LLVM_PROFILE_FILE=str(build["directory"] / "fixture-%p.profraw"))
    command = ["/usr/bin/caffeinate", "-d", str(build["binary"]), "--mos-scroll-benchmark", *map(str, args)]
    with log_path.open("a") as log:
        try:
            result = subprocess.run(command, cwd=build["directory"], env=env, stdout=subprocess.PIPE,
                                    stderr=log, text=True, timeout=15, check=True)
            return json.loads(result.stdout)
        except (subprocess.SubprocessError, json.JSONDecodeError):
            raise ValueError(f"Probe failed ({build['label']}, {' '.join(map(str, args))}). See {log_path}") from None


def collect_normalization(options, build, screen, log_path):
    pinned = None
    with (options.out / "trials.jsonl").open("w") as output:
        for index in range(options.rounds):
            print(f"Sampling normalization round {index + 1}/{options.rounds}", file=sys.stderr, flush=True)
            comparisons = ("auto", "matched") if index % 2 == 0 else ("matched", "auto")
            states = ("off", "on") if index % 2 == 0 else ("on", "off")
            for comparison in comparisons:
                for state in states:
                    flags = ["--pin-display", pinned] if comparison == "matched" else []
                    result = probe(build, "cpu", screen["id"], state, "--mos-scroll-clock", "cvdisplaylink",
                                   *flags, log_path=log_path)
                    if comparison == "auto" and state == "on":
                        actual = result.get("clockDisplay", {}).get("id")
                        if actual is None or (pinned is not None and actual != pinned):
                            raise ValueError("The selected normalization display changed during sampling")
                        pinned = actual
                    result.update(mode="normalization", comparison=comparison, round=index + 1,
                                  revision=build["revision"], requestedClock="cvdisplaylink")
                    output.write(json.dumps(result, ensure_ascii=False) + "\n")
                    output.flush()
    timings = {state: probe(build, "selection", screen["id"], state, "--mos-scroll-clock", "cvdisplaylink",
                           log_path=log_path) for state in ("off", "on")}
    (options.out / "selection.json").write_text(json.dumps(timings) + "\n")


def collect(options, workspace):
    packages = options.packages or workspace / "SourcePackages"
    if options.command == "cpu":
        revisions = [("legacy", options.baseline)]
        if options.control:
            revisions.append(("extracted", options.control))
        revisions.append(("candidate", options.revision))
    else:
        revisions = [("candidate", options.revision)]
    builds = [build(label, revision, workspace / label, packages, options, options.command in ("curves", "starts"))
              for label, revision in revisions]
    capture(options, builds)


def capture(options, builds):
    log_path = options.out / "probe.log"
    available = probe(builds[-1], "displays", log_path=log_path)

    def matching(query):
        return [screen for screen in available if query in (str(screen["id"]), screen["name"])]

    screens = matching(options.display) if options.display else available
    if not screens:
        raise ValueError("No matching display in the current macOS session")
    if options.command == "normalization":
        collect_normalization(options, builds[0], screens[0], log_path)
        return
    if options.command == "starts":
        alternate = matching(options.alternate_display) if options.alternate_display else []
        if options.alternate_display and (len(alternate) != 1 or alternate[0] == screens[0]):
            raise ValueError("--alternate-display must identify another active display")
        flags = ["--alternate-display", alternate[0]["id"]] if alternate else []
        with (options.out / "trials.jsonl").open("w") as output:
            for index in range(options.rounds):
                print(f"Sampling first-frame round {index + 1}/{options.rounds}", file=sys.stderr, flush=True)
                for sample in probe(builds[0], "starts", screens[0]["id"], "on", "--mos-scroll-clock", "cvdisplaylink",
                                    *flags, log_path=log_path):
                    if alternate:
                        expected = alternate[0] if sample["phase"] == "cross" else screens[0]
                        if sample.get("clockDisplayID") != expected["id"]:
                            raise ValueError("The start probe did not bind to the intended screen")
                    sample.update(mode="starts", revision=builds[0]["revision"], round=index + 1,
                                  requestedClock="cvdisplaylink")
                    output.write(json.dumps(sample, ensure_ascii=False) + "\n")
                output.flush()
        return
    targets = getattr(options, "targets", None)
    if targets:
        if len(screens) != 1 or max(targets) > screens[0]["hz"] * 1.002:
            raise ValueError("Target experiments need one --display with a refresh rate at least as high as every target")

    with (options.out / "trials.jsonl").open("w") as output:
        for round_index in range(options.rounds):
            print(f"Sampling round {round_index + 1}/{options.rounds}", file=sys.stderr, flush=True)
            if options.command == "cpu":
                # Rotate and reverse the order so each build occupies each position equally in six rounds.
                order = builds if round_index % 2 == 0 else list(reversed(builds))
                shift = (round_index // 2) % len(order)
                jobs = [(variant, screens[0], "cvdisplaylink", "off", None) for variant in order[shift:] + order[:shift]]
            elif targets:
                order = targets if round_index % 2 == 0 else reversed(targets)
                jobs = [(builds[0], screens[0], "cvdisplaylink", "on", target) for target in order]
            else:
                jobs = [(builds[0], screen, clock, normalized, None)
                        for screen, clock, normalized in product(screens, CLOCKS, ("off", "on"))]
                shift = (round_index * 5) % len(jobs)
                jobs = jobs[shift:] + jobs[:shift]
            for variant, screen, clock, normalized, target in jobs:
                flags = ["--test-target-hz", target] if target is not None else []
                result = probe(variant, options.command, screen["id"], normalized,
                               "--mos-scroll-clock", clock, *flags, log_path=log_path)
                if target is not None:
                    if result.get("targetHz") != target or result.get("clockDisplay") != screen:
                        raise ValueError("The requested pacing target or physical clock source was not selected")
                    result["requestedTarget"] = target
                result.update(variant=variant["label"], revision=variant["revision"], round=round_index + 1,
                              requestedClock=clock)
                output.write(json.dumps(result, ensure_ascii=False) + "\n")
                output.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name, default_rounds in (("cpu", 6), ("normalization", 6), ("curves", 3), ("starts", 6)):
        command = commands.add_parser(name)
        command.add_argument("--out", required=True, type=lambda value: Path(value).resolve())
        command.add_argument("--rounds", type=int, default=default_rounds)
        command.add_argument("--revision", help="candidate git ref (default: current source worktree)")
        command.add_argument("--packages", type=lambda value: Path(value).resolve(),
                             help="reuse a clonedSourcePackagesDirPath")
        command.add_argument("--display", help="display name or CGDisplay ID")
        if name == "cpu":
            command.add_argument("--baseline", required=True, help="git ref with the old sender")
            command.add_argument("--control", help="optional git ref with only the clock abstraction")
        if name == "curves":
            command.add_argument("--targets", type=int, nargs="+",
                                 help="simulate display layouts for selected normalization rates on the real --display clock")
        if name == "starts":
            command.add_argument("--alternate-display", help="also measure switching to this display and back")
    existing = commands.add_parser("report", help="regenerate the report from an existing trials.jsonl")
    existing.add_argument("trials", type=Path)
    options = parser.parse_args()

    # report.py lives beside the Swift probe and HTML template.
    sys.dont_write_bytecode = True
    sys.path.insert(0, str(SUPPORT))
    from report import make_report

    if options.command == "report":
        make_report(options.trials)
        return
    if options.rounds < 1:
        parser.error("--rounds must be positive")
    targets = getattr(options, "targets", None)
    if targets and (not options.display or len(set(targets)) != len(targets)
                    or any(rate < 60 or rate % 30 for rate in targets)):
        parser.error("--targets requires --display and distinct multiples of 30 Hz at least 60 Hz")
    if platform.system() != "Darwin":
        parser.error("Capturing the real frame clocks requires macOS")
    options.out.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="mos-scroll-pipeline-") as scratch:
        collect(options, Path(scratch))
    make_report(options.out / "trials.jsonl")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as failure:
        sys.exit(str(failure))
