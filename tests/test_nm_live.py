#!/usr/bin/env python3
"""Quick offline consistency checks for the NM iOS build and Live UI."""
import json
import pathlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def ensure(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    status = json.loads(read("docs/status.json"))
    projects = json.loads(read("docs/projects.json"))
    ensure(status["state"] in {"waiting", "progress", "exploit", "released"}, "bad PS4 state")
    ensure(isinstance(projects["projects"], list), "projects should be list")
    ensure(projects["projects"][0]["kind"] == "ps4", "missing PS4 project")

    html = read("docs/nm-live.html")
    ensure("<title>NM Live</title>" in html, "NM Live title missing")
    ensure("window.nmRefresh" in html, "NM Live refresh entry missing")
    ensure("NM_BOOT_STATUS" in html, "offline status support missing")
    ensure("projects.json" in html and "status.json" in html, "GitHub data feeds missing")
    ensure("youtube-nocookie.com/embed/" in html, "YouTube embed support missing")
    ensure("Не найден официально" in html, "unreleased status missing")
    ids = re.findall(r'\bid="([^"]+)"', html)
    ensure(len(ids) == len(set(ids)), "duplicate HTML element IDs")

    scripts = re.findall(r"<script(?:\s[^>]*)?>(.*?)</script>", html, flags=re.DOTALL)
    ensure(scripts, "NM Live has no JavaScript")
    if shutil.which("node"):
        for script in scripts:
            check = subprocess.run(
                ["node", "--check"], input=script, text=True, capture_output=True
            )
            ensure(check.returncode == 0, "Live JavaScript syntax: " + check.stderr)

    project_config = read("ios/project.yml")
    ensure("name: NursMode" in project_config, "wrong iOS project")
    for path in [
        "ios/NursMode/NursModeApp.swift",
        "ios/NursMode/NMAppIntents.swift",
        "ios/NursMode/NMLiveHome.swift",
    ]:
        ensure((ROOT / path).exists(), "Missing Swift source " + path)
        ensure(path.split("/")[-1] in project_config, "Swift source omitted " + path)
    ensure(
        sum(read(p).count("@main") for p in [
            "ios/NursMode/NursModeApp.swift",
            "ios/NursMode/NMAppIntents.swift",
            "ios/NursMode/NMLiveHome.swift",
        ]) == 1, "expected exactly one @main entry point"
    )

    app = read("ios/NursMode/NursModeApp.swift")
    live = read("ios/NursMode/NMLiveHome.swift")
    shortcuts = read("ios/NursMode/NMAppIntents.swift")
    ensure("NMRoot()" in app, "NM Live not wired into launch")
    ensure("struct NMRoot: View" in live, "NMRoot missing")
    ensure('nm.live.cachedHTML' in live, "no offline UI cache")
    ensure("NMStatusCache.notify(fresh)" in app, "missing local milestone notification")
    ensure("NMBackgroundMonitor.check()" in shortcuts, "Shortcuts not checking status")
    ensure("BGTaskScheduler.shared.register(" in app, "background refresh not registered")

    plist = ET.fromstring(read("ios/NursMode/Info.plist"))
    values = [x.text or "" for x in plist.iter()]
    ensure("com.nursmode.iphone.refresh" in values, "BG refresh ID missing in plist")
    ensure("Nurs-Mode" in values, "app display name missing in plist")

    build = read("codemagic.yaml")
    ensure("NursMode.xcodeproj" in build, "Codemagic references wrong project")
    ensure("Nurs-Mode.ipa" in build, "IPA output missing")
    print("NM preflight OK: manifest, Swift wiring, shortcuts, HTML, JS and IPA config")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, json.JSONDecodeError, ET.ParseError) as exc:
        print("NM preflight FAIL:", exc, file=sys.stderr)
        sys.exit(1)
