# Daily Rhythm — Product Research and MVP Proposal

Research date: 20 September 2026  
Plan revision: 0.2 — optional PCC planning added; Dynamic Island clarified.  
Language: English  
Status: Product proposal; official documentation and competitor listings reviewed, no device testing completed.  
Repository: [00Gizem00/Daily-Rhythm-Habit-OS](https://github.com/00Gizem00/Daily-Rhythm-Habit-OS), confirmed empty during this review.

## 1. Founder decision

Build a small validation release, not a broad personal operating system.

**Product promise: “Your next small step, wherever you are.”**

Daily Rhythm should help people keep a few meaningful habits through changing days, with minimal planning and logging. Voice is an input method; the value must remain when the user cannot or does not want to speak.

Initial audience hypothesis: English-speaking iPhone users who repeatedly restart habits because their schedules change. Begin with freelancers and people working from home; test shift workers as a separate cohort because their day boundaries differ. These segments and their willingness to pay are unvalidated.

Keep “Daily Rhythm” as a working product name and “Habit OS” as the repository description. App Store name and trademark availability have not been checked.

## 2. What the research changes

The proposed gap is narrower than it first appears. Existing products already support hands-free logging and rich system surfaces.

| Competitor | Verified published capabilities | Implication |
| --- | --- | --- |
| Streaks | US App Store price of $5.99 upfront; version 11.4 advertises Siri AI creation and completion. Existing features include widget completion, Apple Watch, Siri Shortcuts and Health-linked automatic completion. | Opening the app daily is not required for all logging. Voice alone is not a differentiator. |
| Habitify | Its 16 September announcement describes Siri AI habit logging and progress queries. Earlier updates include heatmaps, daily scores and weekly rhythm analysis. | Voice plus attractive progress charts is already competitive territory. |
| Structured | Visual timeline, interactive widgets, Live Activities; Pro recurring routines and replanning. Recent releases advertise Siri AI task creation and updating. | Timeline design and rescheduling are not unexplored gaps. |

Sources: [Streaks US listing](https://apps.apple.com/us/app/streaks/id963034692), [Habitify changelog](https://feedback.habitify.me/changelog), [Structured US listing](https://apps.apple.com/us/app/structured-daily-planner-todo/id1499198946). These are developer claims, not comparative performance measurements.

Even forgiving streaks are established: Streaks has described a two-day rule. The opportunity is to validate a better overall experience for a specific audience, not to claim that competitors lack every individual feature. [Streaks 10 release notes](https://crunchybagel.com/now-available-streaks-10/)

## 3. Exact Siri and App Schema boundary

The current official Reminders domain supports the core capture/completion loop, with one correction: completion is an update.

| User outcome | Official schema / field | Product interpretation |
| --- | --- | --- |
| Create an item | `.reminders.createReminder` | Create an app-owned reminder. |
| Repeat an item | `createReminder` with `recurrence: Calendar.RecurrenceRule?` | Translate the supported recurrence into the app's schedule. |
| Set a time | `dueDate: DateComponents?` | Preserve date-only versus timed semantics. |
| Complete or reopen | `.reminders.updateReminder`, `isCompleted: Bool?` | Update the intended occurrence and retain history. |
| Change schedule | `updateReminder` with due date / recurrence | Distinguish changes to this occurrence from future scheduling. |
| Group reminders | `.reminders.createList` / `.reminders.createSection` | Use truthful collections such as Morning or Evening. |

There is no documented `.reminders.completeReminder`. Current documentation uses `AppSchema` and `@AppIntent(schema:)`; implementation should use the current SDK rather than copy older `AssistantSchemas` examples. The new reminder schema declarations document platform availability from version 27; watchOS is not listed on these declarations. [Reminders domain](https://developer.apple.com/documentation/appintents/app-schema-domain-reminders), [createReminder](https://developer.apple.com/documentation/appintents/appschema/remindersintent/createreminder), [updateReminder](https://developer.apple.com/documentation/appintents/appschema/remindersintent/updatereminder)

The reminder entity does not provide habit streaks, pages-read counters or routine-session progress. “Read 10 pages” can be a reminder; numeric logging such as “add another three pages” needs separate app functionality. [Reminder entity](https://developer.apple.com/documentation/appintents/appschema/remindersentity/reminder)

Under the strict schema approach:

- Siri AI supports documented reminder operations.
- “Start a routine,” “use my light-day plan,” “skip today,” and timer controls remain explicit app/widget controls in the MVP.
- Ordinary App Intents may power those buttons and optional Shortcuts; they must not be advertised as automatically understood Siri AI schemas.
- Do not disguise unrelated commands as reminder completion. Additional custom properties are not automatically understood by Siri AI. [Schema adoption rules](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence)

Adopting schemas exposes Daily Rhythm's own data and actions. It does not automatically share a database with Apple Reminders. EventKit import or synchronisation would be a separate project. Test onboarding phrases with an explicit app name; generic “remind me” routing is not guaranteed. [Siri AI integration](https://developer.apple.com/documentation/appintents/apple-intelligence-and-siri-ai)

## 4. Availability and truthful promises

Apple's 14 September guidance says Siri AI is beta, English-only, with opt-in and a waitlist. It requires eligible hardware, matching device/Siri language and a supported account region. On iPhone it requires iOS 27 and iPhone 15 Pro/Pro Max, iPhone 16 or later, or iPhone Air. Siri AI is currently unavailable on iOS, iPadOS and watchOS in the EU. Supported Watch use requires a compatible paired iPhone nearby. [Siri AI requirements](https://support.apple.com/en-us/127893)

Therefore propose iOS 18+ for the ordinary habit app and supported widgets, with the new schema integration gated to supported iOS 27 environments. Verify deployment and SDK availability in Xcode. Siri Shortcuts can be a separate fallback; do not imply that old Siri has the same natural-language capabilities.

Use **“Siri support included”**, not “unlimited Siri.” Apple applies daily limits to some server-based AI features, including Siri AI; an app cannot override them. [Apple Intelligence usage limits](https://support.apple.com/en-us/121115)

Background intents and an appropriate authentication policy can support actions while locked. They do not guarantee every request will succeed: test data protection, Siri settings, permissions and ambiguous names. A locked device must not cause silent data loss. [Execution modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes), [Authentication policy](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)

## 5. The proposed product loop

1. **Set up three habits.** Choose a morning/evening template, enter titles and schedules, or use **Build My Routine** when available to draft a plan from goals and available time. Review and apply the proposal before any habits are created. No account required.
2. **See one next action.** The widget presents a clearly named item, its target and a completion button.
3. **Complete where convenient.** Use the widget, the app or a supported Siri reminder action. Save once and update every surface.
4. **Recover without rebuilding the plan.** An explicit Light Day choice shows the user's smaller targets. Never secretly lower a goal.
5. **See an honest close.** A compact card distinguishes full completions, smaller versions, skips and remaining items.

Illustrative Siri test phrases, not promised exact recognition:

- “Add reading every morning at eight in Daily Rhythm.”
- “Mark today's reading reminder complete in Daily Rhythm.”
- “Move today's reading reminder to nine tonight in Daily Rhythm.”

Measure whether specifying the app and today's occurrence resolves reliably. Avoid the promise that “I did it” will always find the right task.

## 6. Features worth building

| Feature | User value | Scope |
| --- | --- | --- |
| **Next Up** | One meaningful action instead of a wall of unfinished items. Explicit Done and Later actions. | MVP |
| **Light Day** | User-defined small alternative, such as 2 pages instead of 10. Full and light outcomes stay distinct. | MVP |
| **Day Rhythm** | Morning / Afternoon / Evening view with quiet progress marks and a simple accessible list alternative. | MVP |
| **Reliable completion + Undo** | Repeated requests do not count twice; a mistaken completion can be reversed. | MVP |
| **Weekly consistency** | A clear history of planned and completed occurrences, with small versions marked separately. | MVP, basic |
| **Daily Close** | An optional evening card showing what happened and tomorrow's first step. | MVP card; notification after reliability checks |
| **Build My Routine** | Turn goals and available time into a structured, editable routine proposal using PCC. | First optional AI feature in the MVP, after the core reliability gate and PCC device validation |
| **Make Today Lighter** | Suggest smaller steps for a busy day; the user approves the changes. Existing manual Light Day remains available. | Later AI release |
| **Weekly Reflection** | Explain locally calculated activity patterns and propose a small adjustment. | Later AI release; requires sufficient recorded history |
| **Routine Sessions** | Start a short sequence, see the current step, finish with a compact recap. | Next release |
| **Time Available** | “I have five minutes” filter inside the app selects a preconfigured short action. | Next release; no new Siri schema claim |
| **Flexible day start** | Explicit “Start my day” and configurable day boundary for irregular schedules. | Separate cohort experiment |
| **Personal patterns** | Explain observations from enough history, such as stronger completion in the evening. Ask before changing schedules. | Later |

Use a deterministic rules engine for the core loop. PCC adds optional planning and reflection as described below. A chat interface is not required: a short goal-and-time form can produce a structured plan preview. Manual choices, templates and local progress calculations remain available without AI.

Haptics and small animations belong in the foreground app, with Reduce Motion support. Do not promise identical custom feedback during a background Siri action or across widgets and Watch. Avoid false precision such as a scientifically validated “dopamine score.”

## 7. Dynamic Island, widgets and other surfaces

These are proposed designs on documented system surfaces. Availability and interaction behaviour still need device testing.

The founder clarified that the earlier “Dock” request meant **Dynamic Island**. Prioritise an active routine experience there after the core tracking loop. Native Mac Dock and menu bar support remain optional future exploration, not part of the requested iPhone experience.

| Surface | Proposed design | Delivery priority / boundary |
| --- | --- | --- |
| iPhone Home Screen, small | **Next Up:** one named action and completion button. | MVP |
| iPhone Home Screen, medium | **Today:** three habits, progress and next action. | MVP |
| Lock Screen | Compact daily progress or one selected habit. | MVP; respect privacy and authentication |
| StandBy on a charging stand | Large day progress beside a next-action card. | MVP adaptation; phone charging, sideways and stationary |
| Control Center / Lock Screen control | Complete a clearly configured habit, or open today's view. | MVP if the action is unambiguous |
| Action button | User-selected Daily Rhythm control or Shortcut. | Optional setup; supported hardware |
| Dynamic Island / Live Activity | Current step and remaining time for an explicitly started short routine. | Next release; not an all-day permanent scoreboard |
| Apple Watch | Smart Stack next-step widget, glanceable complication, lightweight completion screen. | After iPhone validation; separate Watch integration |
| Mac desktop / Notification Center | Reuse eligible iPhone widgets through Continuity first. | Useful bridge; test interactions and connection requirements |
| Mac menu bar | Compact progress indicator opening a small Next Up panel. | Native Mac companion later |
| Mac Dock | App icon progress/badge and a contextual menu. | Native Mac companion later; not a WidgetKit Dock widget |
| iPhone bottom Dock | App icon, optionally a badge. | No arbitrary custom widget panel in the iPhone Dock |

Interactive widgets use App Intents and system-rendered timelines. They are not continuously running miniature apps; do not depend on per-second custom code or animation. [Apple: Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)

Controls can appear in Control Center, Lock Screen controls and the Action button. Prefer a named configured habit to a generic “complete next” button that might act on a different item after the screen changes. [Apple: Extend your app's controls](https://developer.apple.com/videos/play/wwdc2024/10157/)

StandBy requires a charging iPhone resting on its side. Always-on behaviour depends on the model and settings. [StandBy guide](https://support.apple.com/guide/iphone/use-standby-iph878d77632/ios)

Mac can display iPhone widgets with the same Apple Account and required proximity/network conditions; that does not itself deliver a native Mac menu bar or Dock experience. [Mac widget guide](https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac)

Live Activities should represent bounded sessions. Apple's current documentation describes up to eight active hours and up to four further hours on the Lock Screen. Users may dismiss or disable them. [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

Native macOS Dock customisation uses AppKit's Dock tile; a menu bar panel is a separate native surface. [NSDockTile](https://developer.apple.com/documentation/appkit/nsdocktile), [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)

## 8. Optional intelligence with Private Cloud Compute

**Approved direction:** add PCC for personal routine proposals, beginning with **Build My Routine**. Keep Siri capture/completion, local tracking and AI planning as distinct responsibilities. PCC does not expand the official Siri App Schema catalogue.

| Feature | Example input or context | Output and application |
| --- | --- | --- |
| **Build My Routine** | “I have 15 minutes in the morning. I want to read and practise English.” | A small ordered routine with suggested durations, schedule and optional light alternatives. Show an editable preview; create habits only after the user applies it. |
| **Make Today Lighter** | “Today is busy; I only have five minutes,” plus the selected existing routine. | A proposed lighter version for today. Preserve the original template unless the user explicitly chooses to change future days. |
| **Weekly Reflection** | Locally calculated completion totals, normal/light outcomes and the user's selected goals. | A short explanation of observed patterns and one practical suggestion. Do not invent statistics or claim a causal explanation for missed habits. |

Apple documents direct PCC access through the Foundation Models framework. Integration depends on entitlement, compatible software/hardware, supported availability and an internet connection. Check current model availability and handle per-person usage quotas; do not hard-code an undocumented daily allowance or promise unlimited access. [Apple PCC implementation guide](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), [PCC developer eligibility](https://developer.apple.com/private-cloud-compute/)

Implementation requirements:

- **Proposal first:** generate a structured draft with stable references to existing habits, explicit durations, targets and schedule changes. Validate it against the user's time budget, supported recurrence rules and entitlement limits before showing it.
- **Explicit application:** preview → edit → apply. Reuse the normal mutation service to save; generation must not directly mark tasks complete or silently overwrite a routine. Prevent duplicate application and support undo.
- **Availability fallback:** on unsupported devices, offline, at quota or after a failed request, preserve user input and offer manual editing or existing templates. An on-device model may be an additional fallback where available and validated; it is not required for core use.
- **Local execution:** recurrence, completion, progress calculations, notifications and widget actions use local state. Once applied, the routine runs without further PCC calls. Live Activities display the saved session; they do not depend on continuous generation.
- **Data minimisation:** send only the goal, constraints and selected app data needed for the request. Explain that this optional feature uses Apple's private cloud processing. Do not describe PCC generation as entirely on-device. Broader access to Mail, Calendar or Health is not implied by PCC or Siri integration.
- **Grounded reflection:** compute totals and rates locally, distinguish full and light outcomes, and let the model explain those facts. Keep inadequate-history states explicit.

Before enabling PCC in TestFlight, verify the app's entitlement and provisioning, perform a successful real-device request, and exercise unavailable/quota/error states. Account-level access alone does not prove this app is configured correctly. The first AI acceptance case is a routine proposal that fits the stated time budget, remains editable, and produces valid app records only after Apply.

**Release order:** core habit and widget reliability → PCC access validation → optional Build My Routine → routine sessions with Dynamic Island → Make Today Lighter and Weekly Reflection. Generation is user initiated in the first release; scheduled background generation is outside scope.

## 9. Implementation proposal

Use SwiftUI, a local persistent store shared through an App Group, App Intents, WidgetKit, UserNotifications and StoreKit 2. Select and validate the persistence implementation during the technical spike; concurrent app/extension writes matter more than the choice of wrapper.

Add a Foundation Models planning service behind availability checks for the optional PCC features. Keep its proposal generation separate from the local mutation service. A plan preview records proposed changes without altering live habit data; only the user's Apply action commits a validated proposal.

Suggested conceptual model:

- **HabitTemplate:** title, schedule, normal/light target and daypart.
- **Occurrence:** stable identity, scheduled local day, due time and target snapshot.
- **CompletionEvent:** occurrence identity, outcome, timestamp and input surface.
- **RoutineSession:** optional active sequence, introduced later.

All entry points call the same mutation service. Completion must be idempotent: two taps or a repeated Siri request for one occurrence produce one result. Completing today's recurring occurrence must not silently complete tomorrow's. Keep undo, timezone travel, daylight-saving transitions and multiple same-name habits explicit.

Generate future occurrences from the schedule when needed; do not depend on the app waking at midnight. Widgets receive timeline entries for known changes and reload after writes. A notification scheduled in advance contains a snapshot: recompute/cancel it on changes, and avoid an exact evening total if it might be stale. Background execution at an exact clock time is not assumed.

No login, advertising SDK, required cloud inference, social feed, calendar import or two-way Apple Reminders sync in the first release. Cloud sync is a separate reliability milestone before promising a full Watch/Mac experience. Provide local data export and deletion.

## 10. Monetisation and acquisition hypotheses

| Free | Pro experiment |
| --- | --- |
| Three active habits; basic reminder capture; core widgets; Siri support; basic history; undo/export. | More active habits, richer historical views, additional widget presentation options and, later, routine sessions. |

Define the limit as **three active habits**, not three bundles containing unlimited habits. Existing data and history remain readable after entitlement expiry; completion and export should never become a recovery problem.

The proposed **$19.99/year** is a price experiment, not a verified market optimum. Streaks' low upfront price makes “reasonable annual price” an insufficient argument on its own. Test a clearly described one-time upgrade alternative before deciding on lifetime pricing; avoid launching a complex set of subscriptions and lifetime offers together.

Keep the core widget useful in Free because it is how the product demonstrates value. Do not make basic Siri reliability a paid feature.

PCC feature packaging remains an experiment: first test whether Build My Routine improves activation. Do not promise unlimited AI or rely on assumed permanent cloud pricing. Manual setup and the core routine loop stay available regardless of PCC availability; any paid AI offer must clearly describe device requirements and service limitations.

Proposed English acquisition messages to compare:

- “Your next small step, wherever you are.”
- “Build a rhythm that survives busy days.”
- “Less logging. More living.”

Demonstrate a real 15-second loop: Siri completion, widget update, next small step. Test keywords such as habit tracker, daily routine and routine widget. Ranking, search volume and conversion are unverified; keywords do not guarantee visibility. Avoid “first Siri AI habit app.”

## 11. Delivery and decision gates

**Gate 1 — Technical spike, roughly 1–2 focused development days.** Build one real recurring habit and verify create/update/complete, entity resolution, persistence and a widget. Record hardware, OS, Siri availability, language and region. Test foreground, background, locked phone, ambiguous names, repeat requests and undo. Compile schema-gated code against the actual SDK. If Siri AI access is unavailable, mark that test blocked rather than successful.

**Gate 2 — Small TestFlight prototype.** Deliver onboarding, three habits, Next Up, normal/light outcomes, history and two widget sizes. Add optional Build My Routine once app-level PCC access and the proposal/application flow pass validation. A rough solo-development estimate for the original core is a further 2–3 weeks after the spike; estimate the PCC addition separately after the access spike. Keep Watch, native Mac, routine sessions and complex sync out of that core estimate. PCC unavailability must not block the manual/template-based beta.

**PCC acceptance checks:** test valid structured output, time-budget violations, invalid recurrence, unsupported availability, offline mode, quota errors, cancellation and repeated Apply. Confirm no task is created before approval; a saved plan remains usable offline. For later Weekly Reflection, check that every stated metric matches the local calculation.

**Gate 3 — 14-day observation with 10–15 testers.** Recruit people who have abandoned at least one habit app. Ask what they previously used and why they stopped; do not assume an interface problem.

Measure:

- Setup-to-first-completion time.
- Completion days per tester and usage on days 7 and 14.
- Share of completions through Siri, widget and app.
- Failed or incorrectly resolved actions, duplicates and stale displays.
- Whether Light Day creates useful returns or merely lowers goals.
- Build My Routine availability, generation success, proposal edits and apply rate; compare time to first completion with manual/template setup. Collect feature events without retaining raw personal prompts by default.
- Whether testers would replace their current product and pay the proposed price.

Suggested internal continuation thresholds: no known data-corruption or duplicate-completion defects; a majority complete onboarding without help; at least half still record meaningful activity in week two; and several can articulate why they prefer this workflow. These are small-pilot decision rules, not industry benchmarks or proof of product-market fit.

The first development milestone is **one recurring habit completed correctly through Siri and a widget, with trustworthy history**. A reliable loop earns the right to add more surfaces.
