# Issue #15 — Local export, privacy and erase

Tracking: [#15](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/15). **Refs #15**: implementation and automated checks pass; the device interaction and post-erase widget matrix is not complete.

**Tested implementation:** `c95685c49b3db5fb709e7eb29cc6f5dea59a43ae`, based on main `be78332692479eec06531cf25a94a828a40b54c7` (PR #47). The 131-test core run and both native configurations cover this source. Documentation-only changes follow.

## Export contract

- Habits → Data & Privacy exports JSON or history CSV without Pro, an account or network access. One validated snapshot is encoded under the shared data lock. Destination/write errors are surfaced without changing saved data. Legacy reads do not migrate or create backups.
- JSON has `format: daily-rhythm-export`, `exportVersion: 1`, an ISO 8601 `exportedAt`, a `dateEncoding` description and `data` containing the validated store document. The current document version is 3. Data timestamps retain numeric Foundation reference-date seconds since 2001-01-01 UTC, including stored subsecond precision; they are not Unix seconds. Original text is preserved. Plans, revisions, archive intervals, outcomes, pending overrides and Light Day choices are included.
- CSV lists saved occurrence records, including full/light/skipped outcomes and pending overrides, with the original recorded titles/targets and archived-plan metadata. It does not turn unrecorded planned days into history. Timestamps are UTC ISO 8601 with millisecond text precision; JSON retains the original numeric precision. Every field is quoted, quotes doubled and rows CRLF-delimited. Formula-like text is apostrophe-prefixed for spreadsheet safety, as explained in the UI.
- A protected temporary export is handed to `UIActivityViewController`. Its completion callback surfaces share errors; completion, cancellation, swipe dismissal and the next cold launch clean owned temporary exports. Externally saved/shared copies remain outside app control.

## JSON recovery

The file picker accepts a Daily Rhythm version-1 JSON export up to 20 MB, validates its full document and encoding, and previews plan/record counts before explicit Restore. CSV cannot restore the complete model. The shared transaction checks both generation and an empty store before atomic persistence; it never overwrites or merges existing plans, history or Light Day choices. Corrupt existing data is preserved. Recovery does not query entitlements, even above the active recurring-habit limit.

The saved values, schedules, archive intervals, outcomes and timestamp precision are preserved. Plan IDs, occurrence IDs and action revisions are renewed together so old widget actions, configured Controls and Undo tokens cannot target restored data. Controls/Shortcuts must re-select their habits. Preferences, onboarding drafts and system permissions are not exported/restored. `matchesRestoredBackup` compares every persisted model field, treating weekday sets by membership rather than JSON array order.

A Debug-only UUID-scoped recovery invocation stages a user-provided file under app Documents, invokes the same empty-store-only API, verifies the saved result and removes the staged source. Its count/status report contains no plan text and uses the generation barrier; reports and staged inputs are included in erase cleanup. Normal launch and Release builds do not invoke this path. It is developer recovery evidence, not file-picker interaction evidence.

## Erase protocol and scope

The destructive confirmation captures the current data generation. A separate screen states that there is no Undo and asks the user to export first; its final button is disabled until the exact word `ERASE` is entered. Cancel discards the captured generation without starting erasure. Once confirmed, `beginErasure` persists a fresh generation and pending flag under the stable shared lock. This happens before cleanup, so a failed barrier write leaves existing data accessible and unchanged. Every ordinary transaction revalidates its captured generation under that same lock. Older stores, generation-bound forms, legacy/saved drafts, staged exports and asynchronous report writes are rejected after the barrier. An unfinished erase rejects normal tracking until retry succeeds.

Cleanup removes owned pending/delivered notifications and reminder preferences under their separate stable lock. It waits for earlier in-flight scheduling and verifies cancellation. A delayed old preference action cannot restore preferences or cancel a new generation's reminders. Schema indexing drains earlier refresh work before deleting the named index; a normal build also clears index data left by a previous opt-in build. App-only setup defaults, in-memory drafts/caches, staged exports and UUID-named schema smoke reports are removed. The final store lock removes the routine JSON and v1/v2 migration backups, then persists completion. Neither stable lock file is unlinked. The non-personal lifecycle marker remains to invalidate old work.

All cleanup hooks must succeed before the barrier is released. A partial failure is reported as unfinished, not successful or rolled back; retry uses the same generation. If marker completion fails after file deletion, the durable pending state still blocks writes. Repeating a completed finish cannot erase new data. App navigation is reset and widgets/Controls receive reload requests; iOS controls visible refresh timing. No routine sessions or Live Activities currently exist; their future cleanup must run before `finishErasure`. Copies outside the app and system permission choices are not erased.

## Executed verification — 20 September 2026

Environment: Apple Silicon macOS **27.0 (26A428)**, Xcode **27.0 (27A266a)**, Swift **6.4**, iOS deployment target **18.0**. Both native configurations inherit **LumeTech L.L.C. (`U54BLJMYG6`)** for app/widget signing.

| Check | Actual result |
| --- | --- |
| Core suite | **131 tests passed**, zero failures; 16 new local-data tests extend the prior 115. |
| Exact JSON / CSV fixtures | Passed with archived plans, full/light/skipped/pending records, Unicode, embedded quotes/newlines and fractional timestamps. JSON data matches the stored snapshot. |
| Free/offline and read-only export | Passed with an entitlement provider that fails if queried, header-only CSV for unrecorded days and unchanged source/legacy bytes. No network service added. |
| Corrupt data / write failure | Passed: unreadable source bytes preserved; destination write failure surfaces. Explicitly confirmed erasure can remove corrupt habit data. Unknown lifecycle formats are preserved and rejected. |
| Cancel/preparation | Core preparation/read leaves store bytes unchanged and does not create a lifecycle marker. This is not evidence of actual native Cancel interaction. |
| Concurrent writes / stale work | 24 competing old store writers plus erase passed; old stores/drafts/confirmation and late export/report writes cannot restore data. New-generation creation works. These are process-local tests of the file-lock protocol, not extension process evidence. |
| Interrupted cleanup | Failed initial barrier preserves data; unfinished cleanup blocks writes; failed final marker retains pending state after deletion; retry completes without re-enabling stale stores. |
| Notification race / cancellation failure | Suspended client scheduling is drained before erase; uncancelled requests keep erase pending; retry removes preferences and owned notices, preserving unrelated notices and the stable lock. Delayed old updates preserve a new generation's queue. These use an injected client, not real OS dispatch. |
| Stable lock / migration backups | Original lock inode survives; both known backup versions and the routine document are removed. Repeated finish preserves data created after reset. |
| Recovery / safe refusal | Passed: weekly schedules and fractional completion timestamps survive; IDs renew; stale actions, old generations, pending erase, malformed/future backups, non-empty storage and failed atomic saves are rejected safely. A competing new creation is never overwritten by restore. |
| Generated project | Regenerated after adding DataPrivacyView; `python3 scripts/generate_project.py --check` passed. |
| Source-membership regression suite | **4 Python tests passed**. Guard and build-script sandbox remain enabled. |
| Signed default and opt-in schema builds | Both **BUILD SUCCEEDED**; strict deep signature verification passed. The schema variant uses the existing `DAILY_RHYTHM_SCHEMA_SPIKE` flag; no new Siri routing claim. |
| User's Xcode session | Closed/reopened DailyRhythm without discarding edits, preserving **XREI-0001**. After reconnecting native UI access, Xcode Build showed **Build Succeeded at 16:36** for the final recovery/typed-confirmation source. |
| Physical install/launch | Opt-in build installed and launched on **XREI-0001 / iPhone 16 / iOS 27.0 (24A437)** after the user reconnected it. No Simulator was selected, booted, reset, created or deleted. |
| Actual share / erase / Cancel interaction | **User-reported:** JSON was successfully shared to the user's own WhatsApp conversation and erasure completed using the original confirmation. Device Hub UI access timed out, so this was not directly observed. The final typed-confirmation screen and Cancel path remain unverified on device. Full post-erase storage/widget verification is still pending. |
| User-provided backup validation / recovery staging | The supplied JSON passes the production decoder. A separate local comparison confirmed every non-identity field is preserved, normalizing only the order of weekday sets. Final recovery build and source file are staged on the selected iPhone. Execution is currently blocked by the phone being locked; no restoration pass is claimed yet. The original export is unchanged and private contents are not committed. |
| GitHub Actions | [Run #77](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/actions/runs/35513970812) did not start its job because the account is locked due to a billing issue. The run's annotation was checked directly. Local test/build results above are not a claim of green CI. |

Commands:

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py --check
python3 -m unittest discover -s scripts -p 'test_*.py'
git diff --check
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daily-rhythm-issue-15/DerivedData build
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daily-rhythm-issue-15/SchemaDerivedData \
  'OTHER_SWIFT_FLAGS=$(inherited) -DDAILY_RHYTHM_SCHEMA_SPIKE' build
codesign --verify --deep --strict --verbose=2 \
  /tmp/daily-rhythm-issue-15/DerivedData/Build/Products/Debug-iphoneos/DailyRhythm.app
codesign --verify --deep --strict --verbose=2 \
  /tmp/daily-rhythm-issue-15/SchemaDerivedData/Build/Products/Debug-iphoneos/DailyRhythm.app
```

Local logs: `/tmp/daily-rhythm-issue-15-tests.log`, `/tmp/daily-rhythm-issue-15-build.log`, `/tmp/daily-rhythm-issue-15-schema-build.log`. These are temporary artifacts; this document records the durable commands, source and outcomes. Successful compilation does not resolve the previously recorded App Shortcuts SSU archive tooling diagnostic or establish Siri discovery.

## Privacy audit

The app has no analytics/ad SDK, cloud account, remote sync, raw-prompt log or network export dependency. Onboarding uses app-local standard UserDefaults; the bundled privacy manifest now declares **CA92.1**, with tracking false and empty collected-data/tracking-domain lists. Shared routine/notification data uses protected App Group files, not a shared UserDefaults suite. Existing logs remain generic, and schema indexing failures no longer interpolate an underlying error. No fingerprinting, disk-capacity or uptime collection was added. App-local file protection and directory enumeration do not introduce file-timestamp collection. System backups remain controlled by iOS settings.

Apple references: [required-reason API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons?language=objc), [privacy manifest guidance](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest), [activity completion callback](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller/completionwithitemshandler-swift.typealias).

## Remaining device checks

- JSON sharing has user-reported evidence. Still record CSV sharing, Save to Files, cancellation, share failure and temporary-file cleanup; include iPad presentation, large text and VoiceOver. Verify that the final typed-confirmation button remains disabled until `ERASE` and that Cancel leaves data unchanged.
- Exercise the actual JSON file picker, preview, Cancel, successful restore and refusal against a populated app. Developer recovery through the same store API does not establish picker interaction.
- With explicitly disposable test data, confirm erase clears the real app/extension container and OS notification/search state, then inspect Home/Lock Screen widgets and configured Controls. Do not erase the user's real habit history for testing. Automated erasure tests only used isolated temporary fixtures; user-reported completion alone does not establish this full matrix.
- Trigger old widget/Shortcut/undo/draft actions around a real device erase and relaunch during unfinished cleanup. Verify recovery UI and first post-erase creation. Core mocks are not OS service evidence.

These gaps keep #15 open; this PR is not TestFlight or release-readiness approval.

## Simulator follow-up — 20 September 2026

**Tested implementation:** `05d343f4b63a0ff195fa1a9c72d8301858b6d2bc`, based on merged PR #48 (`79e641b09786df711e44871214bea1642f68a39a`). The production view and fixture helper were byte-compared with the compiled source copy. The user authorized Simulator testing and said the phone would remain disconnected; physical iPhone recovery is still deferred, not completed.

Used the project's previously tested, existing **iPhone 17 Pro / iOS 26.5**, UDID `A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6`. It was initially shut down and booted for this run. No other Simulator was selected, and no device/runtime was created, deleted, reset, replaced or installed. Xcode **27.0 (27A266a)** built the isolated app/widget with ad hoc signing. The product's open Xcode project was also reopened with its existing **Any iOS Device (arm64)** destination preserved; Build showed **Build Succeeded at 16:50**.

`scripts/validate_privacy_simulator.py` requires an explicit, already booted UDID and refuses unavailable/unbooted input instead of choosing or starting another device. It builds a temporary source copy with unique `.Validation15.<run>` app/widget IDs, a separate App Group and a separate URL scheme. `PrivacyValidation.swift` calls the production application models inside that process using only synthetic fixture plans. The helper is outside product source membership and is injected only into the temporary project. The user's exported JSON is never loaded by this test.

The first run reproduced stale restore state: after a bad file, selecting a valid backup left the previous error visible. `prepareRestore` now clears its old error and preview before validating each newly selected file. A bad selection cannot leave a previously valid backup ready to restore. [Before-fix result](issue-15/simulator-before-fix.json) records the reproduced failure; [after-fix result](issue-15/simulator-after-fix.json) records **31 passing native model/service checks**.

| Executed check | Result |
| --- | --- |
| Export and share callbacks | JSON includes archived plans and full/light/skipped records; CSV escaping/formula protection passes. Cancellation, simulated share-error callbacks and dismissal after SwiftUI clears the binding remove staged exports; store bytes remain unchanged. These are callback tests, not actual share-sheet interaction. |
| Restore preparation and retry | Counts validate; discarding a preview preserves data; populated storage refuses restore; invalid JSON clears the prior preview and preserves data; the next valid file clears the obsolete error. |
| Actual iOS cleanup hooks | Erase completed through the real Simulator notification client and Core Spotlight deletion API. Saved reminder preferences, setup defaults/draft, diagnostic report, main document and both migration backups were removed. The lifecycle barrier completed, stable lock inode survived, and cached app data/Undo cleared. |
| Notification scope | Actual Simulator pending/delivered queues were empty after cleanup. No notification authorization was requested and no delivery is inferred; pre-populated OS queue or search-index deletion still needs separate evidence. |
| Stale work and recovery | Old store and onboarding draft writes were rejected. Restore repopulated the empty fixture through the production API; every saved model field matched the validated backup and the app model showed all three fixture plans. |
| Cold launch | Terminate/relaunch without the validation flag succeeded and retained identical restored store bytes. |
| Isolation and cleanup | The existing product's routine document, lifecycle and known migration-backup hashes were unchanged. Both agent-created test apps were removed after collecting results; the selected Simulator remains available. |
| Project consistency | Generation/check and whitespace checks passed. No generated production project change was needed. |

Reproduction, after selecting and booting the intended existing Simulator yourself:

```sh
python3 scripts/validate_privacy_simulator.py --device <existing-booted-simulator-udid>
```

The runner prints its temporary build log, result and manifest locations. It removes only its uniquely named test app, never the product app or a Simulator. The earlier 131 core-test/4 generator-test results remain recorded above; they are not represented as rerun during this app-only correction.

**UI limitation:** Device Hub accessibility access repeatedly timed out even after successful Simulator boot. No synthetic UI events were used as a substitute. The native typed-ERASE screen, actual picker/share sheet, visual appearance, accessibility and post-erase widget rendering remain unverified. This follow-up establishes application-model/OS-service behaviour and persistence, not those UI acceptance criteria. #15 remains open.
