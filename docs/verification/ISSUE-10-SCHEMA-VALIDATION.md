# Issue #10 — reminder schema validation

Tracking: [#10](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/10). [SDK contract and mapping](../SIRI-SCHEMA-GATE.md).

**Tested implementation commit:** `12ccb3f2138a9dccbda3f0d753120dbc338121af`, based on merged PR #38 (`0b79f86`). Subsequent branch changes only record evidence/documentation.

**Status: SDK and native adapter gates pass; Siri/system-dispatch gate remains open.** Use **Refs #10**. The default product build excludes the experimental schemas; production #11 must not infer Siri availability from compilation or direct `perform()` calls.

## Actual environment

20 September 2026. Apple Silicon, macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`), Swift 6.4 / Swift 6 mode. App minimum deployment remains iOS 18.0. Simulator and physical builds use SDK 27.0.

Physical device: **iPhone 16**, **iOS 27.0 (`24A437`)**, Developer Mode enabled. Existing development certificate and explicit app/widget provisioning profiles were used, with no account settings or billing change. Both signatures verified; signed/profile App Groups matched `group.com.lumetechllc.DailyRhythm`, and both profiles included the selected physical phone. Device serial/UDID/profile contents are not included in this repository evidence.

Before launch, the device reported `passcodeRequired: false`, `unlockedSinceBoot: true`. The app reported device locale **en_TR**, preferred languages **en-TR, tr-TR**. The user subsequently confirmed that **Siri/Apple Intelligence is enabled and Siri uses English**. This is user-reported configuration, not demonstrated schema dispatch or feature availability. Device region remains unconfirmed; device locale is not evidence of Siri language. The original device-generated report retains its contemporaneous unverified settings values.

## Builds and tests

| Check | Result |
| --- | --- |
| Core regressions | **85 XCTest cases passed, zero failures**, 0.507 seconds total. Six new schema-mapping tests cover unscheduled/date-only/timed one-offs, timezone preservation, unsupported inputs, and shared-store completion/reopen. |
| Opt-in schema compilation | **BUILD SUCCEEDED** for generic Simulator, including successful App Intents metadata export. Required optional fields and entity resolution support were added in response to actual metadata validation errors. |
| Signed physical build | **BUILD SUCCEEDED**, using existing profiles. Actual create/update schema names occur in extracted app metadata, alongside ordinary intents. Both target signatures/groups verified; installation and launch succeeded. |
| Default baseline build | **BUILD SUCCEEDED**, generic Simulator arm64/x86_64, local ad hoc signing. Extracted metadata includes `CreateHabitIntent` and excludes both prototype schema intents. App launched on the unchanged iPhone 17 Pro / iOS 26.5 Simulator. No Simulator/runtime was substituted or installed. |
| Project and whitespace | Passed. Two new app-only Swift files are in the generated project; core source/tests are discovered by SwiftPM. |

The successful opt-in builds still emit the known `appintentsnltrainingprocessor: Could not archive SSU artifacts` diagnostic and signed-binary stripping warnings. The halting schema validation errors were resolved; the SSU archive diagnostic was not hidden or treated as proof of working Siri training.

Commands:

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py
python3 scripts/generate_project.py --check
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-10/DerivedData \
  OTHER_SWIFT_FLAGS='$(inherited) -DDAILY_RHYTHM_SCHEMA_SPIKE' \
  CODE_SIGNING_ALLOWED=NO build
# Physical opt-in command is in SIRI-SCHEMA-GATE.md.
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-8/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
git diff --check
```

Local logs: `/tmp/daily-rhythm-issue-10/tests.log`, `schema-build.log`, `device-build.log`, `device-install.log`, `baseline-build.log`. The baseline intentionally reuses the earlier issue's DerivedData with the experimental flag absent.

## Physical adapter execution

At **10:29:29 UTC / 13:29:29 Europe/Istanbul**, the signed app's explicitly invoked Debug smoke runner called the **real schema intent implementations** on the iPhone, using its real shared App Group store. This was not a mock, Simulator or host test. It was also **not a Siri/Shortcuts invocation**.

[Actual device-generated report](issue-10/device-adapter-smoke.json):

- Create returned and persisted one one-off at a stable original-day occurrence ID.
- Documented `updateReminder` with completion true persisted full outcome, completion time and appIntent source.
- A repeated completion left the complete snapshot unchanged.
- Update with completion false cleared the result/time on the same occurrence.
- The test-created task was archived through the normal API, making cleanup reversible.
- Pre-existing plans and their managed occurrence snapshots compared equal before/after the test.

The device wrote a local JSON report under its app Documents directory; `devicectl device copy from --domain-type appDataContainer` retrieved only that known test report. No user store file was edited, replaced or copied to bypass the application's mutation service. The phone's existing shared data was preserved by the normal versioned store.

## Remaining gate

Required before closing #10 or promoting #11:

1. Confirm device region and demonstrated Siri AI schema availability. Siri/Apple Intelligence enabled and English language are user-reported.
2. Invoke **Create Daily Rhythm Reminder** and **Update Daily Rhythm Reminder** through actual system dispatch, then through Siri with an explicit app name. Verify create → full completion → reopen and compare the app result.
3. Exercise lock/authentication behaviour. Direct method calls do not validate `requiresLocalDeviceAuthentication` or background system execution.
4. Record truthful unsupported/ambiguous routing results and the unresolved SSU training diagnostic's effect, if any.

Device Hub UI automation still returns `-10005: timeoutReached` in this task; no alternative UI-event injection was used. The direct adapter runner solves the native persistence/mapping check, not that interaction limitation. No Siri availability, recognition or generic reminder routing is marked passed, and no production schema flag is enabled.
