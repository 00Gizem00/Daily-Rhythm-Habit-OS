# Issue #20 — optional local pilot diagnostics

Date: 20 September 2026. Refs #20; **the issue remains open** for the UI and system-surface checks below. No phone connection, new Simulator or runtime change was needed.

## Behaviour and definitions

Observation is off by default. Users can opt in from the first setup screen or Habits → Data & Privacy, export diagnostics JSON explicitly, or turn observation off and delete its local records. There is no network client, automatic upload, account or remote analytics service.

| Field/event | Meaning |
| --- | --- |
| Completion | First successfully saved full/light transition for each occurrence during the observation. No event is written before the routine save succeeds. Repeated requests, Undo and later recompletion do not add a second event for an observed occurrence. Undo does not remove a past observation; this is not the current progress total. |
| Baseline | Already-completed records when opting in; excluded from pilot activation. Legacy nil provenance is counted as unknown. Opt-in reads old stores without migrating them. Backup restoration itself emits no completion event. |
| Source | App, widget, App Intent or unknown. **App Intent is not a verified Siri count**: Siri, Shortcuts, configured controls and the opt-in schema adapter share this entry point. No source is inferred from habit content or device identity. |
| Setup timing | First onboarding/manual-create opening after opting in while the store has no plans. Opening onboarding and then opting in starts timing at opt-in. Missing start/timing is unknown, not zero. The first saved completion ends the interval. |
| Completion day | Relative 1-based civil day in the timezone captured at opt-in, based on the saved completion instant. This can differ from an overdue step's planned day. Device clock accuracy is assumed; wall-clock changes can affect timing/day interpretation. |
| Day 7 / day 14 | `awaiting` until the respective civil day ends; then `completionObserved` or `noCompletionObserved`. This describes local observations, not verified engagement or retention. |
| Failure | A failed app/widget/intent mutation attempt reduced to staleAction, unavailableStep, validation, capacity, storage or other. Repeated failures may count again. No localized description, file path or user text is saved. |
| Coverage flags | `bestEffort: true` always; `capacityReached` identifies a reached local limit. An interrupted/failed diagnostic write may omit an event after the routine write has already succeeded. |

The separate local sidecar holds observation-start/setup instants, the observation timezone and at most 10,000 occurrence keys for deduplication. These do **not** leave the sidecar in diagnostic export. Export contains only relative days, count buckets, available elapsed setup seconds, flags and definitions; no habit titles, goals, prompts, exact timestamps, local IDs or timezone identifier. Failure buckets are bounded by 30 days × four surfaces × six categories, with at most 10,000 attempts per bucket. Reads are capped at 2 MB and reject malformed/unsupported metadata.

Observation expires at the start of civil day 31. The next app refresh or diagnostics access removes it; this is not a guaranteed background deletion at a particular instant. Opt-out deletes it immediately when storage permits. Re-enabling starts a fresh baseline. The same store lock and generation checks govern reads, writes and export, and final local erasure removes observation before releasing the pending marker. An interrupted erase remains retryable. Normal JSON/CSV routine backups exclude diagnostics; external copies explicitly saved/shared by users are outside app erasure.

Failures before a usable shared store exists cannot be logged. OS entity resolution, system permission/routing failures before adapter invocation, notification delivery and form validation before a mutation are outside these buckets. There are no PCC availability/generation/edit/apply events because that feature does not exist. No physical haptic, Siri routing or WidgetKit refresh result is implied by a count.

## Executed checks

Tested source commit: **`8ebf4ce107b826bbfb290b2edfacffd254c082a5`**. Both native runs compiled a working tree based on `a8b3aefeb7ed615510967599d0533ffa7af7c4e7`; every changed production/core-test Swift file in those fixture copies matches the tested commit byte-for-byte. [Source hashes and isolation outcomes](issue-20/source-verification.json) retain that distinction.

