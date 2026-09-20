# Version 2: schedules, occurrences and migration

Implements [issue #5](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/5). The Foundation-only `DailyRhythmCore` package remains the single mutation service for the app, widgets and ordinary App Intents. [Issue #7 management screens](IMPLEMENTATION.md#habit-and-one-off-management) expose creation and history-preserving editing; ordinary creation Shortcuts still create repeating, date-only habits. Siri schema support remains later roadmap work.

## Supported values

| Concept | Representation and limits |
| --- | --- |
| One-off | `Recurrence.once(dayKey:)`, one Gregorian `YYYY-MM-DD` on or after creation; exactly one original occurrence. |
| Repeating | `Recurrence.weekly(weekdays:)`, nonempty subset of Foundation weekdays 1–7 (Sunday–Saturday). All seven means daily. Weekdays and weekends are subsets. |
| Unsupported recurrence | Monthly/yearly, intervals such as every other week, RRULE strings, multiple occurrences per habit per day, and changing between one-off/repeating are unsupported. The finite enum cannot express them; unknown encoded cases are rejected without rewriting the file. Adaptors must report unsupported requests, never substitute daily recurrence. |
| Date-only | `dueTime == nil` derives `OccurrenceDue.dateOnly(dayKey:)`. Daypart is a presentation category, never an invented clock time. |
| Timed | `ScheduledTime(hour:minute:timeZoneIdentifier:)` uses 24-hour hours 0–23, minutes 0–59, and a valid named timezone. An occurrence resolves this to `OccurrenceDue.timed(at:timeZoneIdentifier:)`. |
| Duration | Optional positive integer `durationMinutes`. Nil is unknown/unspecified; zero and negative values fail validation. Text such as “20 minutes” is never parsed during migration. |
| Snapshot | Original planned day, title, normal/light target, daypart, optional duration, effective due value, optional outcome/timestamp/source. |

## Identity, postponement and overdue work

Occurrence identity stays `UPPERCASE-HABIT-UUID|original-planned-day`. It excludes the due time, due timezone and postponed date. Repeated requests resolve this exact identity; same-name habits keep distinct UUIDs.

Daily summaries and history count an occurrence on its **original planned day**. Postponing a September 20 one-off until September 22 retains its September 20 denominator and ID; it does not create another September 22 occurrence. For repeating habits, September 22's normally scheduled occurrence still has its own ID. A future agenda UI must present postponed work separately from historical daily denominators. `occurrence(id:)` resolves earlier pending work without restricting it to today's summary.

`rescheduleOccurrence` changes only the due value of a pending occurrence, including overdue work. The new due civil date must be on or after the original planned day. It can change date-only to timed or vice versa, or move a previously postponed due date earlier within that constraint. It never changes the target or identity. `updateOccurrence` replaces the pending occurrence's normal/light target, duration and due value; nil explicitly removes an optional target/duration. Target changes cannot rewrite dates before today's date or the habit's last mutation date. Completed occurrences reject both operations until explicitly reopened.

A saved pending override takes precedence over later template revisions, even when a future weekday is removed. This keeps an explicitly customized occurrence from disappearing. Archive intervals still suppress pending work in their excluded original planned dates.

An uncompleted date-only occurrence is overdue once the current device's civil date exceeds its due date; it has no due instant. A timed occurrence is overdue strictly after its stored due instant. Completed occurrences are never overdue. Completion is allowed early on the due civil date, but not on an earlier date (using the timed occurrence's own timezone, or the current store calendar for date-only work). Cross-day postponement therefore blocks completion until the new due date.

First completion wins atomically: outcome, timestamp and source are retained on retries, including competing full/light requests. Reopen clears all three but retains the snapshot and due value. Repeated reopen is a no-op, including after the first reopen hides a completed occurrence in an archive gap.

## Effective history and archive intervals

A habit stores an ordered list of full `HabitRevision` values, each with an effective civil date. Creation establishes the first revision. For any original planned date, the latest revision effective on or before that date determines the unmaterialized plan. Summaries are derived on demand; reading future dates does not save hypothetical occurrences.

`editHabit` accepts a full replacement definition effective **strictly after today and the latest recorded mutation's civil date**. This protects past days even if they were never opened or completed. It can replace an existing future revision at the same date; later future revisions remain scheduled. Repeating weekdays may change. A one-off's anchor date and recurrence kind cannot change through this API; use its occurrence for postponement. Completed records and saved overrides own their snapshots and are never compared to the latest template fields during v2 validation.

Archive intervals are half-open `[archiveDay, restoreDay)`. Archiving removes pending work from that original planned day forward and retains completed records and earlier plans. Restoring resumes on the restore day; the gap stays excluded forever. Several archive/restore cycles are retained. Same-day archive and restore have an empty interval. Restoring after a one-off's original date falls in a gap does not create a replacement occurrence. Reopening a completion inside an archive gap removes it from the summary; it does not reactivate the plan.

