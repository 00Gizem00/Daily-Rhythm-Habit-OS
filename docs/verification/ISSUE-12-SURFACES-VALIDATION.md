# Issue #12 — widgets and configured Controls

Tracking: [#12](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/12). **Refs #12**: implementation and executable checks are complete; system-surface acceptance still needs hands-on device evidence.

**Implementation commit:** `38288d1c94c588d6179021192c0d496f47a15950`, based on merged PR #39 (`824d0ef`). Subsequent changes only record documentation/evidence.

## API and behaviour

Verified on 20 September 2026 against Apple's current documentation and installed Xcode 27 (`27A266a`) SDK interfaces. `ControlWidget`, `StaticControlConfiguration`, `AppIntentControlConfiguration`, `ControlConfigurationIntent` and `ControlCenter` support **iOS 18+**, matching the app deployment target. The configuration-only initializer is present in the installed WidgetKit interface. No iOS 27 schema is required for these controls.

- **Open Today:** an `OpenIntent` compiled into both app and extension, with `.today` as its target. The foreground coordinator selects Today and resets that stack, including when the intent runs before the root view subscribes. Widget body taps use a registered custom URL; the URL handler performs the same routing.
- **Complete Habit:** a configured recurring habit UUID, not a changing Next Up selection. The control always requests the full target. Entity queries return all matching names, never the first match; picker subtitles include target/day part/schedule/reference. Archived saved identities still resolve to permit an explanatory error.
- **Atomic resolution:** one `RoutineStore` transaction resolves the chosen habit's occurrence for today's original local planned date, validates readiness and saves. It does not consume an earlier carryover when today's step is already complete. Full/light retries preserve all saved fields. Skip, archive, no scheduled occurrence and Later/future due states refuse mutation with distinct errors. Missing storage propagates the existing preserved-data error.
- **Privacy and refresh:** widget privacy redaction substitutes neutral content without completion buttons or private accessibility strings. Controls mark configured names sensitive. Widget/control completion requires local device authentication. Reload requests cover both surfaces after mutations; timing remains system-managed.
- **Timeline:** unique Later deadlines, a timed due date's anchored civil midnight and next local midnight are prepared ahead. DST uses calendar arithmetic. Visible-widget writes retain explicit occurrence/revision identity and recheck the full snapshot plus agenda membership under lock.

Official references: [creating controls and opening the app](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system), [configuration and action hints](https://developer.apple.com/documentation/widgetkit/adding-refinements-and-configuration-to-controls), [local control reloads](https://developer.apple.com/documentation/widgetkit/updating-controls-locally-and-remotely). Setup help uses Apple's [StandBy guide](https://support.apple.com/guide/iphone/iph878d77632/ios) and [Control Center guide](https://support.apple.com/guide/iphone/iph59095ec58/ios). StandBy requires charging/sideways placement and system/user setup; no custom continuous animation, background haptic or exact refresh-time guarantee is made.

## Executed checks

Environment: Apple Silicon macOS 27.0 (`26A428`), Xcode 27.0, Swift 6.4 / Swift 6 mode. Selected existing Simulator remains **iPhone 17 Pro / iOS 26.5 (`23F77`)**. Physical device remains **iPhone 16 / iOS 27.0 (`24A437`)**. No simulator was created, deleted, substituted or moved to a different runtime.

| Check | Actual result |
| --- | --- |
| Core regressions | **95 XCTest cases passed, zero failures**, 0.514 seconds suite duration. Ten new tests exercise identity, identical names, byte-preserving retries, existing light/skip, archived/missing/unscheduled choices, carryovers, civil-day travel, concurrent requests, failed persistence, stale visible widgets and timeline boundaries. |
| Default Simulator app + widget | **BUILD SUCCEEDED**, arm64/x86_64, existing DerivedData and local ad hoc signing. iOS 18 deployment target retained. |
| Signed physical app + widget | **BUILD SUCCEEDED**, existing team/certificate/App Group profiles. Both signatures passed strict verification. Installation and launch on the connected iPhone succeeded. |
| App Intents metadata | Both default app and extension contain `OpenTodayIntent`, `CompleteControlHabitIntent`, `ChooseControlHabitIntent`, `RhythmHabitEntity`. Default app excludes experimental reminder schemas. |
| Schema opt-in compatibility | Physical development build retains the earlier `DAILY_RHYTHM_SCHEMA_SPIKE` flag; app metadata includes that prototype plus the new controls. The extension excludes the schema. This does not enable the flag in the project's default configurations. |
| Simulator launch | Installed/launched on the selected existing iOS 26.5 Simulator. Today still shows the prior Read habit at 0/1, without a storage error. |
| Widget URL smoke | `simctl openurl` reached the OS “Open in Daily Rhythm?” confirmation. **Dispatch beyond that prompt is unverified**, as is Open Today control invocation from another tab. [Actual screenshot](issue-12/simulator-url-confirmation.png). |
| Project / whitespace | Project regenerated for the new shared/control Swift files; `--check` and `git diff --check` passed. |

The initial native builds emitted the previously recorded `Could not archive SSU artifacts` diagnostic while succeeding. Final incremental builds succeeded without repeating the training step/diagnostic. This is not a verified fix for Siri training. The user-assisted Siri creation attempt associated with [PR #39](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/pull/39) produced no visible task; #10 and production #11 remain gated independently of Controls.

Commands:

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py
python3 scripts/generate_project.py --check
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-8/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daily-rhythm-issue-10/DeviceDerivedData \
  OTHER_SWIFT_FLAGS='$(inherited) -DDAILY_RHYTHM_SCHEMA_SPIKE' \
  DEVELOPMENT_TEAM=U54BLJMYG6 build
git diff --check
```

Temporary local logs: `/tmp/daily-rhythm-issue-12/tests.log`, `build.log`, `device-build.log`, `device-install.log`, `device-launch.log`. Device identifiers and provisioning payloads are intentionally absent from the committed evidence.

## Remaining device matrix and closure

UI automation was attempted again: `com.apple.iphonesimulator` is not an available app target; the configured Device Hub (`com.apple.dt.Devices`) still returns `-10005: timeoutReached`. No alternate event injection was used. Native build/install/launch succeeds, but this does not provide interactive layout/placement evidence.

All of these still require actual device observation before closing #12:

1. Place both controls through Control Center, Lock Screen and Action button; confirm Open Today navigates from Habits/History and nested Today views.
2. Configure duplicate names, perform repeated completion, then test archive, missing schedule, skipped and deferred cases through system dispatch; compare app/history and the exact configured ID.
3. Place small/medium/accessory widgets, confirm full/light/skipped/empty/error states, visible-ID completion and stale revisions across concurrent app edits.
4. Observe privacy redaction and authentication while locked, VoiceOver, largest text and long titles on each surface; verify no action is available for hidden widget content.
5. Charge the physical phone sideways with StandBy enabled; add Daily Rhythm and record actual layout, interaction and privacy behaviour. App screenshots or host-rendered views are not StandBy evidence.
6. Leave the app stopped across midnight and Later expiry; observe widget refresh and stale-action handling. Host clock-controlled tests prove scheduling calculations, not iOS delivery latency.
7. Run the same ordinary surfaces on an explicitly selected iOS 18 device/runtime when available. The unchanged iOS 26.5 run is evidence below the iOS 27 schema requirement, not an iOS 18 runtime test.

No acceptance checkbox is represented as fully satisfied by compilation or host tests alone. Keep **Refs #12**, with UI and device checks open.
