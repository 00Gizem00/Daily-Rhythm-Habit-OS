# Official reminder schema capability gate

Tracking: [#10](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/10). Checked 20 September 2026 against Xcode 27.0 (`27A266a`), the installed iOS 27 SDK and current official Apple Markdown documentation. [Verification](verification/ISSUE-10-SCHEMA-VALIDATION.md) records the tested commit and device results.

## Exact SDK contract

The installed `AppIntents.swiftinterface` declares `AppSchema.RemindersIntent`, `RemindersEntity` and `RemindersEnum` with `@available(anyAppleOS 27.0, *)`, excluding watchOS/tvOS. Apple's pages list iOS/iPadOS/macOS/visionOS 27.0. This integration targets **iOS 27+** while the app deployment target remains **iOS 18.0**. Availability annotations and a build opt-in are separate from proof that Siri AI is enabled on a particular device.

| Role | Actual schema / types |
| --- | --- |
| Create | `@AppIntent(schema: .reminders.createReminder)`; returns the app's schema reminder entity. |
| Complete / reopen | `@AppIntent(schema: .reminders.updateReminder)` with `target` and optional `isCompleted`. `true` completes, `false` reopens. There is no `.reminders.completeReminder` in this SDK. |
| Content | `@AppEntity(schema: .reminders.reminder)`; exact occurrence ID, `String` title, optional `DateComponents` due, optional `Calendar.RecurrenceRule`, `Bool` completion, optional creation/completion dates and flag, note, tags, URLs, list and optional location trigger. |
| List | `.reminders.list` with name and `.reminders.listType` (`standard`). The prototype exposes one truthful collection of the app's own one-off tasks. |
| Required vocabulary | Create also requires a section parameter. `.reminders.section` has name/list; `.reminders.locationTrigger` has `GeoToolbox.PlaceDescriptor` and `.reminders.locationTriggerEvent` (`arrive`, `depart`). The prototype has no stored sections or location triggers and never fabricates query results. |

Sources: [reminder entity](https://developer.apple.com/documentation/appintents/appschema/remindersentity/reminder), [list entity](https://developer.apple.com/documentation/appintents/appschema/remindersentity/list), [list type](https://developer.apple.com/documentation/appintents/appschema/remindersenum/listtype), [section](https://developer.apple.com/documentation/appintents/appschema/remindersentity/section), [location trigger](https://developer.apple.com/documentation/appintents/appschema/remindersentity/locationtrigger), [location event](https://developer.apple.com/documentation/appintents/appschema/remindersenum/locationtriggerevent).

“Optional” values still require declared properties/parameters in the conforming Swift type. Omitting unsupported optional fields compiled as Swift but **failed App Intents metadata export**. The finished spike declares the actual required vocabulary and explicitly rejects unsupported supplied values before writing. Its list/section/location entity parameters also require resolution support; the list query uses `EntityStringQuery`, and unsupported section/location queries return no entities.

The current [create schema](https://developer.apple.com/documentation/appintents/appschema/remindersintent/createreminder) requires `title`, optional list/note/flag/due/recurrence/location/section, and nonoptional images/tags/URLs collections. The current [update schema](https://developer.apple.com/documentation/appintents/appschema/remindersintent/updatereminder) requires target plus optional title/note/tags/URLs/due/recurrence/completion/flag/list/location. The compiled implementation follows the installed SDK and current page, rather than assuming extra fields from older cached examples.

## Bounded supported mapping

The capability spike is in `ReminderSchemaSpike.swift`, compiled only with `DAILY_RHYTHM_SCHEMA_SPIKE` and Swift compiler 6.4+. Every schema type is additionally annotated iOS 27+. It is app-target-only; the widget retains its ordinary intents. **Default builds do not expose these schema actions**, and their extracted metadata contains only the ordinary actions. Do not enable this flag for a shipping configuration before #10/#11 acceptance.

- Create makes an app-owned **one-off** using `RoutineStore.addHabit`. The caller's title is also the normal target; no smaller goal or duration is invented. No due components means today's date-only task. A supplied full Gregorian date stays date-only unless hour and minute are both supplied. Timed values preserve a supplied timezone, otherwise using the supplied calendar's/device timezone. Day part follows a supplied hour; date-only tasks use Morning for presentation only, without inventing a due time.
- Incomplete, invalid, non-Gregorian, ordinal/week-based or nonzero second/subsecond date inputs fail instead of being silently normalized into a different request. Existing core DST rules still resolve nonexistent wall-clock minutes forward and repeated minutes to the first instant. The store rejects creating a past one-off.
- All recurrence rules are rejected in this spike, even simple rules the broader model could represent. Repeating templates are excluded from schema queries. Production recurrence and occurrence/future-edit mapping belong to #11.
- Notes, flags, images, tags, links, sections and location-trigger creation inputs are rejected if supplied (empty required collections mean no input). The entity's read-only note is a projection of the saved target/result for disambiguation, not a new persisted note field. The list is the app's one-off collection. No location permission is requested.
- Update supports `isCompleted` only. Other supplied edits, including an accompanying title or due change, refuse the entire request before mutation. Completion uses full outcome and `.appIntent` source. Existing full/light results keep their original timestamp/source on repetition. Skip cannot silently become completion. Reopen clears the selected result through the shared store. Every operation uses the exact stable occurrence ID and a freshly read expected revision.
- Reads expose one-offs at their original identity, including postponed ones. They never substitute tomorrow's recurring step. The reminder boolean projects full/light as completed and skip as not completed; result context stays visible in its subtitle. App history retains the distinct underlying outcomes.

One-offs intentionally do not consume the three-active-recurring-habit limit. The schema does not bypass the policy-aware store. A future recurring adapter must go through that same store and its Free activation checks.

## Authentication and execution

Both prototype intents explicitly set `supportedModes = .background` and `authenticationPolicy = .requiresLocalDeviceAuthentication`. This chooses on-device unlock before system-dispatched execution; it does not claim that direct Swift calls enforce authentication. The default AppIntent authentication policy is `alwaysAllowed`, so relying on the default would represent a different contract. See [supported modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes), [authentication policy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy), and [policy cases](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy).

Adopting a schema is not Apple Reminders synchronization, generic “remind me” routing, guaranteed recognition, or a complete Siri integration. Apple also describes entity indexing, transferable content, context and donation in its [Siri AI integration guidance](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai). These broader production surfaces are not claimed by this minimal capability gate.

## Building and reproducing the device check

The build flag uses `OTHER_SWIFT_FLAGS` so it does not overwrite the widget's existing `WIDGET_EXTENSION` compilation condition:

```sh
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daily-rhythm-issue-10/DeviceDerivedData \
  OTHER_SWIFT_FLAGS='$(inherited) -DDAILY_RHYTHM_SCHEMA_SPIKE' \
  DEVELOPMENT_TEAM='<existing configured team>' build
```

Only the **Debug + opt-in** build includes `ReminderSchemaSmoke`. Launching with `DAILY_RHYTHM_SCHEMA_SMOKE=<fresh UUID>` runs the real create/update `perform()` methods in the signed app, reloads each persisted result, confirms repeated completion is unchanged, and archives its own new test task through the normal API. It compares pre-existing plans/results before and after. A report in `Documents/schema-smoke-<UUID>.json` records actual outcomes and explicitly identifies direct adapter invocation. Reusing a report UUID cannot add another test task. No harness runs in normal launches or default/Release builds.

This device check is useful native adapter evidence, but it bypasses Siri/Shortcuts resolution and system authentication enforcement. It therefore **cannot close #10** by itself. A configured user must also invoke the actual schema actions through Siri/Shortcuts, capture the resulting app state and record Siri AI state, Siri language, region and lock state. #11 must not treat this spike as a verified shipping Siri capability.
