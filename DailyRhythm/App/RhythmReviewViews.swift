import DailyRhythmCore
import SwiftUI

struct DailyCloseCard: View {
    let review: RhythmReview

    var body: some View {
        RhythmCard {
            VStack(alignment: .leading, spacing: 16) {
                Label("Daily Close", systemImage: "moon.stars")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Today so far · \(RhythmDates.dayLabel(review.agenda.summary.dayKey))")
                    .font(.subheadline).foregroundStyle(RhythmTheme.muted)
                let summary = review.agenda.summary
                ReviewCounts(full: summary.fullCount, light: summary.lightCount,
                             skipped: summary.skippedCount, remaining: summary.remainingCount)
                Text(status(summary))
                    .font(.subheadline.weight(.medium))
                if let today = review.days.last, today.plannedLaterCount > 0 {
                    Text("\(today.plannedLaterCount) of the remaining steps are planned for later.")
                        .font(.footnote).foregroundStyle(RhythmTheme.muted)
                }
                Text("Counts follow the original planned day. Steps from earlier days stay in their history totals.")
                    .font(.footnote).foregroundStyle(RhythmTheme.muted)
                Divider()
                Label("Tomorrow's first planned step", systemImage: "sunrise")
                    .font(.headline)
                if let next = review.tomorrowFirstStep {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(next.title).font(.headline)
                        Text(next.normalTarget).font(.subheadline)
                        Text("\(next.dayPart.displayName) · \(RhythmDates.dueLabel(next.due))")
                            .font(.caption).foregroundStyle(RhythmTheme.muted)
                        if let minutes = next.durationMinutes {
                            Text("\(minutes) min").font(.caption).foregroundStyle(RhythmTheme.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(review.tomorrow.totalCount == 0
                         ? "No steps planned for tomorrow."
                         : "No remaining steps due from tomorrow's plan.")
                        .font(.subheadline).foregroundStyle(RhythmTheme.muted)
                }
                Text("A preview of tomorrow's plan. Earlier unfinished steps are separate.")
                    .font(.caption).foregroundStyle(RhythmTheme.muted)
            }
        }
    }

    private func status(_ summary: DailySummary) -> String {
        if summary.totalCount == 0 { return "No steps planned today. An off-day is not a missed day." }
        if summary.completedCount == summary.totalCount { return "Every planned step is complete." }
        if summary.remainingCount == 0 { return "No steps remaining. Skipped steps are not completions." }
        return "\(summary.completedCount) of \(summary.totalCount) planned steps completed."
    }
}

struct ReviewCounts: View {
    let full: Int
    let light: Int
    let skipped: Int
    let remaining: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                  ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 125), alignment: .leading)],
                  alignment: .leading, spacing: 12) {
            count(full, label: "Full", symbol: "checkmark.circle.fill", color: RhythmTheme.leaf)
            count(light, label: "Light", symbol: "leaf.fill", color: RhythmTheme.coral)
            count(skipped, label: "Skipped", symbol: "forward.end.circle", color: RhythmTheme.muted)
            count(remaining, label: "Remaining", symbol: "circle", color: RhythmTheme.muted)
        }
    }

    private func count(_ value: Int, label: String, symbol: String, color: Color) -> some View {
        Label {
            Text("\(value) \(label)").monospacedDigit()
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .font(.subheadline.weight(.medium))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label.lowercased()) steps")
    }
}

struct WeeklyRhythmView: View {
    let review: RhythmReview
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your weekly rhythm").font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Seven days through today. Each number is a planned step, counted once on its original day.")
                .font(.subheadline).foregroundStyle(RhythmTheme.muted)
            RhythmCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(review.fullCount + review.lightCount) of \(review.plannedCount) planned steps completed")
                        .font(.headline)
                    ReviewCounts(full: review.fullCount, light: review.lightCount,
                                 skipped: review.skippedCount, remaining: review.remainingCount)
                    if review.plannedLaterCount > 0 {
                        Text("\(review.plannedLaterCount) remaining steps are planned for later.")
                            .font(.footnote).foregroundStyle(RhythmTheme.muted)
                    }
                    Text("Remaining includes pending and postponed steps; it is not a missed-step count.")
                        .font(.footnote).foregroundStyle(RhythmTheme.muted)
                }
            }
            // Symbols, counts and text provide the same information as the tint.
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                ForEach(review.days) { day in
                    let summary = day.summary
                    VStack(alignment: .leading, spacing: 10) {
                        Text(RhythmDates.dayLabel(summary.dayKey))
                            .font(.subheadline.weight(.semibold))
                        if day.isToday { Text("Today").font(.caption.weight(.bold)) }
                        if summary.totalCount == 0 {
                            Label("Off-day", systemImage: "minus.circle")
                                .font(.subheadline)
                            Text("No steps planned").font(.caption)
                        } else {
                            Text("\(summary.completedCount)/\(summary.totalCount) completed")
                                .font(.subheadline.monospacedDigit())
                            VStack(alignment: .leading, spacing: 6) {
                                Label("\(summary.fullCount) full", systemImage: "checkmark.circle.fill")
                                Label("\(summary.lightCount) light", systemImage: "leaf.fill")
                                Label("\(summary.skippedCount) skipped", systemImage: "forward.end.circle")
                                Label("\(summary.remainingCount) remaining", systemImage: "circle")
                            }.font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
                    .background(summary.completedCount > 0 ? RhythmTheme.leaf.opacity(0.12) : RhythmTheme.card,
                                in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(RhythmDates.dayLabel(summary.dayKey))\(day.isToday ? ", today" : "")")
                    .accessibilityValue(summary.totalCount == 0 ? "Off-day. No steps planned."
                        : "\(summary.totalCount) planned, \(summary.fullCount) full, \(summary.lightCount) light, \(summary.skippedCount) skipped, \(summary.remainingCount) remaining, including \(day.plannedLaterCount) planned for later.")
                }
            }
        }
    }
}
