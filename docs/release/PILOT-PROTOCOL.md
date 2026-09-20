# 14-day pilot protocol — review draft

Status: not recruiting, not scheduled, no invitations sent. Start only after the release gate and owner authorization. Recruit 10–15 adults who previously abandoned a habit app. Record what they used and why they stopped before suggesting explanations. Use one candidate per cohort; record every update or interruption.

## Participation and data choice

Use a participant code; keep any code-to-contact mapping privately with the organizer, never in this repository. Participation, reminders and diagnostic sharing are separate opt-ins. Declining diagnostics must not prevent participation. Let people skip questions or withdraw. Do not ask for habit titles, goals, personal prompts, raw routine backups or precise location. Avoid sensitive sample routines.

Before sharing, explain that optional reports contain relative daily completion counts, source buckets, failure categories and available setup duration. The organizer can associate a report with its participant code, so do not call it anonymous. Record a proposed retention period of **30 days after the final pilot decision** for organizer-held reports/contact mapping, then delete them; the owner must confirm this policy and the private collection destination before recruitment. App-local retention and external report retention are separate.

## Schedule

| Time | Participant task | Organizer record |
| --- | --- | --- |
| Before day 1 | Confirm consent, supported device/iOS, candidate version and chosen feedback route. Existing users save a JSON backup and update without uninstalling. | Prior app and reason for leaving; opt-in choices; install/upgrade result. No contact details in the results sheet. |
| Day 1 | Without coaching, create a tiny manual/template routine and record a first completion. Optionally enable diagnostics before setup. | Time from setup opening to first completion, assistance needed, first friction point. Distinguish observed stopwatch time, self-report and diagnostic time. |
| Days 2–6 | Use the app naturally. Try a light step on a busy day; optionally use a widget or ordinary Shortcut. | One brief check-in on day 3 only if reminders were accepted. Log failures separately from engagement. |
| After day 7 ends (day 8) | Say whether the app was useful and why. Optionally export diagnostics JSON and review before sharing privately. | Day-7 event observed / not observed / missing evidence; days used in week 1; app/widget/App Intent totals and reported invocation context. |
| Days 8–14 | Continue naturally without pressure to build a streak. | Log updates/outages and participants who stop, with their reasons if offered. |
| After day 14 ends (day 15) | Optional final diagnostic export, short interview and willingness-to-pay questions. | Day-14 outcome, any meaningful use on days 8–14, completion days, reasons to keep/switch/stop, unmet needs. |
| After review | Communicate next steps only with approved contact scope. | Release decision and defects linked to the exact candidate; confirm report deletion date. |

Diagnostics use the timezone captured at opt-in, not the participant's later travel timezone. Day 1 starts when they opt in and ends at the next civil midnight. Align the pilot clock with that opt-in; otherwise label the offset and do not merge day numbers. Day-7/day-14 fields remain `awaiting` until that day ends. Collect after each checkpoint and before day 31 expiry. Do not change the user's clock to accelerate the pilot.

## Measurement rules

- The denominator is everyone who starts the pilot; show invited/installed/started/completed separately. Missing exports, opt-outs, failed installs and nonresponses are separate states, never fabricated zeroes.
- Setup success means a saved first completion without assistance. If there was no captured start, record timing as unknown. A returning user's baseline is not new activation.
- Week-2 use means at least one meaningful participant-reported use or observed first completion on relative days 8–14. Report the evidence type and the missing-data count. Exact day-14 use is a separate metric.
- Count first saved full/light transitions, not taps or current progress totals. Reopen/recomplete and Undo do not inflate already observed occurrence counts. These best-effort diagnostics may miss writes; use qualitative reports to investigate gaps.
- Report **app / widget / App Intent / unknown** separately. Ask whether an App Intent attempt used Siri, Shortcuts or a control, but do not relabel aggregate App Intent totals as Siri counts. Legacy baseline unknown is not an app completion.
- Failed-action counts are attempts; repeated failed requests may increase them. Use a short reproduction report to distinguish stale display, wrong resolution and unavailable action. Never infer a defect merely from a category count.
- Ask willingness to pay before naming a price: “Would you keep using this?”, “Would you replace your current method?”, “Would you pay for it? Why?”, “If yes, what payment model and range feel reasonable?” Record verbatim non-sensitive answers; no live pricing or purchase commitment.
- AI/PCC measures are **not applicable** for this candidate. Do not include pretend generation or schema-Siri results.

## Stop and decision rules

Stop the affected test and pause distribution for a reproducible data-loss, duplicate-result, wrong-occurrence or privacy defect. Preserve the installed app and source data; do not suggest erasure/reinstallation as a repair. Reproduce with synthetic data, fix, add regression evidence and retest the upgrade path before resuming.

Suggested internal continuation rules from the product plan: no unresolved data-corruption/duplicate/wrong-occurrence defects; a majority complete setup without help; at least half of starters show meaningful week-2 use; several can explain why they prefer this workflow. Show actual counts and uncertainty. These are small-cohort decisions, not market validation or industry benchmarks. Do not close #21 with a local build or a protocol alone; link actual pilot findings into the decision template.
