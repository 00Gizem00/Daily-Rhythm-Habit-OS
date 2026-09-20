# Issue #6 — Free habit activation policy verification

Tracking: [issue #6](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/6). Policy contract: [implementation notes](../IMPLEMENTATION.md#free-activation-policy).

**Tested implementation commit:** `36a2a52c584014692572ae638957de91ce25a1f0`, based on `origin/main` at `2ba0b49` (merged PR #34). Tests and the native build ran against the source and tests in this commit; subsequent changes only document evidence.

## Environment and commands

20 September 2026, approximately 06:47 Europe/Istanbul. Apple Silicon Mac, macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`), Swift 6.4 (`swiftlang-6.4.0.34.1`, clang `2100.3.34.1`), Swift 6 language mode. Deployment target iOS 18.0; generic iOS Simulator 27.0 SDK build for arm64 and x86_64.

```sh
swift test --package-path Packages/DailyRhythmCore
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-6/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
python3 scripts/generate_project.py --check
git diff --check
```

No Simulator device was selected, booted, created, deleted or assigned another runtime. The build was not installed on the physical phone; its store was not changed.

## Results

| Check | Actual result |
| --- | --- |
| Core tests | **44 XCTest cases passed, zero failures**, command exit 0. Includes all 32 previous tests and 12 new policy tests; complete suite reported 0.424 seconds of test execution. |
| App and widget compilation | **BUILD SUCCEEDED**, exit 0. Both targets built for arm64 and x86_64, including the shared Free provider and creation-form copy. |
| Generated project | **Passed**, `Xcode project is up to date.` New files are Swift package sources/tests; Xcode target membership does not change. |
| Whitespace | **Passed**, `git diff --check`. |

Temporary raw logs: `/tmp/daily-rhythm-issue-6/swift-test.log` and `/tmp/daily-rhythm-issue-6/xcodebuild.log`.

The clean build again emitted the existing nonfatal `appintentsnltrainingprocessor: error: Could not archive SSU artifacts. Check build log.` after generating/copying App Intents SSU YAML. Xcode returned success. No build setting was changed to suppress the diagnostic. This build does not establish Siri speech recognition or on-device presentation of the new limit error.

## Acceptance evidence

| Criterion | Evidence |
| --- | --- |
| Fourth active Free habit rejected | Both public single-creation overloads reject the fourth with `activeHabitLimitReached`; the JSON remains byte-for-byte unchanged. Same-name habits are counted separately. A weekday-only habit counts even on an unscheduled day; completion does not free its slot. |
| Concurrent creation cannot exceed three | 40 independent default-Free store instances race to create: exactly **3 succeed, 37 fail with the limit error**, and 3 habits persist. Instances use real file descriptors and the store's existing `flock`. |
| Batch capacity, including future routine groups | A four-recurring batch creates no file in an empty store. An oversized mixed batch writes neither its recurring habits nor its one-off. A fitting mixed batch adds every item. Twenty concurrent two-recurring batches yield exactly **1 complete batch and 19 rejections**; the last single slot remains usable. Every definition counts individually; there is no container discount. |
| Archive/restore | Archive frees one slot and preserves prior history. A full-store restore fails without changing bytes. Same-day duplicate archive does not free another slot. Successful later restore retains the archive gap. Already-active restore is a no-op at capacity. |
| Restore batches and mixed races | A too-large mixed restore leaves even its one-off archived; unknown IDs fail atomically. Repeated IDs count once. With 2 active habits, 20 distinct restorations race 20 creations: **1 succeeds, 39 fail**, final active count 3. |
| One-offs distinguished | Five one-offs can be added while 3 recurring habits are active. One-off archive/restore, completion and undo remain available. A one-off cannot change into a recurring habit through edits. |
| Safe downgrade | A mutable test-only provider creates 5 Pro habits, then changes to Free on the same store instance. Reads preserve all records/bytes. Full/light completion and undo work with `.app`, `.widget` and `.appIntent` source values; history, occurrence lookup, future editing and archive remain available. New recurring creation/restoration fails until capacity permits. One-off creation still works above the cap. |
| Current entitlement boundary | The same store rechecks Free → Pro → Free on each recurring creation/restoration; it does not cache a constructor-time entitlement. Only tests supply Pro. Production supplies `FreeHabitEntitlementProvider` explicitly at the shared composition point and defaults to Free in the public constructor. |
| Existing over-limit v1 data | A valid fixture with 4 active recurring habits rejects creation/restore without migrating or creating a backup. A subsequent read migrates all 5 total habits without pruning, preserves the exact v1 backup and permits existing completion/history. |
| Validation/save failures | A mixed batch with an invalid title saves none of its valid items. An injected atomic-write failure leaves original bytes unchanged; retry adds the full fitting batch. This is deterministic failure injection, not an actual exhausted disk. |
| Clear English and shared entry points | The creation form shows the Free rule and retains input after a failed save. `AppModel.addHabit` and `CreateHabitIntent.perform` both call `SharedRoutineStore.makeStore()` → `RoutineStore.addHabit`; the same localized core error propagates from both. The Shortcut returns success and reloads widgets only after a successful save. Native compilation and source review verify this wiring; a new device invocation is not claimed. |

The two existing high-volume concurrency regressions now inject a **test-only Pro provider** for their 30-creation and 20-migration-write setup. Their original record-count assertions remain intact. New default-Free races verify the cap separately; normal existing tests retain the Free default.

## Boundaries and follow-up

This issue adds an activation rule to the shared mutation service. It does not add purchase handling, a Pro toggle, a paywall, routine containers, Siri AI schemas, proposal application tokens or a new export UI. Future schemas and Apply must call the same individual/batch APIs. Batch creation is atomic but is not retry-idempotent; proposal-level idempotency remains #18.

Completion, undo, history, entity/widget reads and data reads for future export do not consult the provider. Existing export UI was not present in the foundation; its implementation remains #15 and must remain ungated. The `.app`/`.widget`/`.appIntent` completion tests exercise core attribution, not actual device processes.

Concurrency tests use separate store instances/file descriptors within one test process, not a new app-plus-extension physical-device race. Existing [#4 device observations and pending checks](ISSUE-4-DEVICE-VALIDATION.md) remain unchanged; the user previously chose to proceed to subsequent roadmap work with those limits recorded. No outstanding device check has been relabeled as passed here.

Before StoreKit integration (#22), implement a verified shared entitlement snapshot and test expiration/refresh across app and extension processes. The provider must be quick, thread-safe and non-reentrant because it is queried while the file lock is held. Core local tests and unsigned compilation do not establish that future purchase integration.
