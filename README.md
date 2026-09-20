# Daily Rhythm & Habit OS

**Your next small step, wherever you are.**

Daily Rhythm is an English-language native iOS app for small routines that survive busy days.

**Status: first implementation milestone.** The local habit loop, SwiftUI screens, interactive widgets and ordinary Siri Shortcuts are implemented in source. Device validation remains necessary before TestFlight. This is not a finished App Store release.

**Validation:** all 14 core tests and the unsigned iOS Simulator build of the app and widget passed locally on 20 September 2026 with Xcode 27.0 / Swift 6.4. A habit created through the UI also survived process termination and relaunch on the existing iPhone 17 Pro / iOS 26.5 Simulator using an ad hoc signed build. The unsigned build logged a nonfatal App Shortcuts SSU archive error; Siri behaviour remains unverified. See the [native validation evidence](docs/IMPLEMENTATION.md#issue-3-native-validation--20-september-2026) for commands, the tested commit and outstanding device checks. The original [GitHub Actions run](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/actions/runs/35479213534) remains blocked by the account billing issue.

## In this milestone

- **Today / Next Up:** a clear next action and morning, afternoon and evening groups.
- **Flexible targets:** record a full goal or a user-defined small step separately.
- **Reliable history:** daily or selected-weekday recurrence, idempotent completion, undo, archive and seven-day history.
- **Daily Close and weekly rhythm:** separate full/light/skipped/remaining totals, accessible day tiles and a read-only preview of tomorrow's first planned step. See [review verification](docs/verification/ISSUE-13-REVIEW-VALIDATION.md) for tests and pending visual checks.
- **Optional local notifications:** Habits → Notifications enables timed-step reminders and Daily Close independently. Both start off; permission is requested only after enabling one. A bounded seven-day schedule refreshes from saved state, and taps open a read-only view of the original step or day. See [notification verification](docs/verification/ISSUE-14-NOTIFICATIONS-VALIDATION.md) for 115 passing core tests, native builds and device checks.
- **Shared local storage:** app, widget and intents use the same locked, atomically written App Group store.
- **Data & Privacy:** free, offline JSON/CSV export and JSON recovery into an empty app. Local erase requires typing `ERASE`; a persistent recovery marker blocks old drafts and delayed writes, and interrupted cleanup can be retried. See [export and erase verification](docs/verification/ISSUE-15-DATA-PRIVACY-VALIDATION.md) for 131 passing core tests, 31 native Simulator model/service checks and remaining UI/device checks.
- **Accessibility and feedback:** adaptive text colours, wrapping large-text layouts, named VoiceOver actions and optional foreground completion haptics. See [accessibility verification](docs/verification/ISSUE-16-ACCESSIBILITY-VALIDATION.md) for 79 native model/colour checks and the still-open visual/VoiceOver/device walkthrough.
- **Widgets:** small and medium Home Screen widgets, plus Lock Screen progress.
- **Siri Shortcuts:** create a habit, complete a daily step and undo a completion through ordinary App Intents.
- **Free plan:** three active recurring habits, enforced atomically for creation and restoration. One-off tasks and archived habits do not count; existing data and completion stay available above the limit. See [policy verification](docs/verification/ISSUE-6-FREE-POLICY-VALIDATION.md).
- **Plan management:** create one-offs or recurring habits, set date-only/timed due values and duration, edit one pending step or a future schedule, and restore archived plans. See [management verification](docs/verification/ISSUE-7-MANAGEMENT-VALIDATION.md) for executed checks and pending UI cases.

The core targets **iOS 18+** and works without an account, network or AI service. No demo habits are silently inserted into the user's data.

## Open and run

Requirements: **Xcode 16 or later**, Swift 6 and an iOS 18+ simulator or device. No package manager installation is needed.

1. Open `DailyRhythm.xcodeproj`.
2. Select the **DailyRhythm** scheme and an iPhone simulator.
3. Physical-device signing defaults to **LumeTech L.L.C. (`U54BLJMYG6`)**, the team that owns both bundle IDs and the App Group. The app, widget and schema tests inherit that team from the project; the project generator preserves it. Use an Xcode account with access to this team. For a fork using another team, update `DEVELOPMENT_TEAM` and the identifiers in `scripts/generate_project.py`, then register the App Group and assign it to both app IDs in Apple Developer. Enabling App Groups alone is insufficient: both profiles must contain the assigned group. The current group is `group.com.lumetechllc.DailyRhythm`; bundle IDs are `com.lumetechllc.DailyRhythm` and `com.lumetechllc.DailyRhythm.Widgets`.
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

The Xcode project is checked in. After adding, removing or renaming Swift source files, run `python3 scripts/generate_project.py`. If Xcode has this project open, use **File → Close Project**, then reopen `DailyRhythm.xcodeproj` and keep the same run destination. Cleaning build products alone does not reload source membership. The generator atomically replaces changed files and leaves identical files untouched. Each target checks its loaded source list before compilation and gives this recovery instruction if it is stale. CI validates the project and guard, runs core tests and builds both product targets. Make durable signing-setting changes in the generator so regeneration retains them.

## Next milestones

Production **iOS 27 Siri AI App Schemas**, optional **PCC Build My Routine**, and **Routine Sessions with Live Activities / Dynamic Island** remain planned. The default Shortcuts implementation does not claim schema-driven Siri AI integration; the reminder schema prototype is opt-in. StoreKit remains separate work. The [v2 core model](docs/MODEL-V2.md) provides one-off/timed items, future edits, per-occurrence overrides and lossless v1 migration used by management and local reminders.

Read the [product plan](docs/PRODUCT_PLAN.md) and [implementation notes](docs/IMPLEMENTATION.md) for architecture, remaining work and device checks.

Physical-device shared-storage validation is tracked in the [issue #4 device matrix](docs/verification/ISSUE-4-DEVICE-VALIDATION.md). Pending rows are not release evidence.
