#!/usr/bin/env python3
"""Run native privacy or accessibility checks on an explicitly supplied, booted Simulator.

Creates an isolated app/group in a temporary source copy, never changes Simulator
devices/runtimes, never reads the user's exported backup, and removes its test app.
This is not UI automation: the system share sheet and picker still need UI checks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
PRODUCT = "com.lumetechllc.DailyRhythm"


def command(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def group_path(device: str, bundle: str) -> Path | None:
    result = subprocess.run(["xcrun", "simctl", "get_app_container", device, bundle, "groups"],
                            text=True, capture_output=True)
    for line in result.stdout.splitlines():
        if line.startswith("group." + bundle + "\t"):
            return Path(line.split("\t", 1)[1])
    return None


def store_hashes(group: Path | None):
    if group is None:
        return None
    return {name: hashlib.sha256((group / name).read_bytes()).hexdigest()
            if (group / name).exists() else None
            for name in ["daily-rhythm.json", "daily-rhythm.json.lifecycle",
                         "daily-rhythm.json.v1-backup", "daily-rhythm.json.v2-backup"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Existing booted Simulator UDID; no automatic selection")
    parser.add_argument("--suite", choices=["privacy", "accessibility"], default="privacy")
    args = parser.parse_args()
    issue, helper = (15, "PrivacyValidation") if args.suite == "privacy" else (16, "AccessibilityValidation")
    environment_key = "DAILY_RHYTHM_" + args.suite.upper() + "_VALIDATION"
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    matches = [(runtime, device) for runtime, entries in devices.items() for device in entries
               if device["udid"] == args.device and device["state"] == "Booted"]
    if len(matches) != 1:
        parser.error("The exact supplied Simulator must already be booted. No device will be started or substituted.")
    runtime, device = matches[0]
    output = Path(tempfile.mkdtemp(prefix=f"daily-rhythm-{args.suite}-simulator-"))
    fixture = output / "fixture"
    fixture.mkdir()
    suffix = uuid.uuid4().hex[:12]
    bundle = PRODUCT + f".Validation{issue}." + suffix
    manifest = {"sourceCommit": command("git", "rev-parse", "HEAD", cwd=ROOT),
                "device": args.device, "deviceName": device["name"], "runtime": runtime,
                "suite": args.suite, "bundle": bundle, "output": str(output),
                "sourceChanges": command("git", "status", "--porcelain", cwd=ROOT)}
    original_group = group_path(args.device, PRODUCT)
    original_hashes = store_hashes(original_group)
    installed = False
    result = None
    print(f"Validation artifacts: {output}", flush=True)
    try:
        for folder in ["DailyRhythm", "DailyRhythmWidgets", "DailyRhythmSchemaTests", "Packages", "scripts"]:
            shutil.copytree(ROOT / folder, fixture / folder,
                            ignore=shutil.ignore_patterns(".build", "__pycache__", ".DS_Store"))
        generator = fixture / "scripts/generate_project.py"
        generator.write_text(generator.read_text().replace(PRODUCT, bundle))
        app = fixture / "DailyRhythm/App/DailyRhythmApp.swift"
        marker = "guard scenePhase == .active else { return }"
        assert app.read_text().count(marker) == 1, "Expected one app foreground task"
        app.write_text(app.read_text().replace(marker, marker + f"\n            await {helper}.run(model: model, setup: setup)"))
        shutil.copyfile(ROOT / f"docs/verification/issue-{issue}/{helper}.swift",
                        fixture / f"DailyRhythm/App/{helper}.swift")
        info = fixture / "DailyRhythm/Info.plist"
        values = plistlib.loads(info.read_bytes())
        values["CFBundleDisplayName"] = "Daily Rhythm QA"
        values["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = ["daily-rhythm-validation-" + suffix]
        info.write_bytes(plistlib.dumps(values))
        command("python3", str(generator))
        command("python3", str(generator), "--check")
        print("Building isolated app and widget…", flush=True)
        with (output / "build.log").open("w") as log:
            subprocess.run(["xcodebuild", "-project", str(fixture / "DailyRhythm.xcodeproj"),
                            "-scheme", "DailyRhythm", "-configuration", "Debug", "-sdk", "iphonesimulator",
                            "-destination", "id=" + args.device, "-derivedDataPath", str(output / "DerivedData"),
                            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "build"],
                           stdout=log, stderr=subprocess.STDOUT, check=True)
        product = output / "DerivedData/Build/Products/Debug-iphonesimulator/DailyRhythm.app"
        command("codesign", "--verify", "--deep", "--strict", str(product))
        command("xcrun", "simctl", "install", args.device, str(product))
        installed = True
        environment = dict(os.environ)
        for suite in ["PRIVACY", "ACCESSIBILITY"]:
            environment.pop(f"SIMCTL_CHILD_DAILY_RHYTHM_{suite}_VALIDATION", None)
        environment["SIMCTL_CHILD_" + environment_key] = "1"
        environment.pop("SIMCTL_CHILD_DAILY_RHYTHM_RESTORE_BACKUP", None)
        manifest["validationLaunch"] = command("xcrun", "simctl", "launch", args.device, bundle, env=environment)
        data = Path(command("xcrun", "simctl", "get_app_container", args.device, bundle, "data"))
        report = data / f"Documents/{args.suite}-validation-result.json"
        print("Running native model/service checks…", flush=True)
        deadline = time.monotonic() + 90
        while not report.exists() and time.monotonic() < deadline:
            time.sleep(1)
        if not report.exists():
            raise RuntimeError("The app did not produce a result within 90 seconds; no validation pass is claimed.")
        result = json.loads(report.read_text())
        shutil.copyfile(report, output / "result.json")
        if result["passed"]:
            fixture_group = group_path(args.device, bundle)
            if fixture_group is None:
                raise RuntimeError("Fixture App Group could not be resolved")
            saved = (fixture_group / "daily-rhythm.json").read_bytes()
            normal_environment = dict(os.environ)
            normal_environment.pop("SIMCTL_CHILD_DAILY_RHYTHM_PRIVACY_VALIDATION", None)
            normal_environment.pop("SIMCTL_CHILD_DAILY_RHYTHM_ACCESSIBILITY_VALIDATION", None)
            normal_environment.pop("SIMCTL_CHILD_DAILY_RHYTHM_RESTORE_BACKUP", None)
            manifest["coldLaunch"] = command("xcrun", "simctl", "launch", "--terminate-running-process",
                                              args.device, bundle, env=normal_environment)
            time.sleep(2)
            manifest["coldLaunchPreservedStoreBytes"] = saved == (fixture_group / "daily-rhythm.json").read_bytes()
            if not manifest["coldLaunchPreservedStoreBytes"]:
                raise RuntimeError("Saved bytes changed across cold launch")
    finally:
        manifest["originalStoreUnchanged"] = store_hashes(original_group) == original_hashes if original_group else None
        if installed:
            subprocess.run(["xcrun", "simctl", "terminate", args.device, bundle], capture_output=True)
            cleanup = subprocess.run(["xcrun", "simctl", "uninstall", args.device, bundle], capture_output=True)
            manifest["fixtureAppRemoved"] = cleanup.returncode == 0
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2))
        print(json.dumps({"result": result, "manifest": manifest}, indent=2), flush=True)
    if (not result or not result["passed"] or manifest.get("originalStoreUnchanged") is False
            or not manifest.get("fixtureAppRemoved")):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
