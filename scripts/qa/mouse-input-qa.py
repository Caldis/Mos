#!/usr/bin/env python3
"""Run a marked Quartz side-button pair through a local Mos/browser fixture."""

import argparse
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import time
from uuid import uuid4


TEMP = Path("/tmp").resolve()
DOMAIN = f"gui/{os.getuid()}"
BUNDLE_ID = "com.caldis.Mos.debug"
GATE_ARGUMENT = "--mos-check-input-permission"
SESSION_PREFIX = "mos-mouse-qa-"


def launchctl(*arguments, check=True):
    return subprocess.run(
        ["/bin/launchctl", *map(str, arguments)], check=check, capture_output=True,
        text=True, timeout=12,
    )


class Session:
    def __init__(self, path):
        self.path = Path(path).resolve(strict=True)
        if (self.path.parent != TEMP or not self.path.name.startswith(SESSION_PREFIX)
                or self.path.stat().st_uid != os.getuid()):
            raise ValueError("Use the session directory returned by start")
        self.token = self.path.name[len(SESSION_PREFIX):]
        self.label = f"org.caldis.mos.mouse-qa.{self.token}"

    def job(self, name):
        return f"{DOMAIN}/{self.label}.{name}"

    def info(self, name):
        return launchctl("print", self.job(name), check=False)

    def stop(self, name):
        if self.info(name).returncode != 0:
            return
        launchctl("bootout", self.job(name), check=False)
        # launchd can answer print while the old process is still exiting.
        wait_until(lambda: self.info(name).returncode != 0, 6, f"Could not remove {self.job(name)}")

    def load(self, name, command, environment=None):
        log = str(self.path / f"{name}.log")
        config = {
            "Label": f"{self.label}.{name}",
            "ProgramArguments": list(map(str, command)),
            "EnvironmentVariables": environment or {},
            "RunAtLoad": True,
            "ProcessType": "Interactive",
            "ExitTimeOut": 3,
            "WorkingDirectory": str(self.path),
            "StandardOutPath": log,
            "StandardErrorPath": log,
        }
        file = self.path / f"{name}.plist"
        file.write_bytes(plistlib.dumps(config))
        launchctl("bootstrap", DOMAIN, file)

    def ready(self, budget=0):
        info = self.info("guard")
        if info.returncode != 0 or "state = running" not in info.stdout:
            raise RuntimeError("The local QA watchdog is inactive")
        state = json.loads((self.path / "ready.json").read_text())
        if state["deadline"] - time.monotonic() < budget or (self.path / "finish").exists():
            raise RuntimeError("This QA session is ending. Start a new session")
        return state


def wait_until(predicate, seconds, message):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.1)
    raise RuntimeError(message)


def preference_hash():
    result = subprocess.run(
        ["/usr/bin/defaults", "export", BUNDLE_ID, "-"], capture_output=True, timeout=5,
    )
    if result.returncode:
        # An unseeded Debug domain does not have an export.
        return "absent"
    return hashlib.sha256(result.stdout).hexdigest()


