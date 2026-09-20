# Issue #4 — shared storage and cross-surface device validation

Tracking: [issue #4](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/4). This is a device validation record, not a claim that Simulator or host tests establish physical-device behaviour.

## Environment and build

- Date: 20 September 2026, Europe/Istanbul.
- Source baseline: `7a36828c3e585ee8f268e627c6377830cc9bfe53`, current `main` after #31 merged and #3 closed.
- Physical device: iPhone 16, iOS 27.0 (`24A437`), Developer Mode enabled, paired over the local network.
- Toolchain: Xcode 27.0 (`27A266a`), Apple Swift 6.4, iPhoneOS 27.0 SDK.
- App: `com.lumetechllc.DailyRhythm`; widget: `com.lumetechllc.DailyRhythm.Widgets`.
- Required shared group: `group.com.lumetechllc.DailyRhythm`.
- Signed build: **Debug 0.1.0 (1)**, Apple Development signing, built successfully and installed on the physical iPhone at approximately 05:48–05:49.

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

The physical build also logged `Could not archive SSU artifacts` from `appintentsnltrainingprocessor` while returning build success, as in #3. Actual Shortcuts discovery/invocation remains a separate device check; the diagnostic has not been suppressed.

Apple references: [register an App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group), [configure App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).

## Habit creation and process relaunch

The user created the default reading habit through the physical iPhone UI. Their 05:53 screenshot showed **Read**, **10 pages**, **Morning**, a **2 pages** light step, and **0/1** completed, without a storage-error banner.

At approximately 05:56, `devicectl device process launch --terminate-existing` successfully restarted the application. The first capture overlapped the phone's lock screen, so that capture was not treated as a loaded-app result. After the user unlocked the phone, a fresh [device screenshot](issue-4/app-after-relaunch.png) showed the same habit, targets, daypart and pending count, with no storage error. **Visible creation and persistence across process relaunch pass.** Widget and Shortcuts access are separate checks.

The habit's raw UUID has not been extracted. `devicectl device copy from` rejected the App Group root-level `daily-rhythm.json` because its container transfer service allows only `Library`, `Documents` and `tmp` (remote service error 11007). Consequently, the earlier limited directory listing cannot establish whether the store exists. This is a developer-tool access restriction, not evidence of a failed app read/write. No data was moved, replaced or seeded to bypass it. Exact record identity and completion timestamps still require separate evidence.

## Widget observations

After adding the small **Your Daily Rhythm** widget, the user confirmed that it displayed **Read / 10 pages**, matching the habit created in the app. This is user-observed evidence that the widget can read the existing shared data.

The user then tapped **Done** once in that widget. At approximately 06:01, foregrounding the app showed **1/1**, **1 full**, **0 light**, and **Read — Full · 10 pages**, without a storage-error banner ([app after widget completion](issue-4/app-after-widget-done.png)). A subsequent `devicectl device process launch --terminate-existing` and fresh capture showed the same completion ([app after restart](issue-4/app-widget-done-after-relaunch.png)). **The small-widget completion is visible in the app and survives an app process restart.** This establishes the visible full-completion path; raw occurrence identity/timestamp and the medium widget remain unverified.

Next, the user tapped **Reopen** on the app's Read row and returned to the small widget. They reported that **Read / 10 pages** and **0/1** returned immediately. **App-to-small-widget undo refresh passes by user observation.** No numeric refresh latency was measured, and the underlying file was not extracted.

At approximately 06:04, after explicitly reopening the step and tapping the small widget's **leaf** button, the user confirmed that the tap had been performed. A forced app restart then showed **1/1**, **0 full**, **1 light**, and **Read — Light · 2 pages** ([light completion after restart](issue-4/app-widget-light-after-relaunch.png)). **The small-widget light-completion path also passes visually and persists across process restart.** An earlier readiness reply had been mistaken for a completed leaf tap; the user clarified that they had not tapped it, so the preceding full-state capture is not a reproduced defect or a light-test result.

## Device matrix

Each row requires an actual result. `Pending` means no pass is claimed. Tests involving corrupt files must use disposable test data, preserve an exact backup, and restore it after the check.

| Case | Procedure / required observation | Result |
| --- | --- | --- |
| Signing and shared container registration | Verify both signed entitlements and embedded profiles contain the exact group; install and inspect the device's registered container. | **Pass:** both signatures/profiles/configuration agree; installation and shared-container registration succeeded. Runtime access is checked by the create/relaunch row. |
| App create and relaunch | Create a daily reading habit through the UI; record its UUID; terminate/relaunch and check the same habit. | **Partial:** UI creation and visible persistence pass after process restart; Read / 10 pages / Morning / 2 pages light step remains pending (0/1). Raw UUID verification is pending because the device transfer service restricts access to the root-level store. |
| Widget to app | Add small/medium widgets; complete a named step in the widget; foreground/relaunch the app and compare the persisted occurrence. | **Partial:** small-widget full and light completions both pass visually and survive app restart: Full · 10 pages yields 1 full / 0 light; after explicit Reopen, Light · 2 pages yields 0 full / 1 light. Exact ID/timestamp and medium-widget checks remain pending. |
| App to widget | Undo/complete in the app; compare saved data immediately and widget rendering after WidgetKit reload. Record latency separately. | **Partial:** after app Reopen, the user observed the small widget immediately return to Read / 10 pages and 0/1. Measured latency, raw data and app completion-to-widget checks remain pending. |
| Ordinary Shortcuts | Run Create Habit, Complete Daily Step and Undo Daily Step; confirm each mutation in the app and shared store. This does not establish schema-driven Siri AI support. | Pending |
| Duplicate completion | Repeat completion across two surfaces, including competing full/light requests; retain the first timestamp and outcome until explicit Undo. | Pending |
| Duplicate names | Create same-name habits with different targets, including the same daypart; select one exact occurrence and confirm the other remains pending. | Pending |
| Stale widget / archive | Keep an old widget entry, archive its habit in the app, then invoke the old button; reject unavailable work without changing another item. | Pending |
| Midnight | Invoke an occurrence captured before the date boundary after the boundary; preserve its exact identity and never complete tomorrow's item. | Pending |
| Locked after first unlock | Lock the iPhone after a successful unlock; exercise a widget/Shortcut and record saved data or an honest system/app rejection. | Pending |
| Before first unlock after restart | Before first unlock, attempt the action if the OS permits it; record protection/system denial and verify data survives the first unlock. | Pending |
| Missing App Group | On an isolated misconfigured test build, show an honest storage failure and no alternate store; reinstall the correctly signed build and recover the original records. | Pending |
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
