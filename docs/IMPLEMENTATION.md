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

The core now uses version 3 of the JSON model, with one-off or weekly recurrence, distinct date-only/timed due values, optional numeric durations, effective-dated revisions, occurrence overrides and archive/restore intervals. The creation/management screens expose these options; ordinary creation Shortcuts still use repeating, date-only options. See [MODEL-V2.md](MODEL-V2.md) for scheduling rules and [MODEL-V3.md](MODEL-V3.md) for day actions, revisions and migration recovery.

Occurrence identity remains the habit UUID plus its original planned civil date. Postponing changes its due value without moving the historical denominator. Future edits select a new effective revision and preserve previous planned days, including those never completed. Saved completions own their target snapshots; first completion retains its outcome, timestamp and source until explicitly reopened. Migrated records have unknown source.

Every reader/writer acquires a POSIX advisory lock on a separate stable lock file, reloads the latest JSON and atomically replaces it only after successful validation. The first successful v1/v2 operation uses that same lock to preserve an exact `.v1-backup`/`.v2-backup` before migrating to v3. Unknown versions, invalid records and read/write failures never trigger an empty-store replacement. App, widget and intents must all use `RoutineStore`.

Date-only keys follow Gregorian civil dates. Timed schedules explicitly retain their timezone, resolve DST gaps to the next valid time and repeated times to the first instant. Travel never changes saved IDs or completion dates. Calendar-based history arithmetic handles 23/25-hour days. See the model document for overdue work, postponement and archive boundaries.

The first implementation is for small personal habit sets. Whole-file JSON transactions avoid a database dependency; benchmark and migrate before adding large imports or long histories. UI refreshes on foregrounding and periodically while active. Widget reload requests remain subject to WidgetKit scheduling.

## Free activation policy

`RoutineStore` defaults to Free: at most **three active recurring habits**. The count includes every unarchived weekly template, even on a day it is not scheduled or after today's occurrence is completed. One-off tasks and archived habits do not consume slots. Recurrence kind cannot be changed to bypass the limit; future schedule edits keep the same slot.

Both `addHabit` overloads delegate to the atomic `addHabits` batch API. Single and batch `restore` use the same activation policy. The store rereads the current document, counts existing/requested recurring habits and samples `HabitEntitlementProvider` while holding the existing file lock, before any save. A batch that exceeds capacity or fails validation saves nothing. Restoring an already-active habit is a no-op; repeated IDs in a restore batch count once. Empty requests leave current-version bytes unchanged; an older file still migrates on its first successful operation. Repeated creation requests still create distinct habits if capacity permits; proposal-level Apply idempotency belongs to #18.

`SharedRoutineStore.makeStore()` supplies `FreeHabitEntitlementProvider` to the app, widget and ordinary App Intents. The future verified StoreKit adapter belongs at this shared composition point and must provide a quick, thread-safe local snapshot, refreshed across processes. It must resolve unverified/unknown/expired access to Free and must not reenter the store while its lock is held. No production Pro switch, persisted entitlement flag, network call or paywall is added here. Tests alone provide deterministic Pro/downgrade fixtures.

Existing stores above the cap remain valid, including v1 migrations and a future Pro downgrade. Reading, completion, undo, history, existing-habit edits, archiving and export do not query entitlements. No habits are deleted or automatically archived. New recurring creation/restoration is refused until the resulting active count fits; one-offs remain available while over capacity. New schemas and proposal Apply must use these store APIs rather than count/loop/save independently.

