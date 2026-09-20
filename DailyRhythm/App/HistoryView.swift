import DailyRhythmCore
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    private var fullCount: Int { model.history.reduce(0) { $0 + $1.fullCount } }
    private var lightCount: Int { model.history.reduce(0) { $0 + $1.lightCount } }
    private var plannedCount: Int { model.history.reduce(0) { $0 + $1.totalCount } }

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

                if plannedCount == 0 {
                    RhythmCard {
                        RhythmEmptyState(
                            symbol: "chart.bar.xaxis",
                            title: "Your story starts here.",
                            message: "Scheduled habits and the steps you record will appear here. Nothing to catch up on."
                        )
                    }
                } else {
                    RhythmCard {
                        HStack(spacing: 24) {
                            total(fullCount, label: "Full", symbol: "checkmark.circle.fill", colour: RhythmTheme.leaf)
                            total(lightCount, label: "Light", symbol: "leaf.fill", colour: RhythmTheme.coral)
                            total(plannedCount, label: "Planned", symbol: "calendar", colour: RhythmTheme.muted)
                        }
                    }

                    VStack(spacing: 12) {
                        ForEach(model.history.reversed(), id: \.dayKey) { summary in
                            HistoryDayCard(summary: summary)
                        }
                    }
                    Text("Uncompleted steps stay uncompleted. Light steps never count as full goals, and a missed day doesn't erase your progress.")
                        .font(.footnote)
                        .foregroundStyle(RhythmTheme.muted)
                        .padding(.horizontal, 4)
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

    private func total(_ count: Int, label: String, symbol: String, colour: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(colour)
            Text("\(count)")
                .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
            Text(label).font(.caption).foregroundStyle(RhythmTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(label.lowercased()) steps")
    }
}

private struct HistoryDayCard: View {
    let summary: DailySummary
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
                        Text("No habits scheduled.")
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
                         : "\(summary.fullCount) full · \(summary.lightCount) light · \(summary.totalCount - summary.completedCount) not recorded")
                        .font(.caption)
                        .foregroundStyle(RhythmTheme.muted)
                    if summary.totalCount > 0 {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(RhythmTheme.ink.opacity(0.06))
                                Capsule().fill(RhythmTheme.coral.opacity(0.5))
                                    .frame(width: geometry.size.width * CGFloat(fraction(summary.completedCount)))
                                Capsule().fill(RhythmTheme.leaf)
                                    .frame(width: geometry.size.width * CGFloat(fraction(summary.fullCount)))
                            }
                        }
                        .frame(height: 5)
                        .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func fraction(_ count: Int) -> Double {
        summary.totalCount > 0 ? min(Double(count) / Double(summary.totalCount), 1) : 0
    }

    private func symbol(for occurrence: DailyOccurrence) -> String {
        switch occurrence.outcome {
        case .full: "checkmark.circle.fill"
        case .light: "leaf.fill"
        case nil: "circle"
        }
    }

    private func colour(for occurrence: DailyOccurrence) -> Color {
        switch occurrence.outcome {
        case .full: RhythmTheme.leaf
        case .light: RhythmTheme.coral
        case nil: RhythmTheme.muted
        }
    }

    private func detail(for occurrence: DailyOccurrence) -> String {
        switch occurrence.outcome {
        case .full: "Full · \(occurrence.normalTarget)"
        case .light: "Light · \(occurrence.lightTarget ?? "Small step")"
        case nil: "Not recorded · \(occurrence.normalTarget)"
        }
    }
}
