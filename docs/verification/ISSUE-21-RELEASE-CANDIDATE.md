# Issue #21 — local Release candidate and pilot preparation

20 September 2026. **HOLD for TestFlight; Refs #21, not Closes.** A signed local candidate and a reviewable pilot packet exist. No upload, distribution, invitation, pricing/billing change or contact with testers occurred. The phone remains disconnected as requested.

## Candidate identity

| Item | Recorded value |
| --- | --- |
| Final production source | `a5127fade21ae2ca3e3e7d22ec1ca96e4b33b02c` |
| Packaging/cleanup implementation | `b38a9235a9cc828e581e89b3fab3d81c1c090f7e`; final source adds the owner-confirmed support email |
| Version / build | **0.1.0 (2)** for both app and widget; previous local build 1 |
| Scheme/configuration | DailyRhythm / Release; default ordinary intents, no schema-spike flag |
| Toolchain | Xcode 27.0 (`27A266a`), Swift 6.4, device SDK iOS 27; deployment target iOS 18.0; iPhone and iPad families retained |
| App / extension IDs | `com.lumetechllc.DailyRhythm` / `com.lumetechllc.DailyRhythm.Widgets` |
| Signing / shared data | LumeTech team `U54BLJMYG6`, `group.com.lumetechllc.DailyRhythm` unchanged |
| Local signing class | **Apple Development**, both `get-task-allow: true`; not an App Store distribution export |
| Final archive | Repository-local ignored `ReleaseArtifacts/0.1.0-2/DailyRhythm.xcarchive` |
| Review ZIP | `ReleaseArtifacts/0.1.0-2/DailyRhythm-0.1.0-2-development.xcarchive.zip` |
| ZIP SHA-256 | `9af5805aba7fea317c7441413ea7d0f1276110465769be68fff9321c7653a2b6` |

The archive was built after the final production-source commit. Subsequent repository changes contain documentation/evidence only. Binary hashes, matching dSYMs, intent names and profile-expiry summaries are in [archive inspection](issue-21/archive-inspection.json). Provisioning profiles and signed binaries stay in the local ignored artifact directory; private device lists/certificates are not copied to the repository. The older local archive without the support link is retained under `superseded-before-support-link` and is not this candidate.

Only development identities were available in the local signing inventory. This does not prove whether cloud-managed distribution signing is available to the account. App Store Connect was not checked during the archive run. The later registration check is recorded below and in the [release runbook](../release/README.md); distribution validation, processing and beta review remain unverified.

## Changes

- Added original geometric app artwork, an opaque sRGB 1024×1024 PNG, with its reproducible Core Graphics source. The asset catalog is included only in the app; both iPhone/iPad icon metadata are present in the archive. This artwork is not a screenshot of the running app.
- The generator now owns build **2** and app-icon resource/settings. Source-list guards and script sandboxing stay enabled. The application/extension bundle IDs, App Group and store schema did not change.
- Added **Habits → Help & Beta** with runtime version/build, owner-confirmed **Contact@lumetechllc.com**, TestFlight feedback guidance, optional diagnostic sharing, backup/update advice and honest feature scope. The mail link opens an email composer; no message or attachment is sent automatically.
- Fixed an erase cleanup omission found during the audit: the completion-haptic preference now resets with local data erasure. A native Release regression explicitly seeds the preference and checks its removal.
- Added a read-only archive-inspection command and an isolated old-Debug-to-new-Release upgrade runner. These do not upload anything or alter Simulator devices/runtimes.
- Prepared [release notes, tester instructions, 14-day protocol, feedback/decision templates and privacy/support draft](../release/README.md). Public support email is supplied; public URLs and private Review contact remain open.

## Executed validation

| Check | Actual result / scope |
| --- | --- |
| Release core tests | **148 passed, zero failures**, 18:32:12 TRT. Release optimization enabled. Storage schema/core sources are unchanged in this candidate. |
| Generator/guard suite | **4 tests passed** after generator changes; project generation and `--check` passed. |
| Signed Release archive | **ARCHIVE SUCCEEDED** for final source; app and widget signatures validated; App Group matches signed entitlements and embedded profiles; version/build match; app and widget dSYM UUIDs match binaries. |
| Release integration privacy suite | **32 native model/service checks passed**, including export/restore/erase, stale generation handling and the added haptic cleanup. [Actual report](issue-21/privacy-release-result.json). This is not share-sheet interaction. |
| Upgrade fixture | **Passed**: an isolated ad hoc signed build 1 from `7bbba332748aba193455fcb0a1d259d9f1133424` was seeded, then replaced in place with a Release build 2 using the same test bundle/group. Four plans, full/light/skipped/pending data, archived plan, diagnostics, reminder preferences, completed setup, haptic choice and a JSON backup survived. A second launch preserved them too. [Actual report](issue-21/upgrade-result.json). |
| Upgrade boundaries | The old Debug app contains a fixture seeder; the Release test app contains a read-only preference/model probe. Neither helper is in the product archive. Source comparison is recorded [here](issue-21/source-verification.json). Only the support mail link was added after the fixture snapshot; it compiled in the final archive. This is synthetic Simulator data, not a physical/TestFlight upgrade of the user's records. |
| Environment/isolation | Existing booted iPhone 17 Pro / iOS 26.5, `A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6`. No other Simulator selected, created, deleted, reset or changed. Original product store hashes stayed unchanged; disposable apps were removed. The user's exported backup was not read or modified. |
| Release feature exclusion | Archive metadata includes the seven ordinary app/widget/control intents and no schema-spike intents. Debug recovery/seed entry-point strings are absent. PCC, purchases and routine-session Live Activities remain unimplemented. |
| Xcode reload | Closed/reopened only DailyRhythm after project generation, preserving **Any iOS Device (arm64)**. Final actual Xcode **Build Succeeded at 18:46 TRT**, including the support link. |
| Static checks | `git diff --check`, project check and Python syntax checks passed. |

