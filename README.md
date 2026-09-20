# Daily Rhythm & Habit OS

**Your next small step, wherever you are.**

Daily Rhythm is an English-language native iOS app for small routines that survive busy days.

**Status: first implementation milestone.** The local habit loop, SwiftUI screens, interactive widgets and ordinary Siri Shortcuts are implemented in source. Device validation remains necessary before TestFlight. This is not a finished App Store release.

**Validation:** all 14 core tests and the unsigned iOS Simulator build of the app and widget passed locally on 20 September 2026 with Xcode 27.0 / Swift 6.4. A habit created through the UI also survived process termination and relaunch on the existing iPhone 17 Pro / iOS 26.5 Simulator using an ad hoc signed build. The unsigned build logged a nonfatal App Shortcuts SSU archive error; Siri behaviour remains unverified. See the [native validation evidence](docs/IMPLEMENTATION.md#issue-3-native-validation--20-september-2026) for commands, the tested commit and outstanding device checks. The original [GitHub Actions run](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/actions/runs/35479213534) remains blocked by the account billing issue.

## In this milestone

- **Today / Next Up:** a clear next action and morning, afternoon and evening groups.
- **Flexible targets:** record a full goal or a user-defined small step separately.
- **Reliable history:** daily or selected-weekday recurrence, idempotent completion, undo, archive and seven-day history.
- **Shared local storage:** app, widget and intents use the same locked, atomically written App Group store.
- **Widgets:** small and medium Home Screen widgets, plus Lock Screen progress.
- **Siri Shortcuts:** create a habit, complete a daily step and undo a completion through ordinary App Intents.

The core targets **iOS 18+** and works without an account, network or AI service. No demo habits are silently inserted into the user's data.

## Open and run

Requirements: **Xcode 16 or later**, Swift 6 and an iOS 18+ simulator or device. No package manager installation is needed.

1. Open `DailyRhythm.xcodeproj`.
2. Select the **DailyRhythm** scheme and an iPhone simulator.
3. For a physical device, select your development team for both app and widget targets. Register the App Group `group.com.lumetechllc.DailyRhythm` and explicitly assign it to **both** `com.lumetechllc.DailyRhythm` and `com.lumetechllc.DailyRhythm.Widgets` in Apple Developer. Enabling the App Groups capability alone is insufficient: each App ID must have this group selected, and its development profile must be regenerated after assignment. If you change the group, update the project's `APP_GROUP_IDENTIFIER` build setting too.
4. Run the app, add a habit, then add a Daily Rhythm widget to the Home Screen.

The app intentionally reports a storage error if the App Group cannot be opened. It never silently creates a second store that diverges from the widget.

Run the core tests on a Mac:

```sh
swift test --package-path Packages/DailyRhythmCore
```

Build the app and widget without device signing (compilation check only):

```sh
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

For a launch/persistence check, keep Simulator signing enabled so Xcode embeds the App Group entitlements. Installing the unsigned build above can launch the app but leave shared storage unavailable. Build with a local ad hoc identity, then install on your existing test Simulator:

```sh
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

# Set this to the UUID of your existing, selected test Simulator.
# Find it with: xcrun simctl list devices available
RHYTHM_SIMULATOR_UDID='<your existing test Simulator UUID>'
xcrun simctl install "$RHYTHM_SIMULATOR_UDID" \
  DerivedData/Build/Products/Debug-iphonesimulator/DailyRhythm.app
xcrun simctl launch "$RHYTHM_SIMULATOR_UDID" com.lumetechllc.DailyRhythm
```

In the app, create a habit, terminate the app with `xcrun simctl terminate "$RHYTHM_SIMULATOR_UDID" com.lumetechllc.DailyRhythm`, then launch it again and verify the same habit remains. Do not substitute a direct write to the store for this UI check. Simulator signing does not validate physical-device provisioning.

The Xcode project is checked in. After adding or removing Swift source files, run `python3 scripts/generate_project.py`. CI checks the generated project, runs the core tests and builds both targets. Personal signing edits may need to be reapplied after regeneration.

## Next milestones

Official **iOS 27 Siri AI App Schemas**, optional **PCC Build My Routine**, and **Routine Sessions with Live Activities / Dynamic Island** remain planned. The current Shortcuts implementation does not claim schema-driven Siri AI integration. StoreKit, notification scheduling, data export and habit editing are also outside this first slice.

Read the [product plan](docs/PRODUCT_PLAN.md) and [implementation notes](docs/IMPLEMENTATION.md) for architecture, remaining work and device checks.

Physical-device shared-storage validation is tracked in the [issue #4 device matrix](docs/verification/ISSUE-4-DEVICE-VALIDATION.md). Pending rows are not release evidence.
