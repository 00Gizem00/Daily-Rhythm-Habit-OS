# First implementation milestone

This milestone establishes a local habit loop that the future Siri AI and PCC features can use. Product scope and research remain in [PRODUCT_PLAN.md](PRODUCT_PLAN.md).

## Structure

| Path | Responsibility |
| --- | --- |
| `Packages/DailyRhythmCore` | Foundation-only models, recurring occurrences, history, persistence and tests |
| `DailyRhythm/App` | SwiftUI Today, habit creation/management and history screens |
| `DailyRhythm/Shared` | App Group store factory, occurrence entities and ordinary App Intents / App Shortcuts |
| `DailyRhythmWidgets` | Interactive small/medium widgets and Lock Screen progress |
| `scripts/generate_project.py` | Dependency-free, deterministic Xcode project generation |
| `.github/workflows/ios.yml` | macOS core tests and unsigned iOS Simulator builds |

## Data and concurrency

Each habit has a UUID and a weekday schedule. Each occurrence has a stable ID made from the habit UUID and its local civil date. The store derives occurrences when read, so tomorrow does not require a background task to run at midnight.

Completions retain the occurrence's target and full/light outcome. Repeating completion is a no-op: the first successful outcome and timestamp are retained until the user explicitly reopens the occurrence. Archives retain earlier history and completed work. Editing schedules and targets is not exposed yet, so the first format does not need to reinterpret old edited schedules.

Every reader/writer acquires a POSIX advisory lock on a separate stable lock file, reloads the latest JSON and atomically replaces it only after a successful mutation. Locking the JSON inode itself would be unsafe because atomic replacement changes the inode. App, widget and intents must all use `RoutineStore`; writing the JSON directly is unsupported.

Unknown schema versions, invalid records, failed reads and failed writes produce errors. They never trigger an empty-store replacement. Version 1 is deliberately explicit; future schema changes require migration code.

Date keys follow a Gregorian local civil day in the configured time zone. The app creates a fresh store when refreshing so timezone changes take effect. History follows recorded date keys rather than moving yesterday's completions when the user travels. Calendar-based day arithmetic handles 23/25-hour daylight-saving days.

The first implementation is for small personal habit sets. Whole-file JSON transactions avoid a database dependency; benchmark and migrate before adding large imports or long histories. UI refreshes on foregrounding and periodically while active. Widget reload requests remain subject to WidgetKit scheduling.

## Siri and widget scope

The current code uses ordinary App Intents and App Shortcuts. Those are useful on iOS 18+, but are not the new iOS 27 `.reminders` App Schemas. Do not advertise natural-language Siri AI support based on this milestone.

Widget completion carries the exact occurrence ID displayed. The intent checks the current day again before writing, so a stale widget cannot complete tomorrow's item. Entity lookup preserves exact IDs. Shortcuts selection shows the target before the daypart, date and recorded status: the #4 physical-device check exposed identical rows for two pending Morning habits named Read with different targets when only daypart/date were shown. Repeating create requests currently creates separate habits; only completion/reopen are idempotent.

The store is shared through `group.com.lumetechllc.DailyRhythm`. The app and extension read the configured identifier from `DailyRhythmAppGroup` in their Info.plist. Physical-device signing must grant both targets the same group. There is no separate fallback database.

