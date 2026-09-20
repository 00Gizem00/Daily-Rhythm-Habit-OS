# Review copy — Daily Rhythm 0.1.0 (2)

Not published. Use only after the candidate gates pass; update these notes if the binary changes.

## Beta description

Daily Rhythm helps you keep small routines on busy days. Create a routine or one-off task, record a full goal or a smaller step, and review your saved history. Manual tracking works offline without an account. The Free limit is three active recurring habits; one-off tasks and archived plans do not count.

## What to Test

- Create one small habit and record your first full or light step. Try Undo, Later, Skip and a future schedule edit; check that the correct step changes.
- Close and reopen the app, then check your plans and history. If you update from a previous beta, keep the app installed and save a JSON backup first.
- If you choose, try the Home Screen widget and ordinary App Shortcuts. Tell us which surface you used and whether its saved state matched the app.
- Test large text and VoiceOver if you normally use them. Report clipped controls, confusing labels or missing feedback.
- Optional notifications and local pilot diagnostics start off. Enable them only if you want to test them. You can export diagnostic JSON voluntarily; nothing uploads automatically.
- Use **Habits → Help & Beta** for the version and feedback guidance. Report a wrong-step change or missing data immediately, without deleting the app or erasing your data.

## Included changes

The candidate adds a recognizable app icon and a Help & Beta screen with version, feedback and backup instructions. It includes local routine management, full/light completion, history, JSON/CSV export, empty-store JSON restore and opt-in 30-day diagnostics. Local erase also clears the haptic preference.

## Scope and known limits

The default candidate has ordinary App Shortcuts; **experimental iOS 27 schema-driven Siri AI is disabled**. PCC/AI routine generation, cloud sync, purchases, routine-session Live Activities, a Watch app and a native Mac app are not included. No paid offer or price is being tested in the app.

Notification scheduling is local and refreshed over a bounded seven-day window; iOS controls actual delivery. Widget refresh and Siri behavior depend on the system. App Intent diagnostic counts combine Siri, Shortcuts and controls; they cannot identify the exact invocation method. Diagnostics can miss observations after interruption/storage failure and expire after 30 civil days on next access.

The preparation record has open device/UI gates; these notes do not claim they passed. Do not publish screenshots from prior builds, source previews or generated artwork as screenshots of this candidate. Current candidate screenshots are still required from a running build with synthetic data.

## App Review notes draft

No app account or login is needed. Start with a manual one-off or a template, then record a full or light step. Optional notification permission is requested only after enabling a reminder switch. Diagnostics are local and off by default; explicit diagnostic export is separate from the full routine backup. No purchase flow is present. Beta feedback email: **Contact@lumetechllc.com**. Private Review contact and privacy/support URLs remain open fields in the readiness checklist.
