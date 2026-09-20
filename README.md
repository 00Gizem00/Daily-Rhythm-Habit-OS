# Daily Rhythm & Habit OS

**Your next small step, wherever you are.**

Daily Rhythm is an English-language native iOS app for small routines that survive busy days.

**Status: first implementation milestone.** The local habit loop, SwiftUI screens, interactive widgets and ordinary Siri Shortcuts are implemented in source. Device validation remains necessary before TestFlight. This is not a finished App Store release.

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
3. For a physical device, select your development team for both app and widget targets. Register/enable the same App Group, `group.com.lumetechllc.DailyRhythm`, for both bundle IDs. If you change it, update the project's `APP_GROUP_IDENTIFIER` build setting too.
4. Run the app, add a habit, then add a Daily Rhythm widget to the Home Screen.

The app intentionally reports a storage error if the App Group cannot be opened. It never silently creates a second store that diverges from the widget.

Run the core tests on a Mac:

```sh
swift test --package-path Packages/DailyRhythmCore
```

Build the app and widget without device signing:

```sh
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The Xcode project is checked in. After adding or removing Swift source files, run `python3 scripts/generate_project.py`. CI checks the generated project, runs the core tests and builds both targets. Personal signing edits may need to be reapplied after regeneration.

## Next milestones

Official **iOS 27 Siri AI App Schemas**, optional **PCC Build My Routine**, and **Routine Sessions with Live Activities / Dynamic Island** remain planned. The current Shortcuts implementation does not claim schema-driven Siri AI integration. StoreKit, notification scheduling, data export and habit editing are also outside this first slice.

Read the [product plan](docs/PRODUCT_PLAN.md) and [implementation notes](docs/IMPLEMENTATION.md) for architecture, remaining work and device checks.
