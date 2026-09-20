# Issue #14 — Optional local notifications

Tracking: [#14](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/14). **Refs #14**: implementation and automated checks pass; the physical-device delivery and interaction matrix is not yet complete.

**Tested implementation:** `96fa1a90927d8a0f787a50790dda895161256858`, based on main `5f55a9d` (PR #45). Documentation-only changes follow this commit.

## Behaviour

- Both feature switches default off. Habits → Notifications requests alert/sound permission only after the user enables a switch. Permission is not requested at launch, during tracking, or from an extension. Denied/revoked permission retains preferences, schedules nothing and leaves manual tracking available.
- Preferences are a validated versioned JSON file in the existing App Group. Field-level changes reload under a separate cross-process advisory lock, avoiding lost updates between app/extension instances. Lock acquisition suspends in short intervals and fails after ten seconds; the lock is never held during a permission prompt. Habit data retains its existing transaction lock and file format.
- The plan covers the remainder of today plus the next six Gregorian civil dates, with at most 56 future, non-repeating requests. Daily Close slots are reserved; earliest timed steps fill remaining capacity. Stable IDs use `daily-rhythm.notification.close.<day>` and `daily-rhythm.notification.step.<occurrence>`.
- Timed reminders require an unresolved, active plan and a future due instant. Date-only work is silent. Later and older saved pending overrides keep their original occurrence identity. Completed/skipped/archived steps are removed, future edits replace changed due instants, and reopening/Undo/restoring can restore an eligible reminder.
- Timed steps retain saved timezone/instant semantics. Daily Close is recomputed at its chosen current-local wall time on each refresh. DST gaps advance to the next valid time and folds choose the first instant. UTC calendar trigger components preserve the computed instant; whole-second rounding never moves a reminder earlier.
- Reconciliation compares actual pending requests and removes only the owned prefix. Unchanged requests are not re-added. It runs on app refresh/mutations, foreground/significant-time changes, ordinary intents, widget/control completion and the opt-in schema mutation paths. It also clears owned delivered notices at every opportunity to avoid retaining stale prompts. Unrelated notifications are preserved.
- After acquiring the queue lock, unreadable source data or a partial scheduling failure clears owned pending/delivered requests, preserves source bytes and exposes an error/retry in app settings. An already-saved habit action remains successful. A lock-acquisition failure cannot safely modify the other holder's queue and instead reports retry.
- Copy is neutral and contains no habit titles, targets or exact completion totals. Tapping validates the original day or occurrence URL, resets navigation and reads fresh saved state in a read-only review. A missing/archived identity never substitutes another step or completes anything. Foreground banners are suppressed because the app already shows saved state.
- No push service, network, AI generation or exact background wake is used. The seven-day window can expire without another execution opportunity. Travel/edits may leave an already-scheduled notice stale until the next opportunity; iOS controls Focus, summaries and actual delivery timing.

## Executed checks — 20 September 2026

Environment: macOS arm64, Xcode **27.0 (27A266a)**, Swift **6.4**, iOS deployment target **18.0**. Physical signing inherits **LumeTech L.L.C. (`U54BLJMYG6`)** from the project generator for both app and widget.

| Check | Actual result |
| --- | --- |
| Core suite | **115 tests passed**, zero failures, including 12 new notification tests. |
| Defaults / denied / revoked / independent opt-out | Injected client/clock checks passed; tracking remains writable and unrelated OS request IDs are preserved. |
| Repeat, completion, reopen, Later, Undo, skip, edit, archive | Stable request and exact-identity checks passed. These are core/client tests, not OS dispatch tests. |
| Queue bound, no date-only reminders, older Later | Passed; plan computation leaves current-version habit bytes unchanged. |
| Travel and DST | UTC → Tokyo preserves timed instants and changes close time; Los Angeles spring gap/fall fold cases passed. |
| Concurrent coordinator instances / opt-out race | Passed with suspended client calls while another coordinator competes for the same lock. This is process-local test execution of the file-lock protocol, not proof of extension OS scope. |
| Partial scheduling failure / corrupt preferences/store | Passed: owned queue cleared, original corrupt bytes retained, retry and opt-out behaviour verified. |
| URL routing | Exact round trips and malformed/ambiguous-link rejection passed. Native notification-tap dispatch still needs device evidence. |
| Generated project and whitespace | `python3 scripts/generate_project.py --check` and `git diff --check` passed. |
| Signed default app/widget build | `BUILD SUCCEEDED`; strict deep code-signature verification passed, team `U54BLJMYG6`. |
| Opt-in Siri schema app/widget build | `BUILD SUCCEEDED` with `DAILY_RHYTHM_SCHEMA_SPIKE`; known nonfatal `Could not archive SSU artifacts` diagnostic remains. No Siri recognition fix or new capability claim. |
| Physical-device install/launch | Opt-in build installed and launched successfully on the existing **XREI-0001, iPhone 16, iOS 27.0 (24A437)** after the user reconnected it. No Simulator was started, selected, reset, created or deleted. |

Commands (the schema build uses the same source with the existing opt-in flag):

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py --check
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daily-rhythm-issue-14/DerivedData build
codesign --verify --deep --strict --verbose=2 \
  /tmp/daily-rhythm-issue-14/DerivedData/Build/Products/Debug-iphoneos/DailyRhythm.app
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daily-rhythm-issue-14/SchemaDerivedData \
  'OTHER_SWIFT_FLAGS=$(inherited) -DDAILY_RHYTHM_SCHEMA_SPIKE' build
```

Local logs: `/tmp/daily-rhythm-issue-14-tests.log`, `/tmp/daily-rhythm-issue-14-build.log`, `/tmp/daily-rhythm-issue-14-schema-build.log`. These are temporary artifacts; commands, commit and outcomes here are the durable record.

## Physical-device checks still open

Device Hub UI access returned `timeoutReached`, so installation/launch was checked through `devicectl`. The user was given a focused walkthrough on the reconnected iPhone 16: enable Daily Close, allow permission, choose a time roughly two minutes ahead, leave the app, then tap the delivered notice and check today's Saved review. Delivery is not inferred from installation, a source inspection or mock results.

- Record the actual contextual permission prompt, grant and deny paths; revoke in iOS Settings and return to verify the explanatory state and zero owned requests. Do not reset the user's notification permissions or app data to manufacture a fresh-install test.
- Confirm a real background Daily Close notification arrives with neutral copy and opens its exact saved date, including a cold launch. Record the result of the walkthrough above.
- Schedule a controlled timed occurrence; complete/skip/archive or change its time before delivery and inspect the actual system pending queue. Reopen and verify no duplicates. Repeat through a real widget, configured Control and ordinary Shortcut to establish extension/container notification scope.
- Tap an older delivered occurrence after its state changes. It must show current saved results for that identity, or the explicit unavailable state, with no mutation and no substitute occurrence.
- Exercise device timezone travel, DST, offline delivery, large text/light/dark settings, and notification taps while another sheet or tab is open. Core DST tests do not establish device delivery.

Until these rows are recorded, #14 remains open and this work is not release-readiness evidence.

API references: Apple's [contextual permission guidance](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications), [local scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) and [notification response handling](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions).
