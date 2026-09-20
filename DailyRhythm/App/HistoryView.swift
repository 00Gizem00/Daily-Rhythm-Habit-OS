import DailyRhythmCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A week of small steps.")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("The last seven days, including today. Full and light goals each tell part of the story.")
                        .font(.subheadline)
                        .foregroundStyle(RhythmTheme.muted)
                }

                if let review = model.review {
                    DailyCloseCard(review: review)
                    WeeklyRhythmView(review: review)
                    if review.plannedCount == 0 {
                        Text("Your history starts with your first planned step. Off-days add nothing to the total.")
                            .font(.subheadline).foregroundStyle(RhythmTheme.muted)
                    }
                    Text("Day by day").font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 12) {
                        ForEach(review.days.reversed()) { day in
                            HistoryDayCard(day: day, asOf: review.asOf)
                        }
                    }
                    Text("Full and light steps count as completed. Skips stay separate. Schedule edits apply from their effective date; archive gaps add no pending work. One-offs count once, even if completed later. Saved results remain in history.")
                        .font(.footnote).foregroundStyle(RhythmTheme.muted)
                }

            }
            .padding(20)
            .padding(.bottom, 16)
        }
        .background(RhythmTheme.canvas)
        .navigationTitle("Your history")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await MainActor.run { model.refresh() } }
    }

}

private struct HistoryDayCard: View {
    let day: RhythmReviewDay
    let asOf: Date
    private var summary: DailySummary { day.summary }
    @State private var expanded = false

    var body: some View {
        RhythmCard {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(summary.occurrences, id: \.id) { occurrence in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(for: occurrence))
                                .foregroundStyle(colour(for: occurrence))
                                .frame(width: 20)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(occurrence.title).font(.subheadline.weight(.medium))
                                Text(detail(for: occurrence))
                                    .font(.caption)
                                    .foregroundStyle(RhythmTheme.muted)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if summary.totalCount == 0 {
                        Text("No steps planned. This off-day adds nothing to the total.")
                            .font(.subheadline)
                            .foregroundStyle(RhythmTheme.muted)
                    }
                }
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(RhythmDates.dayLabel(summary.dayKey))
                        .font(.headline)
                        .foregroundStyle(RhythmTheme.ink)
                    Text(summary.totalCount == 0
                         ? "No steps planned"
                         : "\(summary.fullCount) full · \(summary.lightCount) light · \(summary.skippedCount) skipped · \(summary.remainingCount) remaining")
                        .font(.caption)
                        .foregroundStyle(RhythmTheme.muted)
                    if day.plannedLaterCount > 0 {
                        Text("Includes \(day.plannedLaterCount) remaining steps planned for later.")
                            .font(.caption).foregroundStyle(RhythmTheme.muted)
                    }
                }
            }
        }
    }

    private func symbol(for occurrence: DailyOccurrence) -> String {
        switch occurrence.outcome {
        case .full: "checkmark.circle.fill"
        case .light: "leaf.fill"
        case .skipped: "forward.end.circle"
        case nil: "circle"
        }
    }

    private func colour(for occurrence: DailyOccurrence) -> Color {
        switch occurrence.outcome {
        case .full: RhythmTheme.leaf
        case .light: RhythmTheme.coral
        case .skipped: RhythmTheme.muted
        case nil: RhythmTheme.muted
        }
    }

    private func detail(for occurrence: DailyOccurrence) -> String {
        switch occurrence.outcome {
        case .full: return "Full · \(occurrence.normalTarget)"
        case .light: return "Light · \(occurrence.lightTarget ?? "Small step")"
        case .skipped: return "Skipped · not completed"
        case nil:
            if RhythmReviewDay.isPlannedLater(occurrence, at: asOf) {
                return "Planned for later · \(RhythmDates.dueLabel(occurrence.due)) · \(occurrence.normalTarget)"
            }
            return "\(day.isToday ? "Remaining" : "Not recorded") · \(occurrence.normalTarget)"
        }
    }
}
