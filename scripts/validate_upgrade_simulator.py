#!/usr/bin/env python3
"""Install old Debug then new Release over one disposable app; never touch product data or Simulator configuration."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import time
import uuid

from validate_privacy_simulator import ROOT, PRODUCT, command, group_path, store_hashes


def snapshot(group, data, bundle):
    files = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in group.glob("*.json*") if p.is_file() and not p.name.endswith(".lock")}
    files["export"] = hashlib.sha256((data / "Documents/upgrade-backup.json").read_bytes()).hexdigest()
    return files


def read_report(path):
    deadline = time.monotonic() + 60
    while not path.exists() and time.monotonic() < deadline:
        time.sleep(1)
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--baseline", required=True, help="Existing commit containing the previous build")
    args = parser.parse_args()
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "available", "--json"))["devices"]
    matches = [(runtime, d) for runtime, entries in devices.items() for d in entries if d["udid"] == args.device and d["state"] == "Booted"]
    if len(matches) != 1:
        parser.error("The exact supplied Simulator must already be booted; none will be selected or started.")
    baseline = command("git", "rev-parse", "--verify", args.baseline + "^{commit}", cwd=ROOT)
    output = Path(tempfile.mkdtemp(prefix="daily-rhythm-upgrade-simulator-"))
    print(f"Upgrade artifacts: {output}", flush=True)
    suffix = uuid.uuid4().hex[:12]
    bundle = PRODUCT + ".Validation21." + suffix
    original_group = group_path(args.device, PRODUCT)
    original = store_hashes(original_group)
    installed = False
    result = {"passed": False, "baselineCommit": baseline, "candidateCommit": command("git", "rev-parse", "HEAD", cwd=ROOT),
              "candidateChanges": command("git", "status", "--porcelain", cwd=ROOT),
              "device": args.device, "runtime": matches[0][0], "bundle": bundle,
              "scope": "In-place Debug-to-Release Simulator upgrade of synthetic app data; not a physical-device or TestFlight install"}
    try:
        old = output / "baseline"
        old.mkdir()
        archive = output / "baseline.tar"
        subprocess.run(["git", "archive", "--format=tar", "-o", str(archive), baseline], cwd=ROOT, check=True)
        with tarfile.open(archive) as source:
            source.extractall(old, filter="data")
        new = output / "candidate"
        new.mkdir()
        for folder in ["DailyRhythm", "DailyRhythmWidgets", "DailyRhythmSchemaTests", "Packages", "scripts"]:
            shutil.copytree(ROOT / folder, new / folder, ignore=shutil.ignore_patterns(".build", "__pycache__", ".DS_Store"))
        shutil.copyfile(ROOT / "docs/verification/issue-21/UpgradeSeed.swift", old / "DailyRhythm/App/UpgradeSeed.swift")
        app = old / "DailyRhythm/App/DailyRhythmApp.swift"
        marker = "guard scenePhase == .active else { return }"
        assert app.read_text().count(marker) == 1
        app.write_text(app.read_text().replace(marker, marker + "\n            await UpgradeSeed.run(model: model, setup: setup)"))
        shutil.copyfile(ROOT / "docs/verification/issue-21/UpgradeProbe.swift", new / "DailyRhythm/App/UpgradeProbe.swift")
        app = new / "DailyRhythm/App/DailyRhythmApp.swift"
        assert app.read_text().count(marker) == 1
        app.write_text(app.read_text().replace(marker, marker + "\n            UpgradeProbe.run()"))
        products = {}
        for name, root, configuration in [("baseline", old, "Debug"), ("candidate", new, "Release")]:
            generator = root / "scripts/generate_project.py"
            generator.write_text(generator.read_text().replace(PRODUCT, bundle))
            info = root / "DailyRhythm/Info.plist"
            values = plistlib.loads(info.read_bytes())
            values["CFBundleDisplayName"] = "Daily Rhythm Upgrade QA"
            values["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = ["daily-rhythm-upgrade-" + suffix]
            info.write_bytes(plistlib.dumps(values))
            command("python3", str(generator)); command("python3", str(generator), "--check")
            print(f"Building {name} ({configuration})…", flush=True)
            with (output / f"{name}-build.log").open("w") as log:
                subprocess.run(["xcodebuild", "-project", str(root / "DailyRhythm.xcodeproj"), "-scheme", "DailyRhythm",
                    "-configuration", configuration, "-sdk", "iphonesimulator", "-destination", "id=" + args.device,
                    "-derivedDataPath", str(output / (name + "-DerivedData")), "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_IDENTITY=-", "build"],
                    stdout=log, stderr=subprocess.STDOUT, check=True)
            product = output / (name + "-DerivedData") / f"Build/Products/{configuration}-iphonesimulator/DailyRhythm.app"
            command("codesign", "--verify", "--deep", "--strict", str(product))
            products[name] = product
            result[name + "Build"] = plistlib.loads((product / "Info.plist").read_bytes())["CFBundleVersion"]
        assert int(result["candidateBuild"]) > int(result["baselineBuild"]), "Candidate must increment the build number"
        environment = {k: v for k, v in os.environ.items() if not k.startswith("SIMCTL_CHILD_DAILY_RHYTHM_")}
        command("xcrun", "simctl", "install", args.device, str(products["baseline"]))
        installed = True
        command("xcrun", "simctl", "launch", args.device, bundle, env={**environment, "SIMCTL_CHILD_DAILY_RHYTHM_UPGRADE_SEED": "1"})
        data = Path(command("xcrun", "simctl", "get_app_container", args.device, bundle, "data"))
        report = data / "Documents/upgrade-seed-result.json"
        seed = read_report(report)
        result["seed"] = {key: value for key, value in seed.items() if key != "onboardingValue"}
        assert seed["passed"], seed
        # cfprefsd can flush later even after synchronize() returns. Do not kill
        # the seed app before its deliberate preference write reaches storage.
        preferences = data / f"Library/Preferences/{bundle}.plist"
        deadline = time.monotonic() + 30
        while True:
            values = plistlib.loads(preferences.read_bytes()) if preferences.exists() else {}
            if values.get("dailyRhythm.completionHaptics") is False:
                result["baselinePreferencesFlushed"] = True
                break
            if time.monotonic() >= deadline:
                raise RuntimeError("Fixture preference did not reach storage before termination")
            time.sleep(1)
        command("xcrun", "simctl", "terminate", args.device, bundle)
        group = group_path(args.device, bundle)
        assert group is not None
        before = snapshot(group, data, bundle)
        assert len(before) >= 4 and "daily-rhythm.json.pilot-diagnostics" in before
        command("xcrun", "simctl", "install", args.device, str(products["candidate"]))
        probe_environment = {**environment, "SIMCTL_CHILD_DAILY_RHYTHM_UPGRADE_PROBE": "1"}
        result["releaseLaunch"] = command("xcrun", "simctl", "launch", args.device, bundle, env=probe_environment)
        after_group = group_path(args.device, bundle)
        after_data = Path(command("xcrun", "simctl", "get_app_container", args.device, bundle, "data"))
        probe_path = after_data / "Documents/upgrade-probe-result.json"
        probe = read_report(probe_path)
        # UserDefaults may be cached by cfprefsd; compare through its native API,
        # not a possibly stale on-disk preferences plist.
        result["nativePreferencesPreserved"] = all(probe.get(k) == seed[k] for k in ["hapticPreferenceReadback", "onboardingValue"])
        result["releaseReadsAllPlans"] = probe.get("planCount") == 4
        # iOS can relocate a data container during an in-place installation.
        # Stable contents and identifiers matter, not its incidental path UUID.
        result["containerPathsUnchanged"] = after_group == group and after_data == data
        result["savedFieldsPreserved"] = snapshot(after_group, after_data, bundle) == before
        result["preservedFields"] = sorted(before)
        probe_path.unlink()
        result["releaseColdLaunch"] = command("xcrun", "simctl", "launch", "--terminate-running-process", args.device, bundle, env=probe_environment)
        cold = read_report(probe_path)
        result["coldLaunchPreferencesPreserved"] = cold == probe
        result["coldLaunchPreserved"] = snapshot(after_group, after_data, bundle) == before
        assert all(result[k] for k in ["savedFieldsPreserved", "coldLaunchPreserved", "nativePreferencesPreserved", "releaseReadsAllPlans", "coldLaunchPreferencesPreserved"])
        result["passed"] = True
    finally:
        result["originalStoreUnchanged"] = store_hashes(original_group) == original if original_group else None
        if installed:
            subprocess.run(["xcrun", "simctl", "terminate", args.device, bundle], capture_output=True)
            result["fixtureRemoved"] = subprocess.run(["xcrun", "simctl", "uninstall", args.device, bundle], capture_output=True).returncode == 0
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result, indent=2), flush=True)
    if not result["passed"] or result.get("originalStoreUnchanged") is False or not result.get("fixtureRemoved"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
