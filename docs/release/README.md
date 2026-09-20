# Daily Rhythm 0.1.0 (2) — beta preparation

**HOLD: prepared locally, not approved for upload or distribution.** This directory is a review packet for issue #21, not evidence of an active pilot. No build has been uploaded and no testers have been contacted by this task.

- [Candidate evidence and release gates](../verification/ISSUE-21-RELEASE-CANDIDATE.md)
- [Release notes and App Store Connect copy](RELEASE-NOTES.md)
- [14-day pilot protocol](PILOT-PROTOCOL.md)
- [Tester guide](TESTER-GUIDE.md)
- [Feedback and decision templates](FEEDBACK-TEMPLATE.md)
- [Privacy/support draft and missing owner information](PRIVACY-SUPPORT-DRAFT.md)
- [Support and privacy HTML previews](web-preview/README.md) — local review assets; public URLs still pending.

## Upload and distribution runbook

1. Resolve the open candidate matrix, with actual build/device evidence. Optional schema Siri and PCC are excluded; they alone do not block the manual beta. Current data, upgrade, accessibility, notification and surface checks do.
2. Confirm the App Store Connect record belongs to LumeTech, bundle `com.lumetechllc.DailyRhythm`, and that build **2** is unused for version **0.1.0**. The local increment is not a reservation in App Store Connect. Keep app and extension versions aligned; change the generator if another increment is needed.
3. Confirm the public support/privacy destinations, beta feedback email and private App Review contact. Review the actual support/diagnostic handling before completing App Privacy answers. Do not claim that voluntarily received reports contain no data. Complete encryption questions based on the final binary; no encryption declaration was submitted here. Apple requires beta compliance information before testing. [Apple export compliance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds)
4. From a clean, recorded source commit, generate/check the project, run the release tests and create a Release archive with the ordinary scheme and no experimental Swift flags. Keep its dSYMs and record binary hashes. Run `python3 scripts/inspect_release_archive.py <archive>`; this verifies local packaging only.
5. In Xcode Organizer, review the archive and validate its App Store Connect distribution signing. The local candidate is development-signed; App Store distribution signing/export has not been verified. Do not alter signing-team or App Group identities to get past a provisioning failure.
6. **Only after the owner explicitly authorizes this exact candidate's upload**, choose Distribute App → App Store Connect and complete the applicable validation/upload flow. Preserve the original candidate archive. Record Apple's processing/validation outcome and resulting build identity. A local archive success does not establish acceptance. [Apple upload workflow](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds)
7. Enter the reviewed English beta description, feedback email, What to Test, and App Review information. External testing needs TestFlight test information; the description and feedback email are required fields. [Apple test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)
8. After processing and any required beta review, obtain explicit distribution/tester-contact authorization. Confirm the chosen group and candidate; keep automatic distribution disabled until approved. Do not create public links or invite participants as part of preparation.
9. Run a final TestFlight install/upgrade on an approved device, confirm bundle/build and data, then start the participant-specific day-1 clock. Record install failures independently of product engagement.

Build numbers, signing/export requirements and Apple processing must be rechecked at upload time. Owner account details, payment settings, legal agreements, prices and live App Store fields have not been changed. GitHub CI billing remains a separate infrastructure gate; local verification is documented explicitly.
