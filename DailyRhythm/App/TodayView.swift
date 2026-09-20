import DailyRhythmCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var setup: OnboardingPreferences
    @State private var showingSetup = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var creationRoute: HabitCreationRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let today = model.today {
                    let items = model.agenda?.occurrences ?? today.occurrences
                    if model.activeHabits.isEmpty && items.isEmpty {
                        welcome
                    } else {
                        lightDay(today)
                        if today.totalCount > 0 { progress(today) }
                        if let next = model.nextOccurrence {
                            NextUpCard(occurrence: next)
                        } else {
                            RhythmCard {
                                Label(items.contains(where: { !$0.isResolved }) ? "Planned for later." : "No steps waiting.",
                                      systemImage: "sun.horizon")
                                    .font(.title3.weight(.semibold))
                                Text("\(today.fullCount) full · \(today.lightCount) light · \(today.skippedCount) skipped today.")
                                    .font(.subheadline).foregroundStyle(RhythmTheme.muted)
                            }
                        }
                        ForEach(DayPart.allCases, id: \.self) { part in
                            let planned = items.filter { $0.dayKey == today.dayKey && $0.dayPart == part }
                            if !planned.isEmpty { dayPart(part, items: planned) }
                        }
                        let carryovers = items.filter { $0.dayKey != today.dayKey }
                        if !carryovers.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("From earlier days").font(.headline)
                                Text("These steps keep their original day in history and its progress count.")
                                    .font(.caption).foregroundStyle(RhythmTheme.muted)
                                ForEach(carryovers) { OccurrenceRow(occurrence: $0) }
                            }
                        }
                        Text("Full, light and skipped steps are recorded separately. Skipping never counts as completing.")
                            .font(.footnote).foregroundStyle(RhythmTheme.muted)
                    }
                    if model.lastUndo != nil {
                        HStack {
                            Label("Change saved", systemImage: "checkmark.circle")
                            Spacer()
                            Button("Undo") { model.undoLastAction() }.frame(minHeight: 44)
                        }
                        .font(.subheadline)
                    }
                } else if model.loadError == nil {
                    ProgressView("Loading your rhythm…")
                        .frame(maxWidth: .infinity)
                        .padding(40)
                }
            }
            .padding(20)
            .padding(.bottom, 16)
        }
        .background(RhythmTheme.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingSetup) { OnboardingView() }
        .sheet(item: $creationRoute) { route in
            AddHabitView(readingTemplate: route == .reading)
        }
        .refreshable { await MainActor.run { model.refresh() } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.today?.completedCount)
        .sensoryFeedback(.success, trigger: model.completionFeedback)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(RhythmDates.todayLabel(model.refreshedAt))
                    .font(.subheadline)
                    .foregroundStyle(RhythmTheme.muted)
                Text("Find your rhythm.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(RhythmTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { creationRoute = .custom } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(RhythmTheme.ink)
                    .frame(width: 48, height: 48)
                    .background(RhythmTheme.card, in: Circle())
            }
            .accessibilityLabel("Add a habit")
            .disabled(model.today == nil)
        }
    }

    private var welcome: some View {
        RhythmCard {
            RhythmEmptyState(
                symbol: "sun.horizon",
                title: "Small steps. Your pace.",
                message: "Start with one thing that matters. Give it a full goal, and an optional smaller version for busy days."
            )
            if model.habits.isEmpty && setup.loadError == nil {
                Button(setup.progress.draft == nil ? "Choose a starting routine" : "Resume my setup") {
                    setup.begin()
                    showingSetup = true
                }
                .buttonStyle(RhythmPrimaryButtonStyle())
            }
            if let error = setup.loadError { Text(error).font(.footnote).foregroundStyle(.secondary) }
            Button("Create my first habit") { creationRoute = .custom }
                .buttonStyle(RhythmPrimaryButtonStyle())
            NavigationLink("Widgets & Siri help") { SetupHelpView() }
                .buttonStyle(RhythmSecondaryButtonStyle())
                .padding(.top, 8)
        }
    }

    private func lightDay(_ summary: DailySummary) -> some View {
        RhythmCard {
            Toggle("Light Day", isOn: Binding(get: { summary.isLightDay }, set: { model.setLightDay($0) }))
                .font(.headline)
            Text(summary.isLightDay
                 ? "For today, your saved smaller targets come first. Turn off to return to your full targets."
                 : "Choose a lighter pace for today using the smaller targets you have saved.")
                .font(.caption).foregroundStyle(RhythmTheme.muted).padding(.top, 6)
        }
    }

    private func progress(_ summary: DailySummary) -> some View {
        RhythmCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    RhythmProgressRing(full: summary.fullCount, light: summary.lightCount, planned: summary.totalCount)
                    progressText(summary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    RhythmProgressRing(full: summary.fullCount, light: summary.lightCount, planned: summary.totalCount)
                    progressText(summary)
                }
            }
        }
    }

    private func progressText(_ summary: DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY'S RHYTHM")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(RhythmTheme.muted)
            Text(summary.completedCount == 0 ? "A little is a beginning." : "You're showing up.")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 5) {
                Label("\(summary.fullCount) full", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(RhythmTheme.leaf)
                Label("\(summary.lightCount) light", systemImage: "leaf.fill")
                    .foregroundStyle(RhythmTheme.coral)
                Label("\(summary.skippedCount) skipped", systemImage: "forward.end")
                    .foregroundStyle(RhythmTheme.muted)
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private func dayPart(_ part: DayPart, items: [DailyOccurrence]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(part.displayName, systemImage: part.symbol)
                    .font(.headline)
                Spacer()
                Text("\(items.filter(\.isCompleted).count)/\(items.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(RhythmTheme.muted)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.horizontal, 18) }
                    OccurrenceRow(occurrence: item)
                }
            }
            .background(RhythmTheme.card, in: RoundedRectangle(cornerRadius: 22))
        }
    }
}