The creation form explains the Free limit before submission and keeps entered values on failure. The store returns one English `activeHabitLimitReached` error for app and Shortcuts callers, without a success response or widget reload from the failing creation path. [Issue #6 verification](verification/ISSUE-6-FREE-POLICY-VALIDATION.md) records the executable checks and integration boundaries.

## Habit and one-off management

The existing creation form switches between recurring habits and one-off tasks, with explicit civil dates, optional due times in a named timezone, normal/light targets and an optional positive whole-minute duration. A due time schedules a notification only when the user has enabled timed-step reminders and granted permission. `HabitFormDraft` is an unsaved value: field changes, validation and Cancel do not write. Only Create/Save call the normal transaction service. Invalid values and capacity failures retain the form input and report the underlying English error.

Habits rows open a management screen for active or archived plans. **Edit future plan** saves a complete effective-dated revision strictly after today; scheduled revisions are visible and individually editable. Recurrence type stays fixed. A future one-off can edit its definition up to its original planned date. **Edit this step** changes only the selected pending occurrence's targets, optional duration and due value. For an earlier planned day, only due changes are exposed; its historical targets stay intact. Completed steps require Reopen before editing. Moving a one-off's due date never creates a replacement occurrence or changes its history date.

Civil-date pickers use Gregorian UTC to preserve the chosen date string independently of device timezone. Time pickers collect wall-clock hour/minute separately from the named timezone. Conversion reuses the core DST rules. An unchanged occurrence due selection retains the original exact instant, including seconds/subseconds and a repeated-hour selection, when editing a target.

`managedOccurrences` reads a one-off at its original identity even when overdue or completed. For recurring habits it reads the next seven planned civil dates plus earlier saved pending steps and earlier steps completed within that window (so Undo remains accessible). It does not generate every unrecorded missed recurring day as catch-up work or write future occurrences. Due and overdue labels are separate from full/light completion. Today's Next Up excludes postponed steps whose due day has not arrived; the empty eligible state does not claim that those pending steps are complete.

Archive and Restore use the existing history-preserving, capacity-checked commands. Archive stops pending work from the archive date forward; Restore cannot fill an older archived gap, including a missed one-off. Management can complete an exact overdue step with the core due-day guard. Today and widget/Shortcut actions resolve the exact current agenda identity, including explicitly saved carryovers; stale ordinary recurring steps from yesterday are rejected.

[Issue #7 verification](verification/ISSUE-7-MANAGEMENT-VALIDATION.md) distinguishes core checks, native compilation and the user-assisted UI matrix. Calendar import, EventKit, new Siri schemas and flexible recurrence remain separate work. Optional notifications are described below.

## Official Siri schema capability spike

[Issue #10's opt-in adapter](SIRI-SCHEMA-GATE.md) compiles the actual iOS 27 reminder entity/create/update schemas while keeping the app's iOS 18 deployment target. `DAILY_RHYTHM_SCHEMA_SPIKE` is absent from normal configurations, so default metadata and widgets retain ordinary Shortcuts only. The prototype supports app-owned one-offs and explicit complete/reopen, rejects unsupported recurrence/fields without mutation, and uses the same shared store. It does not synchronize Apple Reminders or imply generic Siri routing.

The signed iPhone 16/iOS 27 Debug adapter check passed create, completion, repeated completion and reopen while preserving existing plans; its own test item was archived. A subsequent `DailyRhythmSchemaTests` target now verifies those flows through out-of-process AppIntentsTesting, including Spotlight insertion/removal and nil/false/true creation-flag semantics. Opt-in reminder entities are indexed after schema/app mutations and foreground activation; archived tasks cannot resolve or update. [Issue #10 evidence](verification/ISSUE-10-SCHEMA-VALIDATION.md) separates the original direct-adapter report from system tests, 95 current core tests and user-confirmed real Siri creation, completion and reopen. Siri AI Beta and English are user-confirmed; Region and lock/authentication checks remain open. The reported app closure did not reproduce in a controlled cold launch; no crash fix is claimed. #11 must not promote the prototype as a verified production capability.

## First-run setup and contextual help

A new empty installation offers a short English setup sheet: editable morning/evening routines or one blank manual habit. Templates are local values; they do not create sample habits. Each reviewed draft entry has a stable UUID, editable goals/schedule and an explicit Remove action. The draft allows one to three recurring habits, with the regular Free activation check still enforced inside the store. One-off creation stays in the existing manual Add form.

**Create my routine** calls `createInitialRoutine` once for the whole draft. Validation and capacity checks precede an atomic save. Those draft UUIDs become the actual habit IDs. Repeating the same confirmation, including after a process interruption, returns the existing habits without inserting copies, restoring archived habits or rewriting later edits. A different existing plan refuses first-run creation and directs the user to Today/Habits.

`OnboardingPreferences` stores the reviewed draft and unseen/in-progress/skipped/finished status in local UserDefaults, separately from the shared routine document. **Not now** or sheet dismissal saves no habits and leaves a Resume my setup entry in the empty Today view. An editor's unconfirmed field changes remain local to that editor; **Use these details** updates the resumable draft, and only final routine confirmation creates habits. A returning installation, including one with only archived habits, skips automatic setup. Unreadable/unknown draft bytes are preserved; the ordinary manual Add flow remains available.

After creation, the flow explains the first real completion and offers optional widget/Shortcuts help. That help is also in Habits. It uses the system `ShortcutsLink`, exact app-named phrases from `RhythmShortcuts`, and Apple support links verified on 20 September 2026. It distinguishes ordinary App Shortcuts from unimplemented advanced Siri AI/Build My Routine features, makes no Apple Reminders sync or generic routing claim, and adds no launch-time permission requests. `RoutinePlanningHelp` is a contained place for a future availability-gated planning entry; there is no inactive AI button.

[Issue #9 evidence](verification/ISSUE-9-ONBOARDING-VALIDATION.md) records 79 passing core tests, native compilation, a returning-user launch smoke check and the remaining first-install/accessibility/timing walkthroughs.

## Later, Skip Today and Light Day

Today offers **Later · 1 hour**, **Skip Today**, and a manual **Light Day** toggle. Later suppresses only that occurrence from Next Up until its saved instant; it retains the original ID and history day. The shared agenda also exposes explicit earlier overrides and overdue one-offs without manufacturing all missed recurring days. Ordering uses saved timed deadlines or date-only day-part anchors (09:00/14:00/19:00), then day part and stable ID. These anchors only order the list; they are not reminder times.

Skipped records have their own timestamp, never a completion timestamp, and are excluded from completed/full/light counts. History, management and widgets label them explicitly. Progress keeps the original planned-day denominator; carried steps appear in a separate Today section. Full/light completion and skipping resolve a pending step; Reopen is explicit.

Each actual occurrence mutation stamps a fresh revision under the store lock. App actions compare the shown snapshot and return a one-use Undo token. Undo restores the prior snapshot only if that exact resulting revision is still current; stale/repeated/concurrent tokens cannot erase later writes, including identical outcomes recorded again. Widgets pass an explicit revision parameter because AppEntity resolution can refresh other properties before execution. Widget timelines include saved Later deadlines and the next local midnight; refresh timing remains subject to WidgetKit.

Light Day stores a choice for the current Gregorian civil date and promotes only already-saved small targets. Turning it off restores the full-target presentation. A missing small target offers an explicit editor for today's occurrence, or future-plan editing for historical carryovers. No target is inferred, no future template is rewritten, and no AI/network/permission call is needed. [Issue #8 evidence](verification/ISSUE-8-DAY-ACTIONS-VALIDATION.md) separates automated checks and launch smoke from the remaining interactive checks.

## Siri and widget scope

The current code uses ordinary App Intents and App Shortcuts. Those are useful on iOS 18+, but are not the new iOS 27 `.reminders` App Schemas. Do not advertise natural-language Siri AI support based on this milestone.

Widget completion carries the exact occurrence ID displayed. The intent checks the current day again before writing, so a stale widget cannot complete tomorrow's item. Entity lookup preserves exact IDs. Shortcuts selection shows the target before the daypart, date and recorded status: the #4 physical-device check exposed identical rows for two pending Morning habits named Read with different targets when only daypart/date were shown. Repeating create requests currently creates separate habits; only completion/reopen are idempotent.

The store is shared through `group.com.lumetechllc.DailyRhythm`. The app and extension read the configured identifier from `DailyRhythmAppGroup` in their Info.plist. Physical-device signing must grant both targets the same group. There is no separate fallback database.

The [issue #4 device matrix](verification/ISSUE-4-DEVICE-VALIDATION.md) records physical-device provisioning and cross-surface checks separately from the Simulator smoke test below. The first device build exposed an account configuration failure: App Groups capability was enabled, but neither app ID had a group assigned. Both explicit development profiles therefore contained an empty group list. Register and assign the exact group to both app IDs before refreshing profiles; do not remove the entitlement or introduce a second store to get past signing.

## Widgets and configured Controls

The existing widget bundle now includes **Open Today** and **Complete Habit**, using iOS 18 Controls APIs. Open Today uses an `OpenIntent` in both targets and an app navigation coordinator; widget body taps use the registered `daily-rhythm://today` route. Both paths select Today and reset its navigation stack. System placement is chosen by the user in Control Center, Lock Screen controls or an eligible Action button.

Complete Habit configures a persistent, named recurring habit UUID. Its picker includes target, day part, weekdays and a stable short reference to distinguish duplicate names. Invocation resolves the habit's **original planned local date today** and saves full completion inside one locked store transaction. It does not pick a different pending item, a carryover or the next habit. Repeated invocations preserve an existing full or light result; skipped, archived, not-ready and unscheduled choices produce explanatory errors. Light Day does not change the configured full-step action. Widget and control writes require local device authentication; system enforcement and locked-device behaviour still need actual surface testing.

Widget privacy redaction displays a neutral lock message with no occurrence button or named accessibility label. Larger accessibility text uses a compact summary linking into the app. Earlier steps are labeled separately from today's progress. Timelines include unique Later deadlines, anchored timed-due civil-day transitions and the next local midnight, including 23/25-hour days. Widget writes recheck the snapshot and current agenda under the store lock. App/intent mutations request both widget and control reloads; iOS determines refresh timing. Setup help includes Control Center, Lock Screen, Action button and StandBy instructions.

[Issue #12 evidence](verification/ISSUE-12-SURFACES-VALIDATION.md) records 95 passing tests, native builds and the pending device matrix. Compilation, Simulator launch and direct store tests are not proof of Control Center dispatch, widget layouts or StandBy interaction. #12 remains open.

## Daily Close and weekly rhythm

Today and History show a live **Daily Close** card with full, light, skipped and remaining results plus tomorrow's first planned step. History includes seven day tiles with symbols, counts and equivalent text/accessibility summaries, followed by expandable occurrence details. Large accessibility sizes use one column. Basic history stays Free and offline.

`RoutineStore.review(at:)` takes one locked snapshot for the agenda, habits, week and tomorrow. App refreshes reuse it after writes and Undo, on foreground/significant time changes and on the existing refresh timer. Counts retain original planned dates: schedule revisions and archive gaps use the model's history rules, one-offs count once, and deferral/late completion never move the denominator. Remaining includes a separately labeled Planned for later subset; no future work is declared missed. Tomorrow uses effective targets and the normal due/day-part/ID order, excludes earlier carryovers and items moved beyond tomorrow, and never inserts records. Gregorian civil-date labels are formatted in UTC so travel does not shift a saved day.

[Issue #13 evidence](verification/ISSUE-13-REVIEW-VALIDATION.md) records 103 passing core tests and the native build. Device Hub and the selected Simulator did not provide usable live/renderer access; light/dark, large-text and interactive checks remain pending, so #13 stays open.

## Optional local notifications

Habits → Notifications has separate timed-step and Daily Close switches, both off by default. Enabling either requests alert/sound permission only if iOS has not already asked. Denied/revoked permission preserves the feature preferences and every manual tracking operation. Settings offers the iOS notification-settings link and a retryable scheduling error.

`RoutineStore.notificationPlan` computes a read-only, seven-civil-day rolling plan. It includes only future unresolved timed occurrences, including saved Later overrides at their original identity. Date-only work is silent. Daily Close follows the current timezone after reconciliation; timed steps preserve their saved timezone/instant. DST uses the model's existing gap/fold rules. The queue is capped at 56 requests with space reserved for Daily Close; stable identifiers and comparison with actual pending requests prevent duplicate additions.

`RhythmNotificationCoordinator` keeps versioned preferences in the existing App Group, separate from habit data. An async, bounded advisory-lock acquisition serializes preference patches and OS queue reconciliation across app/extension processes. Each holder rereads preferences and the store; no lock is held during the permission prompt. App refreshes/mutations, foreground/significant-time changes, ordinary intents, widget/control completion and opt-in schema mutations reconcile. Unreadable plans or partial scheduling failures clear owned requests after acquiring the lock and preserve source bytes. A successfully saved habit action remains successful even if notification scheduling fails.

Only the owned notification prefix is removed. Every reconciliation also clears owned delivered notices to avoid retaining stale prompts; unrelated requests remain. The app delegate is installed at launch and suppresses foreground banners. Taps validate the exact day/occurrence URL and open a fresh, read-only saved review; archived/missing items never resolve to a replacement or perform a completion. Notification copy contains no habit titles, targets or completion totals. There is no remote push, AI scheduling or exact background wake assumption. Seven days can expire without another execution opportunity, and travel changes Daily Close scheduling only when reconciliation runs.

[Issue #14 evidence](verification/ISSUE-14-NOTIFICATIONS-VALIDATION.md) distinguishes 115 passing core tests and signed native builds from actual permission, delivery, extension and tap checks.

## Local export and erase

Habits → Data & Privacy offers ungated, offline JSON and history CSV exports through the system share sheet. Export version 1 wraps the validated store snapshot, retaining all plans, revisions, archived data, records and Light Day choices. JSON data dates preserve Foundation reference-date seconds and stored precision; the wrapper describes this encoding. CSV contains saved records only, including pending overrides, and uses readable UTC timestamps, quoted fields and an apostrophe before spreadsheet formula-like text. No unrecorded planned days are fabricated. Export does not migrate source files or add backups. Temporary files are protected and removed on completion, cancellation or the next cold launch; copies shared outside the app are user-controlled.

JSON restore validates the supported envelope and complete document before showing counts for confirmation. It only writes into an empty store, with emptiness and current generation checked under the same transaction lock. Existing or corrupt data is never overwritten, and simultaneous creation cannot be lost. Plans, schedules, archive intervals and recorded history retain their values and timestamps; internal plan/occurrence/revision identities are renewed so pre-erase widget/Control/Undo actions stay invalid. Users must re-select restored habits in configured Controls/Shortcuts. Recovery is free even above the current active-habit limit; new creation still follows that limit. Preferences and system permissions are not included. The file picker reads at most 20 MB, and CSV restore is unsupported. Debug-only explicit UUID-scoped recovery uses this same API and writes a count/status report after comparing every persisted field with the expected snapshot; it never runs on a normal launch.

The separate destructive-confirmation screen requires typing `ERASE` before its final button enables, explains that there is no Undo and offers Cancel. Confirmed erasure writes a new generation and a pending marker under the existing stable store lock before cleanup. Each store instance revalidates its captured generation inside every transaction; creation forms, onboarding drafts and notification preference tasks retain the generation they started with. The pending state blocks tracking while owned notifications, preferences, the named search index, setup state, staged exports and schema test reports are removed. The final locked step removes the routine document and migration backups, then releases the pending state. The lock files and non-personal generation marker remain. Failure leaves a retryable pending state, including when final marker persistence fails after data removal; this is not an atomic transaction across iOS services.

Notification cleanup drains earlier scheduling under the same queue lock and verifies no owned requests remain. Old preference replies cannot recreate preferences or clear a newly enabled queue. Schema indexing drains an in-flight write before clearing its index. Late diagnostics/export writes use the store barrier. App caches and navigation are reset and widget/control reloads requested; iOS controls their actual refresh timing. Future routine sessions/Live Activities must add cancellation hooks before the final marker is released. Neither feature exists yet.

The privacy screen explains local App Group storage, iOS-managed backups and the absence of accounts, remote trackers and cloud sync. It makes no entirely-on-device claim for future optional cloud AI. The manifest declares the actual app-local onboarding UserDefaults use with reason CA92.1, with no tracking or collected-data declarations. [Issue #15 evidence](verification/ISSUE-15-DATA-PRIVACY-VALIDATION.md) separates 131 passing core tests, signed builds and installation from device share/cancel and post-erase widget evidence.

## Optional local pilot diagnostics

Observation is off by default and can be enabled in onboarding or Habits → Data & Privacy. A separate `daily-rhythm.json.pilot-diagnostics` file uses the existing App Group lock and data-generation barrier. It stores no routine text, prompts, paths, device identifiers or raw errors. Local occurrence keys deduplicate successful full/light transitions; they never appear in diagnostic exports. Existing completions at opt-in are a separate baseline, with nil legacy provenance remaining unknown. Repeated requests and reopen/recomplete cannot increase an already observed occurrence count, and Undo does not remove a past observation. Restoring a backup itself is not a completion event.

Successful routine persistence precedes optional observation writes. Diagnostic corruption, write failure or a process interruption can leave incomplete observation, but cannot turn a successful core save into a failure. Exports therefore declare `bestEffort: true`; these are pilot observations, not an exact transactional analytics ledger. Failed action attempts are categorized separately and may count again on retry. The app, widget and intent mutation adapters use the captured store instance, preventing delayed pre-erase failures from recreating diagnostics.

Export contains relative civil days, full/light and known-source counts, available setup-to-first-completion seconds, failure buckets and day-7/day-14 checkpoints. `appIntent` combines Siri, Shortcuts, configured controls and the optional schema adapter: the exact system invocation is unknown. First setup time is captured only after opt-in while the app has no plans; missing timing remains unknown. The 30-day window uses the timezone captured at opt-in and expires at the start of day 31. Expired records are removed on the next app refresh or diagnostics access, not by a background timer. Opt-out deletes observation; re-enabling starts a new baseline. Limits bound local IDs and failure counters, with `capacityReached` reporting truncated coverage.

Diagnostic export is explicit and uses the existing temporary-file/share cleanup. It contains no local IDs, exact timestamps or timezone identifier. Routine JSON/CSV backups do not include observation. Local erase removes it before releasing the pending barrier; copies users have shared elsewhere remain theirs. No remote service or PCC events are added: PCC planning is not implemented. [Issue #20 evidence](verification/ISSUE-20-PILOT-DIAGNOSTICS-VALIDATION.md) records definitions, limitations, 148 core tests, 27 native diagnostics checks and 31 privacy regression checks, separately from pending UI and real system-dispatch verification.

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