def serve(session, timeout):
    class Fixture(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path not in ("/1", "/2", "/3"):
                self.send_error(404)
                return
            page = int(self.path[-1])
            next_page = page + 1 if page < 3 else 1
            link = f"进入第 {next_page} 页" if page < 3 else "重建历史"
            content = f"""<!doctype html>
<html lang="zh-CN"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mos Input QA {session.token} | {page}</title>
<style>body {{max-width:40rem;margin:12vh auto;padding:1rem;font:18px system-ui}}</style>
<h1>鼠标事件验收 · 第 {page} 页</h1>
<p>依次打开第 1、2、3 页，为验收建立浏览器导航历史。</p>
<a href="/{next_page}">{link}</a></html>"""
            body = content.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    deadline = time.monotonic() + timeout
    try:
        # Idle browser connections must never block the watchdog.
        with ThreadingHTTPServer(("127.0.0.1", 0), Fixture) as server:
            server.timeout = 0.25
            state = {"url": f"http://127.0.0.1:{server.server_port}/1", "deadline": deadline}
            path = session.path / "ready.pending"
            path.write_text(json.dumps(state))
            path.rename(session.path / "ready.json")
            while time.monotonic() < deadline and not (session.path / "finish").exists():
                server.handle_request()
    finally:
        session.stop("app")
        (session.path / "finished").touch()


def start(timeout):
    session = Session(tempfile.mkdtemp(prefix=SESSION_PREFIX, dir=TEMP))
    try:
        swift = Path(__file__).with_name("mouse-input-probe.swift")
        subprocess.run(
            ["/usr/bin/xcrun", "swiftc", "-o", session.path / "probe", swift],
            check=True, timeout=30,
        )
        (session.path / "prefs-before").write_text(preference_hash())
        session.load("guard", [sys.executable, Path(__file__).resolve(), "_guard", session.path, timeout])
        wait_until(lambda: (session.path / "ready.json").exists(), 5, "The QA watchdog did not start")
        state = session.ready()
    except BaseException:
        session.stop("guard")
        shutil.rmtree(session.path)
        raise
    print(json.dumps({"session": str(session.path), "url": state["url"]}))


def mos_instances():
    return subprocess.run(["/usr/bin/pgrep", "-x", "Mos|Mos Debug"], capture_output=True, timeout=5).returncode == 0


def signed_test_binary(bundle, session):
    bundle = Path(bundle).resolve(strict=True)
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != "Mos Debug":
        raise ValueError(f"Expected a signed Mos Debug bundle with ID {BUNDLE_ID}")
    executable = bundle / "Contents/MacOS/Mos Debug"
    subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--deep", bundle], check=True, timeout=15)
    # Confirm the pre-AppKit command exists before trying it on an older build.
    code = [executable, executable.with_suffix(".debug.dylib")]
    if not any(path.is_file() and GATE_ARGUMENT.encode() in path.read_bytes() for path in code):
        raise ValueError("This Debug build does not contain the input-permission preflight")
    result = subprocess.run(
        [executable, GATE_ARGUMENT], cwd=session.path,
        env={**os.environ, "LLVM_PROFILE_FILE": "/dev/null"}, capture_output=True, timeout=5,
    )
    if result.returncode != 0:
        raise RuntimeError("This Debug build needs its existing Accessibility approval before input QA")
    return executable


def data_argument(value):
    return "<" + json.dumps(value, separators=(",", ":")).encode().hex() + ">"


def binding(value):
    button, separator, action = value.partition("=")
    if not separator or not button.isdecimal() or not 2 <= int(button) <= 31 or not re.fullmatch(r"[A-Za-z0-9_:]+", action):
        raise argparse.ArgumentTypeError("Use a button number from 2 through 31 and a Mos action, e.g. 3=moveSpaceLeft")
    return {
        "id": str(uuid4()),
        "triggerEvent": {"type": "mouse", "code": int(button), "modifiers": 0},
        "systemShortcutName": action,
        "isEnabled": True,
        "createdAt": 0,
    }


def load_app(session, bundle, bindings):
    session.ready(budget=20)
    executable = signed_test_binary(bundle, session)
    session.stop("app")
    wait_until(lambda: not mos_instances(), 3, "Quit the other Mos instance before starting QA")
    session.ready(budget=10)
    inactive_hotkey = data_argument({"type": "keyboard", "code": 65535})
    options = {
        "buttonBindings": data_argument(bindings), "applications": data_argument([]),
        "optionsExist": "qa-fixture", "allowlist": "NO", "checkOnAppStart": "NO",
        "hideStatusItem": "NO", "smooth": "NO", "reverse": "NO",
        "dash": inactive_hotkey, "toggle": inactive_hotkey, "block": inactive_hotkey,
    }
    args = [item for key, value in options.items() for item in (f"-{key}", value)]
    log = session.path / "app.log"
    log.write_text("")
    try:
        # Reuse the hosted-test defaults guard while opting into real app startup.
        session.load("app", [executable, *args], {
            "XCTestMosInputQA": "1", "MOS_TEST_ENABLE_APP_STARTUP": "1",
            "LLVM_PROFILE_FILE": "/dev/null",
        })
        wait_until(lambda: "Input permission probe: granted" in log.read_text(), 5, "Debug did not acquire input permission")
        session.ready()
    except BaseException:
        session.stop("app")
        raise
    print(json.dumps({"app": str(executable.parent.parent.parent), "bindings": [
        {"button": item["triggerEvent"]["code"], "action": item["systemShortcutName"]} for item in bindings
    ]}))


def check(session, button, phases, page):
    session.ready(budget=5)
    app_pid = re.search(r"^\s*pid = (\d+)", session.info("app").stdout, re.M)
    if app_pid is None:
        if mos_instances():
            raise RuntimeError("Quit the unrelated Mos instance before testing the control case")
        if phases != "both":
            raise RuntimeError("Load a Mos Debug build with the app command before expecting interception")
    output = subprocess.check_output([session.path / "probe", session.token, str(button)], text=True, timeout=8)
    result = json.loads(output)
    expected = {"both": ["down", "up"], "up": ["up"], "none": []}[phases]
    app = plistlib.loads((session.path / "app.plist").read_bytes()) if app_pid else None
    result.update(
        app=app["ProgramArguments"][0] if app else None,
        appPID=int(app_pid[1]) if app_pid else None,
        expected={"downstream": expected, "pageAfter": page},
    )
    upstream = result["upstream"]
    downstream = result["downstream"]
    passed = (
        [item["phase"] for item in upstream] == ["down", "up"]
        and upstream[0]["number"] == upstream[1]["number"]
        and [item["phase"] for item in downstream] == expected
        and all(item["number"] == upstream[0]["number"] for item in downstream)
        and result["pageAfter"] == page
    )
    result["passed"] = passed
    line = json.dumps(result)
    with (session.path / "results.jsonl").open("a") as history:
        history.write(line + "\n")
    print(line)
    if not passed:
        raise RuntimeError("Observed input or browser navigation differs from the expected result")


def stop(session):
    (session.path / "finish").touch()
    session.stop("app")
    session.stop("guard")
    if (session.path / "prefs-before").read_text() != preference_hash():
        raise RuntimeError("The persistent Debug preferences differ from the pre-test snapshot")
    print(f"Stopped QA jobs. Results are in {session.path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True, metavar="{start,app,check,stop}")
    begin = commands.add_parser("start", help="start the local webpage and an independent watchdog")
    begin.add_argument("--timeout", default=420, type=int, choices=range(10, 1801), metavar="10..1800")
    app = commands.add_parser("app", help="start or replace this session's signed Mos Debug")
    app.add_argument("session")
    app.add_argument("bundle")
    app.add_argument("--bind", action="append", type=binding, default=[], metavar="BUTTON=ACTION")
    run = commands.add_parser("check", help="send one native pair and compare both observations")
    run.add_argument("session")
    run.add_argument("--button", type=int, choices=range(2, 32), default=3, metavar="2..31")
    run.add_argument("--expect", required=True, choices=["both", "up", "none"])
    run.add_argument("--page", required=True, type=int, choices=[2, 3])
    end = commands.add_parser("stop", help="remove this session's jobs and verify Debug preferences")
    end.add_argument("session")
    guard = commands.add_parser("_guard")
    guard.add_argument("session")
    guard.add_argument("timeout", type=int)
    args = parser.parse_args()
    if args.command == "start":
        start(args.timeout)
        return
    session = Session(args.session)
    if args.command == "_guard":
        serve(session, args.timeout)
        return
    # Keep two test invocations from changing the foreground or live app together.
    with (TEMP / f"mos-mouse-qa-{os.getuid()}.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.command == "app":
            load_app(session, args.bundle, args.bind)
        elif args.command == "check":
            check(session, args.button, args.expect, args.page)
        else:
            stop(session)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(error.stderr.strip() if getattr(error, "stderr", None) else error, file=sys.stderr)
        sys.exit(1)
