# Issue #8 — day-action verification

Tracking: [#8](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/8). Contract: [model v3](../MODEL-V3.md).

**Tested implementation:** `14da9299d85102e7392256a0256a6dac196d412c`, based on merged PR #36 (`51e1ca7`). Following changes in this branch only record documentation and the smoke screenshot.

**Status:** implementation, core regressions, native builds and launch smoke passed. Interactive Today/Undo and widget walkthroughs remain unverified because Device Hub automation still cannot attach. Use **Refs #8**, leaving the issue open for those checks rather than treating core tests as device evidence.

## Environment and actual checks

20 September 2026. Apple Silicon, macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`), Swift 6.4 / Swift 6 mode. Deployment target iOS 18.0. Generic iOS Simulator 27.0 SDK, arm64 and x86_64. The final Simulator build used local ad hoc signing for App Group access.

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py --check
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-8/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
git diff --check
```

- **69 XCTest cases passed, zero failures**, 0.540 seconds total. This includes 53 existing regressions and 16 new day-action/migration tests.
- App and widget: **BUILD SUCCEEDED**, unsigned and final ad hoc signed builds. Generated project already current; no target source membership change needed for package files. Whitespace check passed.
- Final build installed/launched on the previously selected iPhone 17 Pro / iOS 26.5 (`A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6`). [Actual launch screenshot](issue-8/today-smoke.png) shows Light Day off, full/light/skipped counts, and the existing Read habit at 0/1 without a storage error.
- Read-only inspection after app launch found version 3, one existing habit, zero records, and the preserved `.v2-backup`. No test records were seeded or store files edited in the Simulator.

Logs: `/tmp/daily-rhythm-issue-8/tests.log`, `build.log`, `signed-build.log`, `final-build.log`. The first unsigned build emitted the previously known App Intents SSU archive diagnostic despite BUILD SUCCEEDED. Ad hoc builds emitted signed-binary stripping warnings. No suppression setting was added; Siri recognition is not established by compilation.

## Behavioural evidence

| Risk | Executed evidence |
| --- | --- |
| Outcome separation | Four one-offs retain full, light, skipped and pending after reload; counts 1/1/1/1 with only two completions. Skip has no completion timestamp and survives archive/history. Repeated completion cannot overwrite skip. |
| Undo and competing surfaces | Undo restores exact prior due/targets once. Identical completion after reopen has a fresh revision; an old Undo or Reopen revision is rejected. Twenty competing actions have one winner; twenty undo attempts also have one winner. |
| Ordering and Later | Equal anchors sort by stable ID, earlier saved timed due precedes a later day part, day part breaks equal instants. Later moves only its exact ID, retains its target and becomes ready at the saved instant. |
| Midnight and history | September 20's 23:30 Later carries the same ID into September 21 at 00:30; completion updates September 20 only. Yesterday's ordinary unrecorded recurring identity cannot be acted on as today's step. |
| Travel and DST | Tokyo-anchored deferral retains its instant after travel to Los Angeles. One-hour Later across the repeated DST hour remains exactly one hour. A date skipped entirely by Pacific/Apia does not crash agenda ordering or change identity. |
| Light Day | Persisted mode survives reload, ends at civil-day rollover, rejects an old day/revision, toggles off explicitly and leaves all template/occurrence targets unchanged. Missing small target is rejected, never manufactured. |
| Carryovers | An overdue one-off remains visible with its original ID; missed recurring days are not created as backlog. |
| Upgrade and failure | V2 light-completion snapshot/source/timestamp preserved with exact backup; v4 rejected without replacement. Failed migration save preserves original/backup; unfamiliar v2 fields fail. Failed action save preserves the prior bytes. |

## Remaining manual checks

The fresh attempt to attach `com.apple.dt.Devices` again returned **Computer Use server error -10005: timeoutReached**. Install/launch/screenshot through `simctl` worked; no alternate Simulator, runtime installation or UI-event workaround was used.

Pending: tap Later/Skip Today/Undo and Light Day on Today; inspect missing-small-target editing, History and each widget family; exercise old rendered widget buttons after an intervening app edit; VoiceOver and large-text layout. These are not marked passed. The source includes explicit widget revision parameters and deadline timeline entries, but system refresh latency and AppIntent re-resolution require device exercise. Physical-device Siri/signing remain separate roadmap gates.