| Check | Actual result |
| --- | --- |
| Core suite | **148 XCTest cases passed**, zero failures; 17 new diagnostics tests. Final run 18:02:34 TRT. |
| Deduplication and source | Concurrent/repeated completion, Undo/recomplete, all four source buckets, unknown legacy baseline and restore exclusion passed. |
| Retention and failures | Civil-day checkpoints and expiry across New York DST, opt-out/restart, injected routine/diagnostic write failures, corrupt/future metadata, export failure, capacity and erase/retry/stale-writer cases passed. |
| Native diagnostics suite | **27 checks passed** on the existing iPhone 17 Pro / iOS 26.5 (`A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6`). Actual app models and direct widget/ordinary intent adapters, not OS dispatch. |
| Exported content | The actual staged diagnostics file matched the aggregate export; cancellation/error callbacks cleaned the temporary file and preserved routine/diagnostic bytes. A [sample export](issue-20/sample-export.json) records the observed aggregate fields. |
| Privacy regression | **31 checks passed** through real app services in a separate disposable app, including restore, export, lifecycle and erase cleanup. |
| Isolation/persistence | Both normal cold launches preserved routine bytes; original product store/lifecycle/migration-backup/diagnostics hashes remained unchanged; both unique test apps were removed. The user's backup file was not read or modified. |
| Native builds | Default app/widget and opt-in `DAILY_RHYTHM_SCHEMA_SPIKE` Simulator builds succeeded with Xcode 27.0 (`27A266a`). The opt-in build compiled the changed schema adapters and exported App Intents metadata. |
| Xcode session | Project closed/reopened after generation, preserving **Any iOS Device (arm64)**. Actual Xcode **Build Succeeded at 18:03 TRT**. No connected device required. |
| Membership/whitespace | Project generation, `--check` and `git diff --check` passed. New core files use SwiftPM discovery; the generated project did not change. All target guards and script sandboxing remain enabled. |

Evidence: [diagnostics result](issue-20/diagnostics-result.json), [privacy result](issue-20/privacy-result.json), [native helper](issue-20/PilotValidation.swift). The helper stays outside production source membership and runs only when copied into a uniquely identified fixture app/App Group with an explicit environment flag. It does not inject UI events. Core tests use temporary stores; no existing personal data is erased.

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py
python3 scripts/generate_project.py --check
python3 scripts/validate_privacy_simulator.py \
  --device A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 --suite diagnostics
python3 scripts/validate_privacy_simulator.py \
  --device A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 --suite privacy
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'id=A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6' \
  -derivedDataPath /tmp/daily-rhythm-issue-20-schema/DerivedData \
  OTHER_SWIFT_FLAGS='$(inherited) -DDAILY_RHYTHM_SCHEMA_SPIKE' \
  CODE_SIGNING_ALLOWED=NO build
```

The successful builds still log the previously observed nonfatal `Could not archive SSU artifacts` diagnostic. It was not suppressed and does not prove Siri training. Local logs: `/tmp/daily-rhythm-issue-20-core.log`, `daily-rhythm-issue-20-native.log`, `daily-rhythm-issue-20-privacy.log`, `daily-rhythm-issue-20-schema.log` (all under `/tmp`).

## Remaining acceptance checks — open

Device Hub (`com.apple.dt.Devices`) again returned computer-use timeout `-10005`; Xcode itself remained accessible. The user has said the phone will not be connected. Consequently:

- [ ] Navigate the opt-in controls with real taps and VoiceOver, including largest text sizes and the corrupt-observation recovery message.
- [ ] Open the actual diagnostic system share sheet, cancel it and save a file through a share destination. Current evidence verifies real staging plus model callbacks, not sheet interaction or delivery.
- [ ] Verify observation from real widget/Siri/Shortcuts/control dispatch; preserve the combined App Intent label even after those checks. Do not interpret direct adapter calls as a Siri usage measurement.
- [ ] Conduct the real 7/14-day pilot; deterministic clock tests prove arithmetic only.

Earlier notification, accessibility, widget and device-recovery gates remain open. No TestFlight upload, tester contact, billing change or recovery of the disconnected phone was performed.
