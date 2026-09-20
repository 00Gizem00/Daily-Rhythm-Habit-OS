# Support and privacy page previews

Review assets for #21, prepared 20 September 2026 against beta **0.1.0 (2)**. These are not published pages or App Store Connect URLs. They intentionally retain visible draft notices and `noindex, nofollow`. That metadata is not an access-control mechanism.

- [Support](index.html): confirmed support email, backup/restore instructions, missing-data guidance, optional diagnostic export and beta scope.
- [Privacy review draft](privacy.html): local storage, notifications, diagnostics, sharing, erase boundaries, TestFlight and unanswered operator/report-handling details.

The pages use static HTML/CSS, a local SVG mark and system fonts. They contain no JavaScript, forms, analytics, cookies, external fonts or remote assets. The email link opens a composer and does not send automatically. No personal records or screenshots are included. Hosting-provider request logging has not been assessed because no host has been selected; do not extend these source-level properties into a claim that a future website collects no data.

## Preview locally

From the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs/release/web-preview
```

Open `http://127.0.0.1:8765/`. Only this review-assets directory is served, on loopback. The files can also be opened directly; relative links and styles are self-contained.

## Required before public hosting

1. Confirm the legal operator. The signing-team name alone is insufficient.
2. Confirm the selected website/destination and the actual handling of received support/pilot reports: storage/services, access, purpose and deletion period. Do not adopt the proposed 30-day external retention policy by assumption.
3. Finish the privacy policy for those practices, including the chosen host's handling where relevant. Set a real effective date only when it becomes effective. Remove review-only notices only after the content is settled.
4. Publish to the owner-selected destination, with HTTPS, and verify both URLs without login, including mobile navigation and the support email. Do not point App Store Connect or the native app to localhost, a draft page or an invented domain path.
5. Reconcile the App Privacy questionnaire with actual processing. The local app manifest and optional diagnostics do not describe all TestFlight or voluntarily received support data.

The previous Markdown draft remains the accompanying review context. This preparation does not upload a build, register a site, change DNS, invite testers, submit a legal agreement or alter the app binary. The signed 0.1.0 (2) candidate and all remaining #21 gates are unchanged.

## Content references

Product instructions were checked against `BetaHelpView.swift` and `DataPrivacyView.swift`, the release tester guide and diagnostics evidence. The optional local report does not automatically upload; TestFlight's separate crash/usage collection is automatic. The support, privacy, tester and pilot copy now explicitly distinguish the two.

- [Apple: support URL and private review information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Apple: manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Apple: TestFlight & Privacy](https://www.apple.com/legal/privacy/data/en/test-flight/)

No claim of legal sufficiency or completed App Store review is made by this factual review draft.

## Executed checks

- Both pages and both assets served successfully from the loopback preview. All 26 relative asset/navigation/fragment references resolve; each page has a unique main heading, English language metadata and the draft indexing marker.
- Actual browser navigation between support/privacy and the TestFlight section anchor passed. The support mail link targets the owner-confirmed address; no email was sent.
- At 320-pixel and 1280-pixel viewport widths, both pages' document scroll width matched their available width (305 and 1265 pixels after the scrollbar). The support page was visually inspected at both sizes, and the privacy page at the narrow size. The temporary viewport override was reset.
- Keyboard Tab revealed the skip link and visible focus; Enter moved focus to the main content. This is bounded browser keyboard evidence, not a full screen-reader audit or native iOS accessibility pass.
- Browser warning/error log was empty during these checks. `git diff --check` and `python3 scripts/generate_project.py --check` passed. No Swift files or Xcode source membership changed; no native rebuild or Simulator run was needed for these review assets.
