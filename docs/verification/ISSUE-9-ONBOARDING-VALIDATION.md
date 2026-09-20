# Issue #9 — onboarding verification

Tracking: [#9](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS/issues/9). Tested source: `70ab020efc7921ccd4037867cbcf495aa492c148`, based on merged PR #37 (`e6982c9`). Later changes in this branch only add documentation and a screenshot.

**Status: implementation and automated checks complete; manual acceptance remains open.** Use **Refs #9**. In particular, an unassisted tester's first completion and its elapsed setup time have not been observed. Core tests are not a substitute for that acceptance criterion.

## Executed checks

20 September 2026; Apple Silicon, macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`), Swift 6.4 / Swift 6 language mode. Deployment target remains iOS 18.0. Native build used the iOS Simulator 27.0 SDK and both arm64/x86_64 architectures with local ad hoc signing.

```sh
swift test --package-path Packages/DailyRhythmCore
python3 scripts/generate_project.py
python3 scripts/generate_project.py --check
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/daily-rhythm-issue-8/DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
git diff --check
```

The prior issue's DerivedData directory was reused; the current source was rebuilt. Logs are `/tmp/daily-rhythm-issue-9/tests.log`, `build.log` and `final-build.log`.

| Check | Actual result |
| --- | --- |
| Core suite | **79 XCTest cases passed, zero failures**, 0.512 seconds total. Ten new onboarding regressions. |
| App/widget build | **BUILD SUCCEEDED**. An initial NavigationLink overload caused a Swift type-check timeout; its explicit destination/label replacement compiled successfully. Ad hoc signed-binary stripping warnings remain. |
| Project / whitespace | Passed. Three new app-only files registered by the deterministic generator; package sources discovered by SwiftPM. |
| Returning-user smoke | Final build installed/launched on the same iPhone 17 Pro / iOS 26.5, `A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6`. [Actual screenshot](issue-9/returning-user-smoke.png) shows Today with the existing Read habit and no onboarding modal. Read-only store check: v3, one habit, zero records. |

No Simulator was created, erased, deleted, replaced or moved to another runtime. Existing app data was retained. No first-install test is inferred from a returning-user launch.

## Behavioural regressions

- Both templates validate and remain unsaved values. Draft edits, serialization and cancellation create no routine file or hidden sample habits.
- A blank manual draft becomes a real habit only after explicit confirmation, retains its chosen title/targets, and can complete through the same agenda/store service.
- A paused draft round-trips with the same IDs and edited values. Repeating confirmation after a fresh store reload leaves document bytes unchanged.
- Twenty concurrent confirmations of one draft create exactly that routine once. Two competing distinct drafts produce one complete winner, one explicit refusal, and no partial routine.
- Retrying confirmation after a future edit and archive cannot rewrite or restore those habits. An existing manually-created/archived plan prevents another first-run Apply.
- Zero, duplicate, invalid, one-off and oversized draft entries fail before saving; three recurring entries fit Free, and a fourth normal creation is refused.
- An injected save failure leaves no partially-created routine; retry uses the original draft IDs.
- Only unseen empty installations qualify for automatic setup; in-progress/skipped/finished and returning states do not repeatedly interrupt the user.

Local reviewed-draft persistence is a convenience, not the deduplication authority: stable habit IDs and the shared store lock remain authoritative if the UI status write is interrupted. An unconfirmed editor's field changes are intentionally not added to the reviewed draft.

## Official guidance checked

Checked against live official pages on 20 September 2026 and the installed SDK's `_AppIntents_SwiftUI.swiftinterface` (`ShortcutsLink`, iOS 16+):

- [Apple: add/edit/remove widgets](https://support.apple.com/guide/iphone/iphb8f1bf206/ios) — Home Screen long press → Edit → Add Widget → choose app/size → Add Widget. The app's help follows this sequence; no automatic placement or guaranteed refresh latency is claimed.
- [Apple: run App Shortcuts](https://support.apple.com/guide/shortcuts/apd43295406d/ios) — available app actions appear under App Shortcuts and can be run there. The help names Daily Rhythm and its existing action titles.
- [Apple: use Siri to run shortcuts](https://support.apple.com/guide/shortcuts/apd07c25bb38/ios) — Siri can run a named shortcut; locked-device actions may require unlock. App-named example phrases come from the actual `RhythmShortcuts` source, not a claim of generic reminder routing.
- [Apple Intelligence and Siri AI](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai) remains a separate integration topic. This PR adds no assistant schema conformance, AI availability probe, PCC access or Apple Reminders database link. The in-app text says advanced Siri AI and Build My Routine are not available in this build; #10 is the schema capability gate.

Manual setup invokes no network/account/AI or permission API. Optional future notification permission belongs to the notification feature, not onboarding.

## Unmet walkthroughs

The current Device Hub automation attachment still fails with `-10005: timeoutReached` (fresh attempt recorded during #8). No alternate event injection, Simulator reset or replacement was used. Pending checks:

| Scenario | Required evidence |
| --- | --- |
| First installation | Welcome → choose/edit template or manual goal → Create → Today → first real completion, performed without coaching. |
| Interrupted setup | Pause, terminate/relaunch, resume reviewed draft; confirm exact IDs once. Cancel an editor and verify only reviewed values remain. |
| Returning states | Expanded manual check of existing active/archived habits and a successfully finished setup; the existing-habit launch smoke above covers only one returning state. |
| Accessibility | VoiceOver order/labels and navigation; large Dynamic Type through welcome, review, editor, confirmation and help. |
| Timing | Measure setup presentation to the first real completion for an unassisted tester. **Not measured.** Test-suite duration is not a usability timing result. |
| Siri/widget help | Follow the system Shortcuts link and widget instructions, verify each app-named phrase on a configured device. SDK compilation does not establish recognition. |