Initial upgrade-harness attempts stopped before/at verification: they assumed a preference plist was immediately flushed and that the container's path UUID could not change. A focused check showed the seeded Boolean reached disk about ten seconds later; the runner now waits for fixture persistence, reads post-upgrade preferences through native UserDefaults, and compares data contents rather than container path UUIDs. Final native reads preserved the preference. No product persistence change was made to hide those harness failures.

The Release privacy suite compiled the final erase change; the final static mail link was added afterward. Test helpers explicitly use temporary app IDs/groups and no UI event injection. The successful archive still logs the known nonfatal SSU-artifact diagnostic and a warning about not stripping an already signed embedded extension. They are not suppressed and do not establish Siri training/discovery.

Reproduction:

```sh
python3 scripts/generate_project.py --check
python3 -m unittest discover -s scripts -p 'test_*.py'
swift test --package-path Packages/DailyRhythmCore --configuration release
python3 scripts/validate_privacy_simulator.py \
  --device A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 --suite privacy --configuration Release
python3 scripts/validate_upgrade_simulator.py \
  --device A846DE14-5BB1-4F7E-9EEC-D4310CEB07F6 \
  --baseline 7bbba332748aba193455fcb0a1d259d9f1133424
xcodebuild -project DailyRhythm.xcodeproj -scheme DailyRhythm \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/daily-rhythm-issue-21/DerivedData \
  -archivePath /tmp/DailyRhythm-review.xcarchive archive
python3 scripts/inspect_release_archive.py /tmp/DailyRhythm-review.xcarchive
```

## Core beta gate — unresolved rows stay open

| Gate | Current evidence and required next evidence |
| --- | --- |
| Signed physical install/upgrade with real data | No phone connected. Simulator upgrade passes; physical upgrade/export verification on this exact candidate remains required. Previously staged phone recovery remains separate and unverified. Never erase personal data for this check. |
| Correct occurrence, duplicates and shared storage (#3/#4/#8) | Release core tests and synthetic upgrade pass. Repeat foreground/background/locked and stale/duplicate-name actions from real app/widget/ordinary Shortcuts on the candidate. Prior-device evidence is not automatically current-candidate evidence. |
| Setup (#9) | Native model coverage exists. Fresh-user create-to-complete walkthrough, help required and actual timing remain open. |
| Widgets/controls/review (#12/#13) | Candidate compiles. Actual small/medium/accessory/control, StandBy, redaction, light/dark and History/Daily Close screens remain open. |
| Notifications (#14) | Scheduling tests pass historically; real candidate permission/grant/deny/revoke, delivery, tap identity and extension scheduling still need device evidence. |
| Export/restore/erase (#15) | 32 native Release checks pass. Real picker/share/cancel, typed erase confirmation, post-erase widget state and device upgrade/export remain open. |
| Accessibility/feedback (#16) | Earlier 79 native model/colour checks exist. Current screen VoiceOver, largest Dynamic Type, Reduce Motion, focus and physical haptics are not verified. |
| Diagnostics (#20) | Earlier 148 core/27 native diagnostics checks and new upgrade preservation pass. Real opt-in/export UI, system input dispatch and actual 7/14-day observation remain open. |
| Deployment coverage | iOS 18 minimum and iPad support are compiled, but this candidate was exercised only on the existing iOS 26.5 iPhone Simulator. No alternate Simulator was selected. Supported-device/version matrix still needs approved execution. |
| Screenshots | Device Hub returned timeout `-10005` again. No candidate screenshot or UI pass was fabricated from a render or an earlier build. Capture real screenshots with synthetic data after access works. |
| Distribution/account | On 20 September 2026, created owner-selected **Daily Rhythm: Habit OS**, Apple ID **6814232930**, in LumeTech. Saved App Information confirmed bundle/SKU `com.lumetechllc.DailyRhythm` and English (U.S.). iOS storefront draft is **1.0 / Prepare for Submission**; TestFlight visibly shows **No Builds**. Recheck build-number availability at upload time. Distribution signing, export compliance, validation/processing and beta review remain unverified; no upload/distribution performed. |
| Public information | Support email confirmed: Contact@lumetechllc.com. [Support/privacy HTML previews](../release/web-preview/README.md) prepared and browser-checked; optional app diagnostics and automatic TestFlight collection are explicitly distinguished. These are unpublished drafts. Owner-selected support/privacy URLs, legal-policy confirmation, private review contact and actual report-retention/destination policy still needed. |
| CI | Previous workflow runs failed to start due to the account billing lock. The PR records its own fresh run; local results are not a green CI claim. |
| Pilot outcome | Protocol/templates ready; no testers recruited, no day-7/day-14 observations or findings yet. Link actual findings to the decision before closing #21. |

No unresolved data-loss/duplicate/wrong-occurrence defect was observed in the executed core and fixture scenarios; that is bounded test evidence, not proof that the open device scenarios are safe. The optional schema-Siri/PCC exclusions alone are not blockers for the manual beta. The core acceptance, packaging/account and public-information gaps above are why this candidate remains on hold.
