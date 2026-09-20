# Issue #16 — accessibility and feedback

Date: 20 September 2026. Refs #16; **the issue remains open**. This is a source audit, implementation pass and native model/colour verification, not a completed accessibility walkthrough.

## Changes and reasons

- The previous coral and leaf text on the light canvas measured 3.28:1 and 4.01:1 respectively. App and widget now share adaptive foreground colours; muted text is also darker in light appearance. Primary app buttons invert with appearance, and filled widget buttons retain white text on a separate dark fill.
- Accessibility text sizes replace the fixed 104-point progress ring with wrapping progress text. Today action groups, occurrence rows, result/Undo and the load-error banner use vertical layouts. Creation uses an inline plan-type picker instead of compressed segments; returning onboarding can scroll. Button labels wrap without a text-size cap.
- Inline actions have a 44-point minimum inside the button style's hit-test content. The whole occurrence title/status/date opens its plan. VoiceOver labels name the plan, target and action; headings support navigation. Saved results distinguish full, light, skip, postpone and reopen in text, with foreground VoiceOver announcements. “Skip step” also avoids describing an earlier-day carryover as today's plan.
- Completion animation is scoped to the progress ring, rather than moving the entire Today layout. Reduce Motion removes that animation. Existing outcome words and symbols remain available independently of colour or motion.
- Only a successfully saved full/light completion increments the app feedback event. Skip, Later, Reopen, Undo, refresh, rejected actions and clearing app state do not. The root view gates system success feedback on foreground activity, no save/load error, no privacy operation, and the local **Habits → Feedback → Completion haptics** preference. This preference resets with local erase and is not part of a backup. No custom background Siri/widget feedback is added.
- Widget action labels have 44-point minimums. Medium widgets show two steps plus an Open Today label to leave room for these controls. Accessibility summaries have a shorter Open Today fallback if the full summary is too tall. These actual WidgetKit layouts still require visual validation.

## Executed checks

Final source commit: `ac54e83dd25e61a722157c3dd2c7337426dbbfd7`.

| Check | Actual environment/result |
| --- | --- |
| Existing Simulator | iPhone 17 Pro, iOS 26.5, `A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6`; already booted, no device/runtime changes |
| Native app/widget compilation | Xcode 27.0 (`27A266a`), Debug, ad hoc Simulator signing; succeeded; strict bundle signature verification passed |
| Accessibility model/colour suite | **79 checks passed**: 19 model/storage assertions and 60 resolved-colour pair checks |
| Contrast sampling | UIKit-resolved light/dark and normal/increased-contrast traits; ink/muted/coral/leaf on canvas/card/composited Next Up; widget leaf/coral on system background and white text on filled button. All sampled pairs ≥4.5:1; minimum **5.038:1**. These are colour calculations, not screenshot or whole-screen compliance evidence. |
| Privacy suite after runner changes | **31 checks passed**, including export, restore, stale generations and owned-data cleanup through real iOS services in a disposable app |
| Persistence/isolation | Both suites preserved store bytes after a normal cold launch, kept the original product store/lifecycle/migration-backup hashes unchanged, and removed their unique test apps |
| Project source membership | Generator and `--check` passed; guard remains enabled for all targets with script sandboxing enabled |
| Open Xcode session | Closed/reopened only DailyRhythm after adding the shared palette, preserving **Any iOS Device (arm64)**. Final **Build Succeeded at 17:14 TRT**; no connected phone required |

The native runs used a working tree based on `d43bea5a4039f329d3819cf311ae206630e6c56d`. Their compiled AppModel, Theme, RhythmPalette and widget files match the final source commit byte-for-byte. The final root-view announcement and additional load-error feedback gate were added after those test snapshots and compiled in the final Xcode Build. No runtime announcement/gating proof is claimed.

Evidence: [accessibility result](issue-16/accessibility-result.json), [privacy regression result](issue-16/privacy-result.json), [native helper](issue-16/AccessibilityValidation.swift). The helper is outside production source membership and is copied only into a temporary app with its own bundle ID and App Group. No user backup is read. The existing runner now accepts `--suite accessibility`; its default privacy suite is preserved.

```sh
python3 scripts/validate_privacy_simulator.py \
  --device A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 --suite accessibility
python3 scripts/validate_privacy_simulator.py \
  --device A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6
```

Only an explicitly supplied, already booted Simulator is accepted. The helper checks real AppModel/store behaviour, including stale repeated completion, another writer's change, and an unreadable fixture store. It does not inject UI events or emulate physical haptics. Core storage code and the generator/guard implementation were unchanged, so their full suites were not rerun for this UI change; previous results are recorded in the earlier verification documents.

The Simulator build still logs the previously seen nonfatal App Shortcuts SSU archive error while ending with BUILD SUCCEEDED. The colour fixture uses the deprecated but available `UITraitCollection(traitsFrom:)` initializer; this is a fixture warning, not a product-source warning. Neither output is evidence of Siri dispatch.

## Remaining acceptance checks — open

Device Hub (`com.apple.dt.Devices`) returned computer-use timeout `-10005` both directly and after **Xcode → Open Developer Tool → Device Hub**. Xcode itself was accessible. No app screenshots, layout measurements or VoiceOver walkthrough could be obtained. No mockups, off-screen renders or model checks substitute for them.

- [ ] Actual VoiceOver create/full/light/skip/Undo/edit/export walkthrough, focus order, announcements and error recovery.
- [ ] Largest Dynamic Type, long titles/targets, keyboard and sheet navigation in portrait and landscape; light/dark and increased contrast on actual screens.
- [ ] Reduce Motion transitions and recognisable states without colour, including History and empty/error screens.
- [ ] Real small/medium/accessory widget layout, redaction, accented/tinted rendering and control hit areas. Specifically check the larger small-widget buttons and two-row medium layout for clipping.
- [ ] Supported physical-device haptics, app preference off/on, iOS settings, failures and background actions. The user has said the phone will not be connected; these checks are deferred.

Do not close #16 or claim TestFlight readiness until these checks have actual evidence. This work does not mark the outstanding #9/#12/#13 surface checks as complete. Phone backup recovery is separate and remains pending.

Design references: [Apple testing system accessibility features](https://developer.apple.com/documentation/accessibility/testing-system-accessibility-features-in-your-app), [Dynamic Type](https://developer.apple.com/videos/play/wwdc2024/10074/), [system haptics guidance](https://developer.apple.com/design/human-interface-guidelines/playing-haptics), and [W3C text contrast calculation/threshold](https://www.w3.org/WAI/WCAG21/Understanding/contrast-minimum). These informed implementation and checks, not a certification claim.
