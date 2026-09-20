# Issue #10 — reminder schema validation

Tracking: [#10](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/10). [SDK contract and mapping](../SIRI-SCHEMA-GATE.md).

**Initial tested implementation:** `12ccb3f2138a9dccbda3f0d753120dbc338121af`, based on merged PR #38 (`0b79f86`). **System-dispatch/indexing follow-up:** `aaed43a`, based on merged PR #40 (`189179a`). The initial adapter evidence below is preserved; the follow-up is recorded separately.

**Status: SDK, native adapter and unlocked system-dispatch checks pass. Real Siri creation and completion are user-confirmed; Siri reopen and lock/authentication gates remain open.** Use **Refs #10**. The default product build excludes the experimental schemas; production #11 must not infer Siri availability from compilation or direct `perform()` calls.

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

## Follow-up: real Siri, system dispatch and reported closure

Same phone/OS/toolchain, 20 September 2026. The user explicitly confirmed **Siri AI Beta is active** and previously confirmed English Siri. Region remains unconfirmed.

| User-assisted check | Observed result |
| --- | --- |
| Earlier “Siri Test” creation | No matching item appeared in the app; no exact Siri response was captured. |
| “Create a reminder called Rhythm Probe in Daily Rhythm” | Siri said it created the item; the user confirmed **Rhythm Probe appeared in Today**. Actual Siri creation passes for this phrase without an explicit due date. |
| “Mark Rhythm Probe as completed in Daily Rhythm” before indexing | User reported Siri could not find it. Completion failed at discovery; this does not identify an adapter or crash cause. |
| User-reported ordinary launch closure | User reported that the app also closed when opened normally. App process remained present, app-specific crash-log searches returned zero files, and no same-day Jetsam event appeared. These observations do not disprove an earlier crash. |
| Controlled cold launch of the previously installed build | `devicectl --terminate-existing --console` launched successfully and remained running; user confirmed **Today stayed open**. Closure did not reproduce in this attempt. No crash fix is claimed. The test runner taking foreground is a possible explanation, not a confirmed diagnosis. |
| Siri completion after indexing | User retried the same “Mark Rhythm Probe as completed in Daily Rhythm” phrase and confirmed **Siri completed it and the task appeared completed in the app**. |
| Siri reopen after indexing | Retest requested; no result recorded yet. |

Investigation found the opt-in reminder entity was not donated to Spotlight. The follow-up indexes active one-offs, refreshes pre-existing content on foreground entry, removes archived IDs and excludes archived tasks from resolution/update. A separate out-of-process test reproduced rejection of explicit `isFlagged: false`; the adapter now accepts nil/false and still rejects true before creating a task. Neither finding is presented as a proven cause of the earlier app closure.

### Executed follow-up validation

- **95 core XCTest cases passed**, zero failures (0.539 seconds).
- Signed opt-in `build-for-testing` and default generic Simulator build both succeeded. Default extracted metadata includes ordinary `CreateHabitIntent` and excludes both schema intents and the hidden cleanup intent; opt-in metadata contains them. No Simulator/runtime changed.
- **Four retained AppIntentsTesting tests passed on the physical phone**: list discovery; nil-flag create/query/Spotlight/complete/repeat/reopen/archive; the same flow with explicit false; and true-flag rejection with no task created. Stable occurrence identity, unchanged repeated-completion time, archived-query exclusion and Spotlight deletion are asserted.
- The successful run executed **five tests, zero failures**, 0.918 seconds, because it also included a temporary recovery check for the single UUID-scoped fixture left by the initial outdated-build run. Recovery passed and that temporary test was removed; the four retained tests and app implementation are unchanged from the successful run. All diagnostic fixtures were archived through the normal API; the user's Rhythm Probe was not altered by these tests.
- The initial run had harness issues: framework identifiers differed only by optional bundle qualification, and the installed app was older than the built app so cleanup was unavailable. Instance-ID assertions and explicit installation fixed the harness. A subsequent run isolated the actual false-flag rejection before the final passing run. Failed runs are not counted as passing evidence.
- Project generation check and `git diff --check` passed. App was brought back to foreground after the runner finished. The test-runner app was then uninstalled; the real app and its store remain installed.

Local evidence is under `/tmp/daily-rhythm-siri-investigation/`: `core-tests.log`, `final-build.log`, `recovery-build.log`, `default-build.log`, `dispatch-index.log` (reproduced false-flag failure), `dispatch-spotlight.log` / `.xcresult` (passing run), `cold-launch-console.log`, and scoped crash-list JSON. Raw diagnostic bundles/device identifiers are not committed. Reproduction commands are in [SIRI-SCHEMA-GATE.md](../SIRI-SCHEMA-GATE.md).

## Remaining gate

Required before closing #10 or promoting #11:

1. Confirm device region. Siri AI Beta and English are user-reported, and explicit-app Siri creation is demonstrated by the user-confirmed app result.
2. Finish actual Siri **reopen** with an explicit app name and verify the saved app result. The corresponding unlocked system-dispatch sequence already passes; it does not substitute for Siri recognition.
3. Exercise lock/authentication behaviour. Direct method calls do not validate `requiresLocalDeviceAuthentication` or background system execution.
4. Record truthful unsupported/ambiguous routing results and the unresolved SSU training diagnostic's effect, if any.

Device Hub UI automation still returns `-10005: timeoutReached` in this task; no alternative UI-event injection was used. AppIntentsTesting covers out-of-process framework dispatch, and user-assisted checks cover actual Siri. Generic reminder routing, reopen recognition and lock behavior are not marked passed, and no production schema flag is enabled. The reported closure remains unconfirmed pending another reproducible event or crash report.
