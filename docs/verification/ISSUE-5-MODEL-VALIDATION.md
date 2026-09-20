# Issue #5 — versioned model verification

Tracking: [issue #5](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/5). Model rules and recovery: [MODEL-V2.md](../MODEL-V2.md).

**Tested implementation commit:** `444caa4f2babc034be58412c7697517ee39dae5f`, based on `origin/main` at `23fdfeb63cbd368de7d5735c719efcb12a00825a` (includes merged PR #33). This evidence file is a documentation-only follow-up to the tested implementation.

## Environment and commands

20 September 2026, Apple Silicon Mac, macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`), Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, clang `2100.3.34.1`), Swift 6 language mode, iOS deployment target 18.0. Native build: unsigned generic iOS Simulator 27.0 SDK, arm64 and x86_64.

```sh
swift test --package-path Packages/DailyRhythmCore
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-5/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/generate_project.py --check
git diff --check
```

No Simulator device was selected, created, deleted, booted or assigned a different runtime. The v2 build was not installed on the physical phone and did not migrate its data.

## Results

| Check | Actual result |
| --- | --- |
| Core regressions | **32 XCTest cases passed, 0 failures**: original 14 plus 18 v2 tests. Final suite reported 0.583 seconds of tests; command exit 0. |
| App and widget | **BUILD SUCCEEDED**, exit 0. Both Simulator architectures compiled/linked with the new core model and dedicated widget completion intent. |
| App Intents metadata | Both app and extension `extract.actionsdata` contain discoverable `CompleteOccurrenceIntent` and `CompleteWidgetOccurrenceIntent` with `isDiscoverable: false`. This verifies extraction, not device invocation. |
| Project generation | **Passed**, `Xcode project is up to date.` New source membership is confined to the Swift package, so no Xcode project regeneration was needed. |
| Diff whitespace | **Passed**. |

Local raw logs: `/tmp/daily-rhythm-issue-5/swift-test.log`, `/tmp/daily-rhythm-issue-5/xcodebuild-final.log`. The first full build from this work also succeeded, but emitted the existing nonfatal `appintentsnltrainingprocessor: error: Could not archive SSU artifacts. Check build log.` diagnostic (`xcodebuild.log`). The final incremental build after rebasing onto current main reported no such diagnostic. No setting was changed to suppress it; the incremental result does not establish that the full-build tooling problem is fixed.

## Acceptance evidence

| Criterion | Evidence |
| --- | --- |
| Lossless v1 migration | Checked-in empty and mixed v1 JSON fixtures. Mixed fixture includes same-name habits, selected weekdays, an archived habit, full/light completions, a reopened pending record and fractional timestamps. Tests compare every original habit/record field, IDs, counts, and exact backup bytes. No duration, due time, source or old revision timestamp is invented. |
| Preserve bytes on failure | Tests cover malformed/unknown versions, unknown v1 fields, invalid schedules, inconsistent snapshots, orphan archive metadata, duplicate records, failure of the requested mutation before migration, save failure, conflicting pre-existing backup, and retry. A failed v2 completion save also retains the pending original file. Save failures use a deterministic injected disk-write error, not an actual exhausted device. |
| One-off and date-only distinction | Tests verify exactly one occurrence, nil due instant for date-only, optional numeric duration, overdue date boundaries, late completion and no new occurrence on completion/postponement dates. |
| Immutable planned/completed history | Tests edit all future schedule/target fields, compare earlier full summaries including never-completed dates, reopen/recomplete an old snapshot with its original light target, and complete a previously unrecorded old day. Today's/past edits and recurrence-kind changes fail without mutation. |
| Stable occurrence overrides | Repeated same-day time changes and cross-day postponement retain ID and original denominator. Retries retain the first completion's source/timestamp. Completed and historical target edits are rejected. Explicit pending overrides survive later weekday removal and can clear optional fields. |
| Archive gaps | Two archive/restore cycles retain their gaps. Restore does not resurrect a one-off whose planned date was excluded. Existing tests retain completed archive-day records and now also verify repeated reopen after that record becomes hidden. |
| DST and travel | Tests cover date-only 23/25-hour days, New York missing 02:30 → 03:00, the first occurrence of repeated 01:30, no duplicate completion, fixed timed deadlines during Tokyo → LA travel, unchanged floating date-only keys and rejection of backward archive/edit mutations. |
| Concurrency | Independent store instances race 30 creations and 40 completions; another test races 20 first-use migrations/additions/completions and checks the single exact v1 backup. A further test races 30 future edits/completions and verifies the original target snapshot and one completion. These are real file/lock transactions across independent instances in one process. |
| Supported rules documented | `MODEL-V2.md` records recurrence limits, effective revisions, exact identity, snapshot precedence, overdue/postponement behavior, archive intervals, DST/timezone choices, source attribution and recovery. |

## Scope and limits

The model acceptance criteria are covered by executable core tests, source review and native compilation. No new hardware-dependent acceptance criterion is required by #5. This evidence does not claim a physical-device schema upgrade, real cross-process device race, new widget-intent invocation, notification scheduling, or Siri AI schema support. Existing physical-device results remain in the separate [issue #4 matrix](ISSUE-4-DEVICE-VALIDATION.md).

The current UI and ordinary creation Shortcut still use repeating date-only habits. New one-off/timed/editing API support is ready for the subsequent UI and Siri roadmap issues; historical summaries intentionally remain grouped by original planned date. The App Intents SSU tooling diagnostic remains a follow-up limitation, and GitHub CI results must be assessed separately from these successful local checks.
