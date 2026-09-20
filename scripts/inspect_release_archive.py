#!/usr/bin/env python3
"""Read-only local archive checks. A pass is NOT TestFlight validation or distribution approval."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

TEAM = "U54BLJMYG6"
BUNDLE = "com.lumetechllc.DailyRhythm"
GROUP = "group." + BUNDLE


def output(*args):
    return subprocess.check_output(args, stderr=subprocess.DEVNULL)


def inspect(archive):
    app = archive / "Products/Applications/DailyRhythm.app"
    report = {"localArchiveChecksPassed": False, "scope": "Local signatures, packaging and disabled experimental/debug entry points only", "targets": []}
    versions = set()
    for bundle, expected in [(app, BUNDLE), (app / "PlugIns/DailyRhythmWidgets.appex", BUNDLE + ".Widgets")]:
        subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True, capture_output=True)
        info = plistlib.loads((bundle / "Info.plist").read_bytes())
        entitlements = plistlib.loads(output("codesign", "-d", "--entitlements", ":-", str(bundle)))
        profile = plistlib.loads(output("security", "cms", "-D", "-i", str(bundle / "embedded.mobileprovision")))
        assert info["CFBundleIdentifier"] == expected and info["DTPlatformName"] == "iphoneos"
        assert entitlements["com.apple.developer.team-identifier"] == TEAM
        assert entitlements["application-identifier"] == TEAM + "." + expected
        assert entitlements["com.apple.security.application-groups"] == [GROUP]
        assert profile["TeamIdentifier"] == [TEAM] and profile["Entitlements"]["com.apple.security.application-groups"] == [GROUP]
        assert profile["ExpirationDate"] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
        privacy = plistlib.loads((bundle / "PrivacyInfo.xcprivacy").read_bytes())
        assert privacy["NSPrivacyTracking"] is False and privacy["NSPrivacyCollectedDataTypes"] == []
        assert privacy["NSPrivacyAccessedAPITypes"] == [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}]
        metadata = json.loads((bundle / "Metadata.appintents/extract.actionsdata").read_bytes())
        actions = metadata["actions"]
        assert all(name in actions for name in ["CreateHabitIntent", "CompleteOccurrenceIntent", "ReopenOccurrenceIntent"])
        assert not any("Schema" in name for name in actions) and not metadata["assistantIntents"]
        executable = bundle / info["CFBundleExecutable"]
        strings = output("strings", "-a", str(executable)).decode(errors="replace")
        assert all(flag not in strings for flag in ["DAILY_RHYTHM_RESTORE_BACKUP", "DAILY_RHYTHM_SCHEMA_SMOKE", "DAILY_RHYTHM_UPGRADE_SEED"])
        dsym = archive / "dSYMs" / (bundle.name + ".dSYM") / "Contents/Resources/DWARF" / info["CFBundleExecutable"]
        binary_uuid = output("dwarfdump", "--uuid", str(executable)).decode().split()[1]
        assert output("dwarfdump", "--uuid", str(dsym)).decode().split()[1] == binary_uuid
        versions.add((info["CFBundleShortVersionString"], info["CFBundleVersion"]))
        report["targets"].append({"bundle": expected, "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
            "minimumOS": info["MinimumOSVersion"], "team": TEAM, "appGroup": GROUP,
            "developmentSignature": entitlements.get("get-task-allow", False), "profileExpires": profile["ExpirationDate"].isoformat() + "Z",
            "executableSHA256": hashlib.sha256(executable.read_bytes()).hexdigest(), "dSYMMatches": True,
            "ordinaryIntentNames": sorted(actions), "schemaIntentsAbsent": True, "debugRecoveryEntryPointAbsent": True})
    assert len(versions) == 1
    app_info = plistlib.loads((app / "Info.plist").read_bytes())
    for key in ["CFBundleIcons", "CFBundleIcons~ipad"]:
        assert app_info[key]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "AppIcon"
    assert (app / "Assets.car").is_file()
    report["iconCatalogPresent"] = True
    report["localArchiveChecksPassed"] = True
    report["developmentSigned"] = any(target["developmentSignature"] for target in report["targets"])
    report["testFlightValidated"] = False
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    print(json.dumps(inspect(args.archive), indent=2))
