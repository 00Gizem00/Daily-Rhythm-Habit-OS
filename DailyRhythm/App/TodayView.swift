import DailyRhythmCore
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var creationRoute: HabitCreationRoute?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let today = model.today {
                    if model.activeHabits.isEmpty && today.totalCount == 0 {
                        welcome
                    } else if today.totalCount == 0 {
                        RhythmCard {
                            RhythmEmptyState(
                                symbol: "leaf",
                                title: "Room to breathe.",
                                message: "No habits are scheduled today. Your next planned day is waiting in Habits."
                            )
                        }
                    } else {
                        progress(today)
                        if let next = model.nextOccurrence {
                            NextUpCard(occurrence: next)
                        } else if today.remainingCount == 0 {
                            RhythmCard {
                                Label("Today's rhythm is complete.", systemImage: "sparkles")
                                    .font(.title3.weight(.semibold))
                                Text("\(today.fullCount) full · \(today.lightCount) light. Every recorded step has its place.")
                                    .font(.subheadline)
                                    .foregroundStyle(RhythmTheme.muted)
                                    .padding(.top, 6)
                            }
                        } else {
                            RhythmCard {
                                Label("Planned for later.", systemImage: "calendar")
                                    .font(.title3.weight(.semibold))
                                Text("Pending steps keep their due dates. They have not been recorded as complete.")
                                    .font(.subheadline).foregroundStyle(RhythmTheme.muted)
                            }
                        }
                        if let undoID = model.lastCompletedID,
                           today.occurrences.contains(where: { $0.id == undoID && $0.outcome != nil }) {
                            HStack {
                                Label("Step saved", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(RhythmTheme.leaf)
                                Spacer()
                                Button("Undo") { model.reopen(undoID) }
                                    .fontWeight(.semibold)
                                    .frame(minHeight: 44)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 4)
                        }
                        ForEach(DayPart.allCases, id: \.self) { part in
                            let items = today.occurrences.filter { $0.dayPart == part }
                            if !items.isEmpty { dayPart(part, items: items) }
                        }
                        Text("Full and light steps are recorded separately. A lighter day still belongs in your story.")
                            .font(.footnote)
                            .foregroundStyle(RhythmTheme.muted)
                            .padding(.horizontal, 4)
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
            Button("Create my first habit") { creationRoute = .custom }
                .buttonStyle(RhythmPrimaryButtonStyle())
            Button("Try a reading habit") { creationRoute = .reading }
                .buttonStyle(RhythmSecondaryButtonStyle())
                .padding(.top, 8)
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
                Text("\(items.filter { $0.outcome != nil }.count)/\(items.count)")
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
                Text(occurrence.normalTarget)
                    .font(.title3)
                    .foregroundStyle(RhythmTheme.muted)
                Text(RhythmDates.dueLabel(occurrence.due))
                    .font(.caption).foregroundStyle(RhythmTheme.muted)
                if occurrence.isOverdue(at: model.refreshedAt) {
                    Text("Overdue · not recorded").font(.caption).foregroundStyle(RhythmTheme.coral)
                }
            }
            Button { model.complete(occurrence, outcome: .full) } label: {
                Label("Full step done", systemImage: "checkmark")
            }
            .buttonStyle(RhythmPrimaryButtonStyle())
            .accessibilityLabel("Complete \(occurrence.title), full goal: \(occurrence.normalTarget)")
            if let light = occurrence.lightTarget {
                Button { model.complete(occurrence, outcome: .light) } label: {
                    Label("Light step: \(light)", systemImage: "leaf")
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(RhythmSecondaryButtonStyle())
                .accessibilityLabel("Complete \(occurrence.title), light goal: \(light)")
            }
            NavigationLink("Edit or manage this plan") { HabitDetailView(habitID: occurrence.habitID) }
                .font(.subheadline)
        }
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
                Button("Reopen") { model.reopen(occurrence.id) }
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
                } label: {
                    Image(systemName: "checkmark")
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
        case nil: "circle"
        }
    }

    private var outcomeColour: Color {
        switch occurrence.outcome {
        case .full: RhythmTheme.leaf
        case .light: RhythmTheme.coral
        case nil: RhythmTheme.muted.opacity(0.5)
        }
    }

    private var outcomeDetail: String {
        switch occurrence.outcome {
        case .full: "Full · \(occurrence.normalTarget)"
        case .light: "Light · \(occurrence.lightTarget ?? "Small step")"
        case nil: occurrence.normalTarget
        }
    }
}
