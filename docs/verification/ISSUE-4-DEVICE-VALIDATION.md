# Issue #4 — shared storage and cross-surface device validation

Tracking: [issue #4](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/4). This is a device validation record, not a claim that Simulator or host tests establish physical-device behaviour.

## Environment and build

- Date: 20 September 2026, Europe/Istanbul.
- Initial source baseline: `7a36828c3e585ee8f268e627c6377830cc9bfe53`, `main` after #31 merged and #3 closed.
- Physical device: iPhone 16, iOS 27.0 (`24A437`), Developer Mode enabled, paired over the local network.
- Toolchain: Xcode 27.0 (`27A266a`), Apple Swift 6.4, iPhoneOS 27.0 SDK.
- App: `com.lumetechllc.DailyRhythm`; widget: `com.lumetechllc.DailyRhythm.Widgets`.
- Required shared group: `group.com.lumetechllc.DailyRhythm`.
- Signed build: **Debug 0.1.0 (1)**, Apple Development signing, built successfully and installed on the physical iPhone at approximately 05:48–05:49.
- Target-label fix: source `5c368716919eb20a8797c2dcd91337f655fe49bc`, signed **Debug 0.1.0 (1)** rebuilt and installed at approximately 06:12. Both target signatures, signed/profile App Groups and expanded Info.plist settings were reverified. Project-generation consistency and whitespace checks pass.

Device serial numbers, physical-device identifiers, raw provisioning profiles and account credentials are deliberately excluded from this repository record. Use the selected device UUID locally for the commands below.

## Provisioning defect found

The initial physical-device build selected a wildcard development profile without App Groups capability and failed for both targets. A retry with `-allowProvisioningUpdates` created explicit development profiles, but both contained an empty `com.apple.security.application-groups` list and still failed. The selected iPhone was included in those profiles; missing device registration was not the cause.

The Apple Developer account had no Daily Rhythm App Group. The configured group was registered as **Daily Rhythm Shared Storage**. The user approved assigning it to both explicit App IDs and regenerating their development profiles after Apple's capability-change warning. This changes provisioning, not the on-disk storage identity or the application schema.

After assignment, `xcodebuild ... -allowProvisioningUpdates build` exited 0 with `BUILD SUCCEEDED`. For **both** the app and embedded extension:

- `codesign --verify --strict` passed.
- The signed `com.apple.security.application-groups` entitlement contains `group.com.lumetechllc.DailyRhythm`.
- The embedded development profile contains the same group and includes the selected physical iPhone.
- The expanded `DailyRhythmAppGroup` Info.plist key matches that group.

`devicectl device install app` succeeded. A device-side app query confirmed version 0.1.0 (1) and an allocated shared container for `group.com.lumetechllc.DailyRhythm`. A subsequent foreground launch was rejected by iOS because the phone had relocked during setup (`FBSOpenApplicationErrorDomain`, code 7, `Locked`). This is a recorded system launch rejection, not a persistence failure or a passed locked-phone action test.

After unlock, a retry of `devicectl device process launch` succeeded and the captured physical-device screen showed the first-habit UI without a storage-error banner. The user had reported a generic "failed" message before that retry; its source/action was not established, so it is not classified as a fixed app defect. No Daily Rhythm crash report was listed at that point. Device Hub UI automation continued to time out, so creation and widget interaction require user-assisted reproduction.

The physical build also logged `Could not archive SSU artifacts` from `appintentsnltrainingprocessor` while returning build success, as in #3. The diagnostic has not been suppressed. Subsequent device discovery and invocation results are recorded separately below; neither build success nor App Shortcuts discovery establishes Siri voice recognition.

Apple references: [register an App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group), [configure App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).

## Habit creation and process relaunch

The user created the default reading habit through the physical iPhone UI. Their 05:53 screenshot showed **Read**, **10 pages**, **Morning**, a **2 pages** light step, and **0/1** completed, without a storage-error banner.

At approximately 05:56, `devicectl device process launch --terminate-existing` successfully restarted the application. The first capture overlapped the phone's lock screen, so that capture was not treated as a loaded-app result. After the user unlocked the phone, a fresh [device screenshot](issue-4/app-after-relaunch.png) showed the same habit, targets, daypart and pending count, with no storage error. **Visible creation and persistence across process relaunch pass.** Widget and Shortcuts access are separate checks.

The habit's raw UUID has not been extracted. `devicectl device copy from` rejected the App Group root-level `daily-rhythm.json` because its container transfer service allows only `Library`, `Documents` and `tmp` (remote service error 11007). Consequently, the earlier limited directory listing cannot establish whether the store exists. This is a developer-tool access restriction, not evidence of a failed app read/write. No data was moved, replaced or seeded to bypass it. Exact record identity and completion timestamps still require separate evidence.

## Widget observations

After adding the small **Your Daily Rhythm** widget, the user confirmed that it displayed **Read / 10 pages**, matching the habit created in the app. This is user-observed evidence that the widget can read the existing shared data.

The user then tapped **Done** once in that widget. At approximately 06:01, foregrounding the app showed **1/1**, **1 full**, **0 light**, and **Read — Full · 10 pages**, without a storage-error banner ([app after widget completion](issue-4/app-after-widget-done.png)). A subsequent `devicectl device process launch --terminate-existing` and fresh capture showed the same completion ([app after restart](issue-4/app-widget-done-after-relaunch.png)). **The small-widget completion is visible in the app and survives an app process restart.** This establishes the visible full-completion path; raw occurrence identity/timestamp and the medium widget remain unverified.

Next, the user tapped **Reopen** on the app's Read row and returned to the small widget. They reported that **Read / 10 pages** and **0/1** returned immediately. **App-to-small-widget undo refresh passes by user observation.** No numeric refresh latency was measured, and the underlying file was not extracted.

At approximately 06:04, after explicitly reopening the step and tapping the small widget's **leaf** button, the user confirmed that the tap had been performed. A forced app restart then showed **1/1**, **0 full**, **1 light**, and **Read — Light · 2 pages** ([light completion after restart](issue-4/app-widget-light-after-relaunch.png)). **The small-widget light-completion path also passes visually and persists across process restart.**

On the corrected target-label build, the user added a **medium** widget and completed the remaining **Read / 10 pages** there. At approximately 06:15, a forced app restart showed **2/2**, **2 full**, **0 light**, with both **Full · 10 pages** and **Full · One step** rows ([app after medium-widget completion](issue-4/app-after-medium-widget.png)). **Medium-widget full completion also passes visually and persists across app restart.**

## Shortcuts observations

In the installed Shortcuts app, the user opened **App Shortcuts → Daily Rhythm** and confirmed that **Create Habit**, **Complete Step** and **Undo Step** were all visible. **App Shortcuts discovery passes by user observation**, despite the nonfatal SSU archive diagnostic. Invocation and data changes require the following checks and are not implied by discovery.

At approximately 06:08, the user ran **Undo Step** and selected **Read**, whose existing light completion had been made by the small widget. Foregrounding Daily Rhythm then showed **0/1**, **0 full**, **0 light**, and **Read / 10 pages** as the next pending step ([app after Shortcut undo](issue-4/app-after-shortcut-undo.png)). **Shortcut undo of a widget-created completion passes visually in the foreground app.**

At approximately 06:09, the user ran **Complete Step** for **Read** twice, leaving **Use Small Step** off. A forced app restart showed **1/1**, **1 full**, **0 light**, and **Read — Full · 10 pages** ([app after two Shortcut completions](issue-4/app-after-shortcut-complete-twice.png)). **Shortcut completion and repeated full completion pass visually without an extra completion count.** The first completion timestamp and competing full/light requests have not yet been checked on the physical device.

At approximately 06:10, the user ran **Create Habit** with the name **Read** and defaults (**One step**, **Morning**, **Every Day**). After a forced app restart, the screen showed **1/2**: the original **Read — Full · 10 pages** remained completed, and the new **Read — One step** was pending ([app after Shortcut creation](issue-4/app-after-shortcut-create.png)). **Shortcut creation passes visually and preserves the other habit's existing completion.** All three ordinary App Shortcuts have now been invoked successfully; same-name selection is tested separately.

### Same-name selection defect

After the user reopened the original Read / 10 pages step, both Morning habits were pending. Opening **Complete Step** displayed two identical choices: **Read** with **Morning · 2026-09-20**, omitting the different targets ([picker before fix](issue-4/shortcut-duplicate-picker-before.png)). This is a reproduced selection defect: the user cannot identify the intended habit from those labels. No choice was submitted during this check, so a wrong-record write is not claimed.

`RhythmOccurrenceEntity` now includes the normal target at the start of its display subtitle, followed by the existing daypart, date and recorded status. Occurrence IDs and entity lookup are unchanged. The corrected signed build succeeded and was installed without removing the app; a fresh app launch retained both habits at **0/2**. After restarting Shortcuts and reopening **Complete Step**, the user and a fresh [picker screenshot](issue-4/shortcut-duplicate-picker-after.png) confirmed distinct **10 pages · Morning · 2026-09-20** and **One step · Morning · 2026-09-20** subtitles.

The user selected **Read — One step**. A forced app restart at approximately 06:13 showed **1/2**, with **Read / 10 pages** still pending as Next Up and the other Read row completed ([result after selecting One step](issue-4/app-after-duplicate-selection.png)). **The same-name, same-daypart, different-target scenario passes on the corrected build.** The screenshot establishes the visible selected result; raw record IDs were not extracted. No new core regression test was added for this display-only change; the real Shortcuts picker and selected-habit result were tested on device.

## Unavailable App Group and recovery

At approximately 06:16, a local copy of the corrected signed build was used as a negative fixture. Only the main app's `DailyRhythmAppGroup` Info.plist setting was changed to the unprovisioned `group.com.lumetechllc.DailyRhythm.validation-unavailable`. The fixture was re-signed with the original development certificate and entitlements; both main-app and embedded-widget signatures were verified before the successful installation. No Apple Developer account settings or existing shared-store files were changed, and the app was not uninstalled.

Launching the fixture showed **Your rhythm couldn't be refreshed** and **Daily Rhythm cannot access its shared storage**, with a Retry button ([unavailable-group screen](issue-4/app-unavailable-group.png)). It did not present zero habits, a new empty-store creation flow, or a successful write. This tests runtime container access failure, separately from the initial provisioning build failure.

The original correctly configured signed build was immediately reinstalled. A fresh launch at approximately 06:17 recovered **2/2**, **2 full**, **0 light**, and both completed Read targets ([restored app](issue-4/app-restored-after-group-failure.png)). **Visible error handling and recovery pass.** Raw file bytes were not extracted, and this fresh-process failure does not establish preservation of an already-loaded in-memory screen during a subsequent read failure.

## Lock-state observations

The user reported locking the phone, invoking **Undo a step in Daily Rhythm** through Siri and undoing **Read / 10 pages** without manually unlocking. Foregrounding the app at approximately 06:19 showed **1/2**, with **10 pages** pending and the other Read still completed ([app after Siri undo](issue-4/app-after-siri-undo.png)). This confirms the resulting ordinary Shortcut mutation, not schema-driven Siri AI support.

The first tool query after the user reported completion returned `passcodeRequired: false` and `unlockedSinceBoot: true`; the app could then be launched normally. **Authentication state during the action itself is unverified.** The reported locked-screen interaction is recorded, but it is not treated as conclusive proof that the action executed while authentication remained locked; Face ID may have unlocked the device before the query.

## Device matrix

Each row requires an actual result. `Pending` means no pass is claimed. Tests involving corrupt files must use disposable test data, preserve an exact backup, and restore it after the check.

| Case | Procedure / required observation | Result |
| --- | --- | --- |
| Signing and shared container registration | Verify both signed entitlements and embedded profiles contain the exact group; install and inspect the device's registered container. | **Pass:** both signatures/profiles/configuration agree; installation and shared-container registration succeeded. Runtime access is checked by the create/relaunch row. |
| App create and relaunch | Create a daily reading habit through the UI; record its UUID; terminate/relaunch and check the same habit. | **Partial:** UI creation and visible persistence pass after process restart; Read / 10 pages / Morning / 2 pages light step remains pending (0/1). Raw UUID verification is pending because the device transfer service restricts access to the root-level store. |
| Widget to app | Add small/medium widgets; complete a named step in the widget; foreground/relaunch the app and compare the persisted occurrence. | **Partial:** small-widget full/light and medium-widget full completions pass visually after app restart. The medium widget completes the remaining 10 pages habit, yielding 2/2 with both targets full. Raw ID/timestamp checks remain pending. |
| App to widget | Undo/complete in the app; compare saved data immediately and widget rendering after WidgetKit reload. Record latency separately. | **Partial:** after app Reopen, the user observed the small widget immediately return to Read / 10 pages and 0/1. Measured latency, raw data and app completion-to-widget checks remain pending. |
| Ordinary Shortcuts | Run Create Habit, Complete Daily Step and Undo Daily Step; confirm each mutation in the app and shared store. This does not establish schema-driven Siri AI support. | **Partial:** all three discover and execute successfully. Undo returns the foreground app to 0/1; two Complete runs yield one full completion after restart; Create adds a pending Read / One step while retaining Read / 10 pages as completed. Raw record identity and timestamp are still unverified. |
| Duplicate completion | Repeat completion across two surfaces, including competing full/light requests; retain the first timestamp and outcome until explicit Undo. | **Partial:** two full completions via Shortcuts leave one visible full completion after app restart. Competing outcomes, cross-surface overlap and the original timestamp remain unverified. |
| Duplicate names | Create same-name habits with different targets, including the same daypart; select one exact occurrence and confirm the other remains pending. | **Pass for the tested visible scenario after fix:** the picker distinguishes targets; selecting Read / One step completes that item and leaves Read / 10 pages pending after app restart. Baseline indistinguishable rows are preserved as failure evidence. |
| Stale widget / archive | Keep an old widget entry, archive its habit in the app, then invoke the old button; reject unavailable work without changing another item. | Pending |
| Midnight | Invoke an occurrence captured before the date boundary after the boundary; preserve its exact identity and never complete tomorrow's item. | Pending |
| Locked after first unlock | Lock the iPhone after a successful unlock; exercise a widget/Shortcut and record saved data or an honest system/app rejection. | **Partial:** user reports successful Siri Undo while on the locked phone; app subsequently shows the selected 10 pages item pending. The post-action lock query says passcode not required, so authentication state during execution remains unverified. |
| Before first unlock after restart | Before first unlock, attempt the action if the OS permits it; record protection/system denial and verify data survives the first unlock. | Pending |
| Missing App Group | On an isolated misconfigured test build, show an honest storage failure and no alternate store; reinstall the correctly signed build and recover the original records. | **Pass for observed runtime failure/recovery:** the signed negative fixture shows an access error without an empty-store flow; reinstalling the original build recovers both completed targets at 2/2. Raw byte identity was not measured. |
| Concurrent app / extension | Trigger overlapping app/widget writes and compare final IDs, outcomes and timestamps; no lost distinct writes or duplicate record. | Pending |
| Corrupt / unsupported storage | In the disposable fixture, inject malformed JSON and then a future version; read/write attempts must fail without overwriting either file; restore the backup and verify recovery. | Pending |
| Last good state on read failure | Load valid state first, induce a read error, refresh and confirm the app retains its previous visible state while showing the error. | Pending |

The existing 14 host XCTest cases cover several corresponding core behaviours, but they do not turn any pending device row into a pass. Add regression tests only when a concrete defect is reproduced and fixed.

## Local commands

```sh
# Use the existing physical test iPhone; do not select a replacement Simulator.
RHYTHM_DEVICE_UDID='<selected physical iPhone UUID>'
RHYTHM_DEVELOPMENT_TEAM='<existing Apple development team>'
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -configuration Debug -sdk iphoneos \
  -destination "id=$RHYTHM_DEVICE_UDID" \
  -derivedDataPath /tmp/daily-rhythm-issue-4/DerivedData \
  DEVELOPMENT_TEAM="$RHYTHM_DEVELOPMENT_TEAM" \
  -allowProvisioningUpdates build
```

Temporary build logs are under `/tmp/daily-rhythm-issue-4/`. Keep raw account/device data local. Record the final build and observed device outcomes here before closing #4.

## Closure

All four issue acceptance criteria remain open until the relevant device rows are demonstrated. Use `Refs #4` while any required check remains pending or blocked.
