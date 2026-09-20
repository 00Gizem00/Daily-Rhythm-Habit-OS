# DailyRhythmCore

Foundation-only Swift 6 package shared by the app and widget extension.

```sh
swift test --package-path Packages/DailyRhythmCore
```

## Behaviour

- Habits recur daily or on selected Foundation weekdays (`1 = Sunday`, `7 = Saturday`). A Gregorian calendar uses the supplied calendar's timezone.
- Each local calendar date produces a stable `UUID|yyyy-MM-dd` occurrence. Reading tomorrow's summary never writes data, and no midnight task is required to generate tomorrow's work.
- Full and light completions remain distinct. A light completion requires a configured smaller target. The first completion wins; reopen explicitly before changing it.
- Completing an exact past occurrence is allowed, including a tap crossing midnight. Future completions are rejected. UI/intents may apply a stricter current-day policy. Neither path substitutes a different occurrence.
- Creation/archive dates are saved as local date keys. Travelling changes today's local date but does not move prior records to another calendar date. No custom day boundary is implemented yet.
- Archive removes unfinished occurrences on the archive date and later. Earlier history and recorded completions remain; reopening an archived occurrence on its archive date removes it from that day's visible schedule.
- History includes empty days, oldest first; its bounded range is 1–366 days.

## Persistence

Inject a file URL in the shared App Group directory. Each operation uses an exclusive POSIX `flock` on a **separate stable lock file**, reads the latest JSON, and atomically replaces JSON only after a successful mutation. This coordinates independent app/widget store instances, including processes. The lock file must not be deleted while the app or extensions are using it.

The versioned JSON stores habit templates and occurrence snapshots for completed/reopened items. Dates use Foundation's reference-date numeric encoding to preserve fractional seconds. Schema migrations are deliberately not implicit: unsupported versions, decode failures and invalid records throw without overwriting the existing bytes. The app must show the error instead of constructing a replacement empty store.

On iOS the store directory, stable lock file, and each atomically written JSON file use `completeUntilFirstUserAuthentication` protection. Data is intended to remain available while locked after the first device unlock following boot. The App Group entitlement and real-device locked-phone behaviour still require integration verification. An unavailable file throws; callers must not report a successful completion. Atomic replacement prevents partial JSON visibility, but this prototype does not promise crash-proof power-loss durability or cloud synchronisation. Export, explicit erase, schedule editing, event-source attribution, and data migrations remain separate milestones.

## Tests

Tests cover daily/weekday recurrence, stable identity, midnight rollover, DST spring/fall changes, timezone travel, duplicate completion, undo, archive history, duplicate habit names, validation, persistence across instances, corrupt/future-version preservation, and concurrent independent store writes. The concurrency test uses separate file descriptors in one process; an app-plus-extension real-device test is still required before claiming the cross-process integration is validated.
