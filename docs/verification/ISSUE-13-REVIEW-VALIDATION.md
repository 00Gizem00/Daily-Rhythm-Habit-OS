# Issue #13 — Daily Close and weekly rhythm

Tracking: [#13](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/13). **Refs #13**: core behaviour and compilation pass; appearance and interactive accessibility checks remain open.

**Tested implementation:** `fa5435c43bd853f4202ef08bad747b41975778c5`, based on main `154f21b` (merged PR #43). Later changes in this PR record documentation only.

## Behaviour and denominators

- `RoutineStore.review(at:)` returns the agenda, all habit snapshots, seven civil days through today, and tomorrow's original plan in one locked read. `AppModel.refresh()` uses this result after mutations, Undo, foreground activation, significant time changes and its existing refresh timer. Read failures retain the last successful state and the existing error banner.
- Daily Close appears in Today and History. It says **Today so far**, shows full, light, skipped and remaining counts, and does not claim the day is permanently closed. It distinguishes an off-day, every step completed, and no remaining work with skips.
- The weekly view stays Free and offline. Each day tile has explicit symbols and counts plus an equivalent accessibility summary; expandable day details retain titles and targets. Accessibility text sizes use a single column. There are no streaks or inferred success rates.
- The denominator is the number of original planned occurrences, not the number of active habits multiplied by seven. Full + light + skipped + remaining always equals planned. Only full + light is completed. Zero-plan days add zero; they do not count as successes or failures.
- Effective schedule revisions apply from their saved date. Pending work in archive gaps is excluded; saved full/light/skipped outcomes are retained. Explicit pending overrides retain the existing model's pinned-occurrence semantics.
- A one-off counts once on its original planned day. Deferral and late completion do not move its identity, increase today's denominator or duplicate it in history. An earlier step completed today changes the earlier day's result, while the agenda can still show the carried step.
- **Planned for later** is a subset of remaining: an unresolved step with a future due instant/date or an unexpired Later deadline. Future work is not labeled missed. Today's elapsed pending work says Remaining; earlier elapsed pending work says Not recorded. Future dates outside the seven-day window are excluded from weekly totals.
- Tomorrow's preview uses the next Gregorian civil date, including DST, and that day's effective targets and exact identities. It selects an unresolved item from the original tomorrow plan whose saved due civil date is tomorrow, ordered by the existing due-time/day-part/stable-ID rules. It does not include old carryovers or items moved to later dates. The due value remains visible and date-only ordering anchors are never presented as due times.
- A review creates no occurrence or completion records. On current-version stores it leaves data bytes unchanged; an empty store does not acquire a data file. The existing lossless legacy migration rules still apply to reads of older versions.

## Executed checks — 20 September 2026

Environment: Apple Silicon, macOS 27.0, Xcode 27.0 (`27A266a`), Swift 6.4 / Swift 6 language mode. The Xcode UI explicitly showed **GameCatch iPad Pro 13** as the active run destination. Builds use that existing iOS 27 Simulator (`EEBC0A84-C715-4D00-9D2B-84C043A6C314`); the app's minimum remains iOS 18. No simulator was substituted, created, deleted or moved to another runtime.

| Check | Actual result |
| --- | --- |
| Core suite | **103 XCTest cases passed, zero failures**, including eight new review tests. Suite duration 3.907 seconds. |
| Mixed outcomes | 22 planned = 1 full + 1 light + 1 skipped + 19 remaining. One deferred one-off stays in today's four-step denominator and in Planned for later, not tomorrow's plan. |
| Schedule/archive/one-off fixture | Daily totals `[2, 2, 1, 0, 1, 1, 1]`, eight planned, one completed; an archived completed result remains and archive gaps add nothing. |
| Late Undo and completion | Light completion on the original day is undone six days later; a subsequent full completion updates only the original day's total. Today remains an off-day. |
| Tomorrow preview | Uses effective revised target and early saved due time; excludes carryovers and an occurrence moved beyond tomorrow. Saved overrides survive schedule removal. No records are inserted and repeated review preserves the saved bytes. |
| Off-days / all done / Later | Empty review returns seven off-days with no data file; resolved work never counts as Planned for later; Later drops from that subset at its exact deadline. |
| Calendar | Spring and fall Los Angeles DST cases and Tokyo civil-day selection preserve seven unique days and the correct tomorrow. |
| App and widget build | **BUILD SUCCEEDED** with ad hoc Simulator signing. Final incremental build after the civil-date-label adjustment also passed. |
| Project / whitespace | `python3 scripts/generate_project.py --check` and `git diff --check` passed. |

The initial build emitted the previously known App Intents training diagnostic `Could not archive SSU artifacts` while ending successfully. This work does not claim a Siri training fix.

Commands:

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py --check
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=EEBC0A84-C715-4D00-9D2B-84C043A6C314' \
  -derivedDataPath /tmp/daily-rhythm-issue-13/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
git diff --check
```

Local logs: `/tmp/daily-rhythm-issue-13-tests.log` and `/tmp/daily-rhythm-issue-13-build.log`. These temporary paths are not durable evidence attachments.

## Remaining verification

Device Hub (`com.apple.dt.Devices`) returned `-10005: timeoutReached` on both connection attempts. Installation on the selected Simulator did not return after several minutes and the owned install command was terminated. A screenshot showed a blank white surface with a spinner; it does **not** demonstrate a successful launch of this build or a defect in these views. A temporary SwiftUI ImageRenderer fixture executable compiled, but Simulator spawn timed out; no appearance-render evidence is claimed. No runtime or simulator was reset or switched to bypass the failure.

Before closing #13:

1. Visually inspect Today and History in light and dark modes, including long titles, empty/off-day, full/light/skip and all-done states.
2. Inspect large Dynamic Type and VoiceOver on the weekly tiles, text totals and expanded details. Confirm no truncation, colour-only distinction or unreachable content.
3. On the live app, complete, skip, Later and Undo, then change a future plan and archive/restore. Confirm both screens refresh and tomorrow's preview changes without creating records.

The automated acceptance assertions pass; these pending appearance and interaction checks keep **#13 open**. No TestFlight or production release is performed.
