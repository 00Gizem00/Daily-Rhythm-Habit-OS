# Version 3 — day actions

Scheduling, original planned-date identity, future revisions, archive gaps and Free capacity retain the [v2 contract](MODEL-V2.md). V3 adds explicit skipped outcomes, optional `skippedAt` and `deferredUntil`, occurrence `mutationID` revisions, and optional per-civil-date `dayModes` with independent revisions. Older v2 binaries reject version 3 rather than silently erase these fields.

## Result and mutation rules

- Full/light results have `completedAt`; skipped results have `skippedAt` and no completion timestamp. Pending has neither timestamp nor result source. Light requires a saved small target. `isCompleted` includes only full/light; `isResolved` also includes skipped. Remaining count excludes resolved steps; the planned denominator still includes skipped steps.
- `perform(_:on:source:requiringAgenda:now:)` compares the entire supplied snapshot inside the same lock as its save. Completion, skip, Later and Reopen return an opaque Undo token. Undo checks the resulting revision, restores the previous snapshot, and assigns a new revision. Repetition or another write makes a token stale, including completion → reopen → identical completion at the same timestamp.
- Existing completion remains first-result-wins. Optional expected revisions protect callers such as widgets. Every save path, including target/due editing and reopen, stamps a new revision. No-op legacy requests do not stamp or rewrite. Reopen is a deliberate command; it is distinct from Undo of an earlier action.
- Light Day compares its own mode revision and current day. Switching it off is the explicit reversal. It changes presentation only; it does not create completions or smaller targets and does not carry yesterday's mode into today. The choice is keyed to the user's local Gregorian civil date, including during travel.

## Agenda and ordering

Historical summaries stay on the original planned day. The current agenda combines today's plan, earlier explicit occurrence records, and overdue one-offs. Resolved carryovers remain visible on their resolution date for Reopen. Unrecorded missed recurring dates are not synthesized as backlog.

Timed due values order by absolute instant. Date-only values use the due civil date with a local 09:00/14:00/19:00 morning/afternoon/evening anchor, then day part and stable ID. Anchors do not alter the persisted due value. If travel enters a timezone that skipped that date entirely, the validated date's UTC noon is the ordering fallback. Next Up selects the first pending, due-day-eligible item whose explicit deferral has expired.

Later saves an absolute future instant and its timezone in the existing due field and `deferredUntil`. Today offers one hour. The occurrence ID, targets and historical denominator are unchanged, even across midnight or a repeated DST hour. The normal due editor clears this special deferral when replacing the due value. Timed schedules without Later keep their prior due-day early-completion policy.

Today and widgets consume the same agenda ordering. Widget timelines precompute the next local midnight and earlier deferral deadlines. Carryover completion updates its original planned day, not today's progress denominator. A stale widget must still name an exact agenda ID and carry the current occurrence revision; it cannot silently complete a new version of the task.

## Upgrade and recovery

First successful access to v1 or v2 validates and migrates under the existing transaction lock. The original bytes are copied to `daily-rhythm.json.v1-backup` or `.v2-backup` before an atomic v3 save. V2 snapshots retain every pre-existing field; no completion source is invented. New fields start absent. V2 upgrades reject unfamiliar fields, including nested schedule/record fields, instead of silently discarding them. Unknown versions and invalid documents fail without replacing the original.

A failed operation does not migrate. A failed atomic save leaves the original and any created exact backup intact. A pre-existing different backup blocks the migration rather than overwriting either file. Recover only with the app and extensions stopped: preserve all files first, inspect the matching version backup, and restore the chosen complete document through a deliberate recovery procedure. Do not overwrite a newer v3 document with an old backup to recover a single action: use the current app's Reopen/Undo or inspect the records first.
