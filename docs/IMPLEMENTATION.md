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

Widget completion carries the exact occurrence ID displayed. The intent checks the current day again before writing, so a stale widget cannot complete tomorrow's item. Entity lookup and display include enough context to disambiguate duplicate titles. Repeating create requests currently creates separate habits; only completion/reopen are idempotent.

The store is shared through `group.com.lumetechllc.DailyRhythm`. The app and extension read the configured identifier from `DailyRhythmAppGroup` in their Info.plist. Physical-device signing must grant both targets the same group. There is no separate fallback database.

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

The current developer environment is Linux without Xcode or Swift. Local checks cover project generation, plist parsing and source consistency; macOS CI and real-device checks are reported separately.
