# Issue #7 — habit and one-off management verification

Tracking: [issue #7](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/7). Behaviour: [management contract](../IMPLEMENTATION.md#habit-and-one-off-management).

**Tested implementation commit:** `5bd9678f2cd2aa33205ad2d9e5a3423ee7c4cf54`, based on `origin/main` at `937e15e` (merged PR #35). Final core tests and native compilation ran against the source/tests in this commit. Subsequent commits only record evidence unless explicitly noted below.

**Status: implementation and automated checks complete; manual form checks pending.** Use `Refs #7` until the required manual matrix is exercised. Compilation and draft-value tests do not establish successful tapping, selection, cancellation or save feedback in the actual forms.

## Environment and commands

20 September 2026, approximately 06:58–07:00 Europe/Istanbul. Apple Silicon, macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`), Swift 6.4, Swift 6 language mode. iOS deployment target 18.0; generic iOS Simulator 27.0 SDK build, arm64 and x86_64, local ad hoc signing for Simulator App Group access.

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py
python3 scripts/generate_project.py --check
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-7/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
git diff --check
```

| Check | Actual result |
| --- | --- |
| Core regressions | **53 XCTest cases passed, zero failures**, exit 0; 0.815 seconds reported test execution. Includes 44 existing tests and 9 management/draft regressions. |
| App and widget | **BUILD SUCCEEDED**, exit 0, both Simulator architectures. The generated project includes the three new SwiftUI files in the app target only. |
| Generated project / whitespace | **Passed**. Project regeneration changes source membership only. |
| Simulator smoke launch | An earlier build of this branch was installed and launched on the previously selected, already-booted iPhone 17 Pro / iOS 26.5, `A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6`. The existing Read / 10 pages / 2 pages light record appears without a storage-error banner; Today shows a date-only due label and management link. |

Logs: `/tmp/daily-rhythm-issue-7/swift-test.log`, `xcodebuild.log`, `xcodebuild-final.log`. The build emitted the pre-existing nonfatal App Intents SSU archive diagnostic and ad hoc signed-binary stripping warnings. No setting was changed to suppress them. Native compilation does not establish Siri recognition, notification scheduling or physical-device signing.

No Simulator was created, deleted, switched to another runtime or substituted. No physical-phone data was changed. The [06:59 smoke screenshot](issue-7/today-smoke.png) predates the final management-Undo refinement and year-inclusive date labels; it is a launch smoke result, not final form acceptance evidence. A read-only check of the shared JSON after launch reported v2, 1 habit and 0 records. Test data was not inserted through direct file writes.

## Executable behaviour

| Risk | Evidence |
| --- | --- |
| Selected date/time/duration survives reload | Draft creates date-only and 08:35 Asia/Tokyo one-offs for September 22 with 15-minute duration. A fresh store returns exact definitions; date-only has nil instant, timed resolves to September 21 23:35 UTC, and September 23 has no replacement occurrence. |
| Cancel and invalid form values | Mutating/validating an unsaved draft leaves the original document bytes and habit unchanged. Blank/zero/negative/fractional/overflow durations, invalid timezone and invalid date fail. UI Cancel wiring is source-reviewed but awaits manual exercise. |
| Explicit edit scope | A future revision changes tomorrow's title/target/time; an independent edit changes today's target/light/duration/due only. Fresh-store checks retain yesterday's whole summary, the original identity/denominator and tomorrow's template. Postponement remains pending and cannot complete before its new due day. |
| Exact existing timed due retained | Editing a target retains an occurrence's second DST-fold instant, seconds and fractional seconds. Changing the time uses the model's documented first-fold rule; clearing time produces an explicit date-only value. |
| Civil dates and DST | Civil-date selection round-trips as a Gregorian date key. New York's nonexistent 02:30 resolves through the same core conversion to 03:00, with no new UI-specific DST implementation. |
| Overdue one-off management | A September 20 one-off is still retrievable in October, with the same ID and overdue/pending status. Completion remains on September 20 in history, does not generate an October occurrence and removes overdue status. |
| Bounded recurring agenda | The next seven dates include an earlier explicitly postponed pending step once, without adding every missed recurring day or writing the store. Earlier steps completed in the window remain visible for Reopen; Undo retains the original due/identity. |
| Archive/restore and Free capacity | Archived plans have no new pending steps in the excluded window. At three active habits, restore fails without changing bytes. After freeing a slot, a later restore resumes only on the restore date and preserves the gap. Existing #5/#6 regression suites also pass. |

`canComplete` is shared by the core mutation guard and the management/Today UI. Due and overdue are never completion outcomes. Ordinary Shortcut creation remains recurring/date-only; management adds no unofficial Siri schema or notification claim.

## Manual UI matrix

Native UI automation could not attach: Simulator name/path lookup reported `Invalid app`; the installed **Device Hub** (`com.apple.dt.Devices`) was found in the application inventory, but attachment returned `Computer Use server error -10005: timeoutReached`. Simulator install/launch/screenshot commands still worked. The user was asked to perform the first one-off creation on the existing test Simulator. No response/result is assumed.

| Case | Procedure | Result |
| --- | --- | --- |
| One-off creation | Plus → One-off task → Call test / One call; today, due time off → Create. Verify one planned occurrence and date-only display. | **Pending user interaction.** |
| Occurrence edit | Habits → Call test → Edit this step; set a new target, 15-minute duration, tomorrow's due date and an explicit time/timezone. Save and inspect the selected values. | **Pending.** |
| Future edit | Read → Edit future plan; tomorrow, new normal/light goals, selected weekdays and due time. Today remains unchanged; Scheduled changes and tomorrow's step show the new values. | **Pending.** |
| Cancellation and validation | Change an existing form and Cancel; reopen and compare. Attempt blank target/invalid duration, dismiss the error, confirm input retained and no store mutation. | **Pending.** |
| Archive and restore | Archive a test plan, open it under Archived, Restore and compare steps. Try restore at Free capacity and verify the error with no partial activation. | **Pending.** |
| Process relaunch | After successful UI creation/editing, terminate and launch on the same Simulator; compare persisted IDs, definitions, overrides and displayed values. | **Pending.** |

Do not close #7 or mark these rows passed from core tests alone. Additional source edits after UI testing must be assessed against the affected rows. Accessibility, notification delivery, broader widget UX and official Siri schemas remain their separate roadmap items.