Each habit also retains a civil-date mutation frontier. Archive/restore operations cannot move backward across that frontier, and edits must start after it. Moving west or changing the clock cannot use these APIs to retroactively archive already affected dates. A later local date or an explicit future edit is required. `habits(asOf:)` projects the effective definition; its archive filter reflects the latest archive/restore action, while `history` is the historical view.

## DST and timezone travel

Civil keys are validated and their weekdays evaluated in Gregorian UTC, independently of the reader's timezone. Existing keys, creation boundaries and archive gaps are never recomputed from timestamps. Date-only repeating habits continue to follow the device's civil day, matching v1 behavior. Travel may expose a different day's repeating occurrence; it does not move a saved completion to that day.

Timed schedules keep their explicitly selected timezone when travelling. Their wall-clock time is resolved on the original civil date in that zone. Missing times during a DST jump use the next valid time (`02:30` becomes `03:00` for New York's spring jump); repeated times use the first instant. The repeated hour never produces another ID. Changing a schedule timezone requires a future revision; changing one pending occurrence uses its due override. A whole civil date omitted by a timezone's historical date-line change cannot be assigned a time on that date: resolution returns `invalidDueDate` instead of silently moving the plan. Date-only keys remain valid Gregorian dates.

Saved timed snapshots retain their exact instant and timezone. Unmaterialized timed plans resolve using the platform's timezone rules when read. The store's calendar selects which date a summary views; it never re-buckets a saved occurrence by the device's new timezone. History uses calendar-day arithmetic, not fixed 86,400-second subtraction.

## Completion attribution

New app taps pass `.app`. Widget buttons use a dedicated undiscoverable `CompleteWidgetOccurrenceIntent` and pass `.widget`, regardless of which process iOS selects to run the intent. The ordinary `CompleteOccurrenceIntent` passes `.appIntent`; Siri and Shortcuts cannot be distinguished reliably here. The store's default is nil for unspecified callers.

All migrated completions have nil source. Migration does not infer a surface, duration or due time. The new widget intent is compiled into both targets; existing ordinary Shortcut identifiers remain available. Today and current widget/Shortcut intents keep their “today” stale-action guard. The management screen can act on an explicitly selected overdue occurrence by exact ID, under the core due-day guard.

## Migration, failures and recovery

The JSON header now contains `version: 2`. `LegacyDocument` decodes v1 independently of the new types and validates its original snapshot invariants. It preserves habit and occurrence IDs, all targets, dayparts, weekday sets, creation/archive civil dates, outcomes, pending reopened records and the exact fractional `Date` values. Each old habit becomes a first date-only weekly revision; an old archive becomes an open archive interval. The old format has no revision timestamp, so `recordedAt` stays nil.

The first successful read or mutation migrates while holding the existing exclusive `flock` on a stable sibling `.lock` file. The whole document is decoded and validated, the requested operation succeeds, and the result is validated/encoded before any replacement. The original bytes are copied to `daily-rhythm.json.v1-backup` and checked for equality, then v2 atomically replaces the primary file. The backup uses the same iOS data-protection policy as the store. There is no empty fallback store.

A failed operation before commit leaves the v1 primary unchanged. Decode/validation failures and unknown versions leave the original bytes unchanged and produce errors. Unknown v1 fields are also rejected rather than discarded. If backup creation or the atomic save fails, the primary remains intact; an existing completed backup is retained for retry. A pre-existing backup with different bytes blocks migration and is never overwritten. A partial backup from an interrupted copy likewise blocks retry rather than being trusted. All concurrent readers/writers reread after acquiring the same lock, so only one migrates and later operations see its v2 result.

The backup is a recovery artifact, not an automatic fallback. Keep both files when diagnosing any error. Never overwrite a newer v2 primary with the old backup automatically: that could lose post-migration work. A manual rollback requires stopping the app and extension, preserving the current primary separately, then restoring a verified backup under the same transaction discipline. Older app versions reject version 2 instead of resetting it. Keep the backup until an explicit future data-management action removes it.

Validation rejects duplicate IDs, orphan/malformed records, invalid dates/targets/durations/timezones, invalid outcome/timestamp/source combinations, unsorted revisions and overlapping/malformed archive intervals. The v2 validator deliberately validates a snapshot on its own values rather than requiring it to equal today's definition.

## API examples

```swift
let definition = HabitDefinition(
    title: "Call the library", normalTarget: "One call", dayPart: .afternoon,
    recurrence: .once(dayKey: "2026-09-22"), durationMinutes: 10
)
let habit = try store.addHabit(definition)
let id = "\(habit.id.uuidString)|2026-09-22"
try store.rescheduleOccurrence(occurrenceID: id, due: .dateOnly(dayKey: "2026-09-23"))
// Still the same occurrence, counted on September 22; complete on/after September 23.
```

For deterministic callers/tests, pass `now:` explicitly. All new APIs validate before committing and use the same transaction service; callers must not write the JSON directly.

Verification evidence is in [ISSUE-5-MODEL-VALIDATION.md](verification/ISSUE-5-MODEL-VALIDATION.md).