The [issue #4 device matrix](verification/ISSUE-4-DEVICE-VALIDATION.md) records physical-device provisioning and cross-surface checks separately from the Simulator smoke test below. The first device build exposed an account configuration failure: App Groups capability was enabled, but neither app ID had a group assigned. Both explicit development profiles therefore contained an empty group list. Register and assign the exact group to both app IDs before refreshing profiles; do not remove the entitlement or introduce a second store to get past signing.

## AI and Dynamic Island follow-up

1. Validate the official reminder schemas against the current Xcode 27 SDK and a Siri AI-enabled physical device. Map creation and `updateReminder` completion onto the same mutation service.
2. Add a proposal-only PCC planning service with runtime availability, quota and network handling. Manual setup remains available. User review and Apply are required before generating persistent habits.
3. Implement explicit routine sessions, then display their current step and remaining time through ActivityKit and Dynamic Island. Do not use a permanent all-day Live Activity.

No placeholder PCC responses, unofficial schema names or pretend Dynamic Island sessions are included in this milestone.

## Verification

Core tests cover recurrence, day rollover and DST, duplicate completion, full/light separation, reopen, archive/history, disk reload, corrupt/unsupported data and concurrent store instances. CI builds the SwiftUI app and widget extension against its installed Xcode SDK.

An unsigned Simulator build does not verify signing, App Group provisioning, Siri recognition, widget refresh latency, accessibility or visual layout. Before TestFlight, run these device checks:

- Add a daily habit and a weekday-only habit; relaunch and verify the records remain.
- Complete a full and a small target; verify counts, history and Undo.
- Add small/medium and Lock Screen widgets; complete in the widget, then foreground the app.
- Invoke all three App Shortcuts and test duplicate names and repeated completion.
- Test after locking/unlocking, across midnight, after a timezone change and with a stale widget.
- Test VoiceOver, large Dynamic Type and Reduce Motion.

The initial implementation was produced on Linux without Xcode or Swift. Its project-generation consistency, plist/XML parsing and whitespace checks passed, but its fourteen written core tests and native build were not executed there. The Mac verification below supersedes that native-validation status.

### Issue #3 native validation — 20 September 2026

Tracking: [#3](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/3), the first item in [the delivery roadmap](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/2).

**Tested source commit:** `3202d911b205afc0f7257df56207340368c0a071` (merged PR #1). `git fetch origin` confirmed that `HEAD` and the latest `origin/main` both pointed to this commit before verification. No application, package, project-generator or generated-project source changes were needed for the tests or compilation. This validation branch only updates evidence/documentation.

| Environment | Recorded value |
| --- | --- |
| Host | Apple Silicon, macOS 27.0 (`26A428`) |
| Xcode | 27.0, build `27A266a` |
| Swift | Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`); Swift 6 language mode |
| Simulator build SDK | iOS Simulator 27.0 (`24A430`) |
| Deployment target | iOS 18.0 |
| Build configuration | Debug, unsigned, generic iOS Simulator; arm64 and x86_64 |
| Local run time | 20 September 2026, approximately 05:27 Europe/Istanbul (02:27 UTC) |

Commands run from the repository root:

```sh
git fetch origin
git rev-parse HEAD origin/main
sw_vers
xcodebuild -version
swift --version
xcodebuild -showsdks
swift test --package-path Packages/DailyRhythmCore
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-3/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/generate_project.py --check
git diff --check
```

`-derivedDataPath` only controls the location of build artifacts; the build otherwise uses the README command. A generic build destination does not select, boot or modify a Simulator device.

| Check | Actual result |
| --- | --- |
| Existing core tests | **Passed:** 14 XCTest cases executed, zero failures, 0.089 seconds reported for the suite; command exited 0. The trailing Swift Testing runner reported zero tests because these tests use XCTest. |
| App and widget compilation | **Passed:** `DailyRhythm` and `DailyRhythmWidgets` compiled and linked for both Simulator architectures, the widget was embedded and validated, and `xcodebuild` ended with `BUILD SUCCEEDED`, exit 0. |
| Deterministic project | **Passed:** `Xcode project is up to date.`, exit 0; no regeneration necessary. |
| Whitespace check | **Passed:** `git diff --check`, exit 0. |
| Simulator launch and App Group access | **Passed with ad hoc signing:** app installed and launched on the existing iPhone 17 Pro / iOS 26.5 Simulator. The app shows the empty-state creation screen without a storage error, and `simctl get_app_container ... groups` lists the configured App Group. |
| Create a habit, terminate and relaunch | **Passed, user-assisted UI creation:** the user created the reading habit through the app. After `simctl terminate` and `simctl launch`, the same habit appeared on Today with the same UUID, targets and unchanged saved bytes. See evidence below. |

The core test run exercised recurrence, rollover/DST, timezone travel, duplicate completion, undo, full/light outcomes, archive history, fresh-store reload, invalid/corrupt/unsupported data preservation and concurrent independent stores. No compiler or test failure required a source fix or a new regression test.

The successful build did emit this diagnostic from `AppIntentsSSUTraining`:

```text
appintentsnltrainingprocessor: error: Could not archive SSU artifacts. Check build log.
** BUILD SUCCEEDED **
```

`ExtractAppIntentsMetadata` wrote `Metadata.appintents`; SSU YAML generation and copying also completed before the archive diagnostic. The build log provides no more specific failure cause. Record this as an unresolved tooling diagnostic, not proof of working Siri recognition or a clean App Shortcuts training result. Recheck discovery and invocation during [#4](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/4). No build setting was changed to suppress the diagnostic.

Local raw logs from this run are `/tmp/daily-rhythm-issue-3/swift-test.log` and `/tmp/daily-rhythm-issue-3/xcodebuild.log`. These are temporary local artifacts; the commands, environment, commit and outcomes above are the durable evidence.

#### Simulator launch follow-up

The existing, already-booted test device was **iPhone 17 Pro**, iOS **26.5 (`23F77`)**, UUID `A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6`. No Simulator was created, deleted or moved to a different runtime.

Installing the unsigned compilation artifact produced the expected storage-error UI: `Daily Rhythm cannot access its shared storage.` The app had no registered App Group container. Rebuilding with local ad hoc signing allowed Xcode to package the configured simulated App Group entitlements, and the same device then opened the normal first-habit screen. No application fallback store or entitlement/source changes were introduced.

```sh
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-3/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcrun simctl terminate A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 \
  com.lumetechllc.DailyRhythm
xcrun simctl install A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 \
  /tmp/daily-rhythm-issue-3/DerivedData/Build/Products/Debug-iphonesimulator/DailyRhythm.app
xcrun simctl launch A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 \
  com.lumetechllc.DailyRhythm
xcrun simctl get_app_container A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 \
  com.lumetechllc.DailyRhythm groups
```

The ad hoc build exited 0 with `BUILD SUCCEEDED`; launch returned a live process ID and the container query returned `group.com.lumetechllc.DailyRhythm`. The build log is `/tmp/daily-rhythm-issue-3/simulator-signed-build.log`. The README now separates unsigned compilation from an entitlement-enabled launch check. This is Simulator evidence only; physical-device App Group provisioning and widget/intent writes are not established by it.

#### Habit persistence smoke check

At approximately 05:34 Europe/Istanbul, the user performed **Try a reading habit → Create** on the existing Simulator. This was user-assisted because the Device Hub UI automation connection repeatedly returned `timeoutReached` (error -10005). No store data was seeded or edited outside the app.

Before termination, the Today screen showed **Read**, full goal **10 pages**, light goal **2 pages**, Morning, and **0/1** steps. A read-only inspection of the App Group JSON confirmed exactly one habit, UUID `B03E96F9-A02C-4DA1-B9C2-BFB2076215D6`, scheduled on all seven weekdays.

```sh
xcrun simctl terminate A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 \
  com.lumetechllc.DailyRhythm
xcrun simctl launch A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 \
  com.lumetechllc.DailyRhythm
```

Both commands exited 0; the process ID changed from `10424` to `11342`. The relaunched app displayed the same reading habit, targets and **0/1** count without a storage error. A second read-only inspection confirmed the same UUID, exactly one habit and an identical SHA-256 for the saved JSON before and after relaunch:

```text
f6f510704994b9078e80d3350e30346564b74d0fdc00f5c847dfc05bdb0d725d
```

Screenshots: [before termination](verification/issue-3/before-relaunch.png) and [after relaunch](verification/issue-3/after-relaunch.png). These are captures of the running Simulator, not mockups. The test habit remains in the app for further checks.

**CI status checked on 20 September 2026:** the [first GitHub Actions run](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/actions/runs/35479213534), for commit `b54ccc6cf26b5752390d56c9924671b57862646f`, remains `completed` / `failure`. The GitHub API returned no executed job steps, and the check annotation still says: "The job was not started because your account is locked due to a billing issue." This historical run is not a green CI result. Local Mac execution is the verification path allowed by #3; no billing changes were made.

**Closure:** all four acceptance criteria for #3 are demonstrated by the local tests, builds, user-assisted launch/persistence check and this evidence. The PR can use `Closes #3`. Physical-device signing, App Group provisioning, cross-surface writes, locked-device behaviour, Siri invocation and widget refresh are still unverified and belong to #4 and the later release gates above.