private struct NextUpCard: View {
    @EnvironmentObject private var model: AppModel
    let occurrence: DailyOccurrence
    @State private var editingOccurrence: DailyOccurrence?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("NEXT UP").font(.caption.weight(.bold)).tracking(1.5)
                Spacer()
                Label(occurrence.dayPart.displayName, systemImage: occurrence.dayPart.symbol)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(RhythmTheme.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text(occurrence.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(model.today?.isLightDay == true ? (occurrence.lightTarget ?? occurrence.normalTarget) : occurrence.normalTarget)
                    .font(.title3)
                    .foregroundStyle(RhythmTheme.muted)
                Text(RhythmDates.dueLabel(occurrence.due))
                    .font(.caption).foregroundStyle(RhythmTheme.muted)
                if occurrence.isOverdue(at: model.refreshedAt) {
                    Text("Overdue · not recorded").font(.caption).foregroundStyle(RhythmTheme.coral)
                }
            }
            if model.today?.isLightDay == true, let light = occurrence.lightTarget {
                Button { model.complete(occurrence, outcome: .light) } label: {
                    Label("Light step: \(light)", systemImage: "leaf")
                }
                .buttonStyle(RhythmPrimaryButtonStyle())
                Button("Full step: \(occurrence.normalTarget)") { model.complete(occurrence, outcome: .full) }
                    .buttonStyle(RhythmSecondaryButtonStyle())
            } else {
                Button { model.complete(occurrence, outcome: .full) } label: {
                    Label("Full step done", systemImage: "checkmark")
                }
                .buttonStyle(RhythmPrimaryButtonStyle())
                .accessibilityLabel("Complete \(occurrence.title), full goal: \(occurrence.normalTarget)")
                if let light = occurrence.lightTarget {
                    Button("Light step: \(light)") { model.complete(occurrence, outcome: .light) }
                        .buttonStyle(RhythmSecondaryButtonStyle())
                } else if model.today?.isLightDay == true {
                    Text("No smaller target saved for this step.").font(.subheadline)
                    if occurrence.dayKey == model.today?.dayKey {
                        Button("Add a smaller target for this step") { editingOccurrence = occurrence }
                            .frame(minHeight: 44)
                    } else {
                        Text("Past targets stay in history. Edit the future plan to add a smaller target for upcoming days.")
                            .font(.caption).foregroundStyle(RhythmTheme.muted)
                    }
                }
            }
            HStack {
                Button("Later · 1 hour", systemImage: "clock") { model.later(occurrence) }
                Spacer()
                Button("Skip Today", systemImage: "forward.end") { model.skip(occurrence) }
            }
            .font(.subheadline).frame(minHeight: 44)
            NavigationLink("Edit or manage this plan") { HabitDetailView(habitID: occurrence.habitID) }
                .font(.subheadline)
        }
        .sheet(item: $editingOccurrence) { OccurrenceEditor(occurrence: $0) }
        .padding(24)
        .background(RhythmTheme.coral.opacity(0.075), in: RoundedRectangle(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(RhythmTheme.coral.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct OccurrenceRow: View {
    @EnvironmentObject private var model: AppModel
    let occurrence: DailyOccurrence

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: outcomeSymbol)
                .font(.title3)
                .foregroundStyle(outcomeColour)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                NavigationLink { HabitDetailView(habitID: occurrence.habitID) } label: {
                    Text(occurrence.title).font(.body.weight(.medium))
                }
                .buttonStyle(.plain)
                Text(outcomeDetail)
                    .font(.caption)
                    .foregroundStyle(RhythmTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RhythmDates.dueLabel(occurrence.due))
                    .font(.caption2).foregroundStyle(RhythmTheme.muted)
            }
            Spacer(minLength: 4)
            if occurrence.outcome != nil {
                Button("Reopen") { model.reopen(occurrence) }
                    .font(.caption.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Reopen \(occurrence.title)")
            } else {
                Menu {
                    Button("Full: \(occurrence.normalTarget)") { model.complete(occurrence, outcome: .full) }
                        .disabled(!occurrence.canComplete(at: model.refreshedAt))
                    if let light = occurrence.lightTarget {
                        Button("Light: \(light)") { model.complete(occurrence, outcome: .light) }
                            .disabled(!occurrence.canComplete(at: model.refreshedAt))
                    }
                    Button("Later · 1 hour") { model.later(occurrence) }
                        .disabled(!occurrence.canComplete(at: model.refreshedAt))
                    Button("Skip Today") { model.skip(occurrence) }
                        .disabled(!occurrence.canComplete(at: model.refreshedAt))
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(RhythmTheme.ink.opacity(0.04), in: Circle())
                }
                .accessibilityLabel("Record \(occurrence.title)")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var outcomeSymbol: String {
        switch occurrence.outcome {
        case .full: "checkmark.circle.fill"
        case .light: "leaf.fill"
        case .skipped: "forward.end.circle"
        case nil: "circle"
        }
    }

    private var outcomeColour: Color {
        switch occurrence.outcome {
        case .full: RhythmTheme.leaf
        case .light: RhythmTheme.coral
        case .skipped: RhythmTheme.muted
        case nil: RhythmTheme.muted.opacity(0.5)
        }
    }

    private var outcomeDetail: String {
        switch occurrence.outcome {
        case .full: "Full · \(occurrence.normalTarget)"
        case .light: "Light · \(occurrence.lightTarget ?? "Small step")"
        case .skipped: "Skipped · not completed"
        case nil: occurrence.deferredUntil.map { "Later · \(RhythmDates.dueLabel(.timed(at: $0, timeZoneIdentifier: TimeZone.current.identifier)))" } ?? occurrence.normalTarget
        }
    }
}
