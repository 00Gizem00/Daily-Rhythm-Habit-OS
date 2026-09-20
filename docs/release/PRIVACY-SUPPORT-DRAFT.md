# Privacy and support — review draft, not published

Owner-confirmed public support and beta feedback email: **Contact@lumetechllc.com**. Still required: support URL, privacy-policy URL, confirmation of legal operator and private App Review contact. The signing team is LumeTech L.L.C.; that alone does not confirm the legal policy/contact details. Do not invent these fields or publish placeholders. No remote page or App Store Connect field was created by this task.

## Product privacy text for owner review

Daily Rhythm stores routines, goals, history and preferences locally. The app, its widgets and App Shortcuts use shared local storage. Manual tracking does not need an account, an AI service or a network connection. This beta includes no advertising SDK, remote analytics service or cloud sync.

Local notifications are optional. The app asks for notification permission after you enable a reminder option; tracking still works if you decline. iOS controls delivery and permission settings.

Optional local pilot diagnostics start off. When enabled, they record first saved completion counts, relative observation days, known input surfaces, available setup duration and categorized action failures. Habit names, targets, prompts and raw error messages are not recorded in diagnostics. The local file uses occurrence keys to avoid counting a result twice; exports omit those keys, exact timestamps and timezone identifiers. No diagnostic report is uploaded automatically. Observation lasts 30 civil days and is removed on the next app/diagnostic access after expiry; turning it off deletes local observation.

You can explicitly export routine JSON/CSV or diagnostic JSON and choose a destination through iOS sharing. A routine backup contains your personal routine text and history. A diagnostic report contains aggregate usage information. Review the file and destination before sharing. Once sent, that destination's handling applies. User-saved copies outside the app are not removed by app erasure.

Erase Local Data removes local routines, history, preferences, owned notifications, setup state, diagnostics and other app-owned cleanup files. It is permanent; a previously saved JSON backup can restore data into an empty app. Small non-personal coordination/recovery files remain to reject outdated actions and recover interrupted erasure. iOS permissions and backups are managed separately through device settings.

If you install through TestFlight or send beta feedback, Apple and the developer may receive TestFlight feedback/diagnostic information under the applicable TestFlight settings and terms. Reports that you voluntarily send to the organizer can be associated with your feedback contact or participant code. Such handling must be explained in the organizer's confirmed policy; it is separate from the app's absence of automatic upload.

## Support page draft

Contact **Contact@lumetechllc.com** for support and beta feedback. Include: product/version scope, backup/restore steps from the tester guide, optional diagnostic export instructions, and how to ask for deletion of organizer-held reports. Do not request full routine backups by default. For missing data, keep the app and source files intact, note version/build, and seek support before erasing or reinstalling.

The organizer proposes private report collection and deletion 30 days after the final pilot decision; confirm actual destinations, access and retention before adopting this text. Do not promise deletion of copies held by unrelated sharing destinations or Apple.

## App Store Connect review items

- Confirm who operates the app and which public contact/URLs should appear. Verify they load without login and are accurate for this build.
- Review voluntary diagnostic exports, emailed reports and TestFlight feedback before selecting privacy answers. The bundled manifest describes app APIs and current tracking/collection declarations; it does not replace the App Store privacy questionnaire or the support-report policy.
- Source inspection found no custom crypto, network client, cloud account or third-party runtime dependency. Complete the final encryption classification in Apple's workflow; no legal compliance answer was submitted automatically.
- Public feedback email and private App Review contact serve different purposes. Do not copy personal signing-account details into either field without the owner's selection.

References: [Apple app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), [TestFlight feedback email](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/), [beta export compliance](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds).
