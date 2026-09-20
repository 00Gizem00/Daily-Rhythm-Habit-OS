import AppIntents
import SwiftUI
import WidgetKit
import DailyRhythmCore

@main
struct DailyRhythmWidgetBundle: WidgetBundle {
    var body: some Widget {
        DailyRhythmTodayWidget()
    }
}

struct DailyRhythmTodayWidget: Widget {
    let kind = SharedRoutineStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RhythmTimelineProvider()) { entry in
            RhythmWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Your Daily Rhythm")
        .description("See your next step and record progress without opening the app.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct RhythmWidgetEntry: TimelineEntry {
    let date: Date
    let agenda: DailyAgenda?
    var summary: DailySummary? { agenda?.summary }
    let storageUnavailable: Bool

    static func placeholder(at date: Date = Date()) -> Self {
        Self(date: date, agenda: nil, storageUnavailable: false)
    }
}

struct RhythmTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> RhythmWidgetEntry {
        .placeholder()
    }

    func getSnapshot(in context: Context, completion: @escaping (RhythmWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder())
        } else {
            completion(entry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RhythmWidgetEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let current = entry(at: now)
        guard !current.storageUnavailable,
              let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            // Temporary data protection / storage failure is visible, never displayed as zero habits.
            completion(Timeline(entries: [current], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }
        // Precompute the new local day so a delayed system refresh cannot display yesterday's tasks.
        // Calendar arithmetic matters: a local day is not always 86,400 seconds.
        let wakeTimes = Set((current.agenda?.occurrences.compactMap(\.deferredUntil) ?? [])
            .filter { $0 > now && $0 < nextDay })
        let entries = [current] + wakeTimes.sorted().map { entry(at: $0) } + [entry(at: nextDay)]
        completion(Timeline(entries: entries, policy: .after(nextDay.addingTimeInterval(60))))
    }

    private func entry(at date: Date) -> RhythmWidgetEntry {
        do {
            let agenda = try SharedRoutineStore.makeStore().agenda(at: date)
            return RhythmWidgetEntry(date: date, agenda: agenda, storageUnavailable: false)
        } catch {
            return RhythmWidgetEntry(date: date, agenda: nil, storageUnavailable: true)
        }
    }
}

private struct RhythmWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RhythmWidgetEntry

    private let leaf = Color(red: 0.26, green: 0.52, blue: 0.43)
    private let coral = Color(red: 0.91, green: 0.34, blue: 0.24)

    var body: some View {
        Group {
            if entry.storageUnavailable {
                unavailable
            } else if let summary = entry.summary {
                switch family {
                case .accessoryCircular:
                    circular(summary)
                case .accessoryRectangular:
                    rectangular(summary)
                case .accessoryInline:
                    Text("Rhythm: \(summary.fullCount) full · \(summary.lightCount) light · \(summary.skippedCount) skipped")
                case .systemMedium:
                    medium(summary)
                default:
                    small(summary)
                }
            } else {
                preview
            }
        }
    }

    @ViewBuilder
    private var unavailable: some View {
        if family == .accessoryInline {
            Text("Rhythm: open app to refresh")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "arrow.clockwise.circle")
                Text("Open to refresh")
                    .font(.headline)
                    .minimumScaleFactor(0.75)
                if family == .systemSmall || family == .systemMedium {
                    Text("Unlock your iPhone and open Daily Rhythm.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if family == .accessoryInline {
            Text("Your next small step")
        } else if family == .accessoryCircular {
            Image(systemName: "circle.dotted.circle.fill")
                .font(.largeTitle)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("DAILY RHYTHM", systemImage: "sun.horizon")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(leaf)
                Text("Your next\nsmall step.")
                    .font(.title3.weight(.semibold))
                if family != .accessoryRectangular {
                    Text("Build a rhythm that fits your day.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func small(_ summary: DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("NEXT UP")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(leaf)
                Spacer(minLength: 4)
                Text("\(summary.completedCount)/\(summary.totalCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let next = entry.agenda?.next(at: entry.date) {
                Text(next.title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
                Text(summary.isLightDay ? (next.lightTarget ?? next.normalTarget) : next.normalTarget)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Button(intent: CompleteWidgetOccurrenceIntent(occurrence: next, useSmallStep: summary.isLightDay && next.lightTarget != nil)) {
                        Label(summary.isLightDay && next.lightTarget != nil ? "Light" : "Full",
                              systemImage: summary.isLightDay && next.lightTarget != nil ? "leaf" : "checkmark")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(leaf)
                    .accessibilityLabel("Complete \(next.title): \(summary.isLightDay ? (next.lightTarget ?? next.normalTarget) : next.normalTarget)")
                    if let lightTarget = next.lightTarget, !summary.isLightDay {
                        Button(intent: CompleteWidgetOccurrenceIntent(occurrence: next, useSmallStep: true)) {
                            Image(systemName: "leaf")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(coral)
                        .accessibilityLabel("Complete small step for \(next.title): \(lightTarget)")
                    }
                }
                .controlSize(.small)
            } else {
                Spacer(minLength: 0)
                Image(systemName: summary.totalCount > 0 ? "sparkles" : "sun.horizon")
                    .font(.title2)
                    .foregroundStyle(leaf)
                Text(summary.remainingCount > 0 ? "Planned for later." : (summary.totalCount > 0 ? "No steps waiting." : "Room to begin."))
                    .font(.headline)
                    .minimumScaleFactor(0.8)
                Text(summary.totalCount > 0
                     ? "\(summary.fullCount) full · \(summary.lightCount) light · \(summary.skippedCount) skipped"
                     : "Open the app to add a habit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ summary: DailySummary) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("TODAY'S RHYTHM")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: fraction(summary.completedCount, of: summary.totalCount))
                        .stroke(coral.opacity(0.6), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle()
                        .trim(from: 0, to: fraction(summary.fullCount, of: summary.totalCount))
                        .stroke(leaf, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(summary.completedCount)/\(summary.totalCount)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .minimumScaleFactor(0.7)
                }
                .frame(width: 70, height: 70)
                .padding(4)
                Text("\(summary.fullCount) full · \(summary.lightCount) light\n\(summary.skippedCount) skipped")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(summary.fullCount) full completions, \(summary.lightCount) light completions, \(summary.skippedCount) skipped, \(summary.remainingCount) pending, of \(summary.totalCount) planned steps")
            VStack(alignment: .leading, spacing: 9) {
                if entry.agenda?.occurrences.isEmpty != false {
                    Text("Room to begin.")
                        .font(.headline)
                    Text("Open Daily Rhythm to create your first habit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleSteps(summary)) { step in
                        HStack(spacing: 7) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Text(step.outcome == .skipped ? "Skipped" : ((step.outcome == .light || (!step.isResolved && summary.isLightDay)) ? (step.lightTarget ?? step.normalTarget) : step.normalTarget))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .privacySensitive()
                            Spacer(minLength: 0)
                            if step.outcome == .skipped {
                                Image(systemName: "forward.end.circle").accessibilityLabel("Skipped, not completed")
                            } else if step.isCompleted {
                                Image(systemName: step.outcome == .light ? "leaf.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(step.outcome == .light ? coral : leaf)
                                    .accessibilityLabel(step.outcome == .light ? "Small step completed" : "Completed")
                            } else if step.isReady(at: entry.date) {
                                Button(intent: CompleteWidgetOccurrenceIntent(occurrence: step, useSmallStep: summary.isLightDay && step.lightTarget != nil)) {
                                    Image(systemName: summary.isLightDay && step.lightTarget != nil ? "leaf" : "checkmark.circle")
                                        .font(.title3)
                                        .padding(3)
                                }
                                .buttonStyle(.plain)
                                .tint(leaf)
                                .accessibilityLabel("Complete \(step.title): \(summary.isLightDay ? (step.lightTarget ?? step.normalTarget) : step.normalTarget)")
                            } else {
                                Image(systemName: "clock").accessibilityLabel("Planned for later")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func circular(_ summary: DailySummary) -> some View {
        Gauge(value: Double(summary.completedCount), in: 0...Double(max(summary.totalCount, 1))) {
            Image(systemName: "sun.horizon")
        } currentValueLabel: {
            Text("\(summary.completedCount)")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityLabel("\(summary.fullCount) full completions, \(summary.lightCount) light completions, \(summary.skippedCount) skipped, \(summary.remainingCount) pending, of \(summary.totalCount) planned steps")
    }

    private func rectangular(_ summary: DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(summary.fullCount) full · \(summary.lightCount) light · \(summary.skippedCount) skipped")
                .font(.headline)
            if let next = entry.agenda?.next(at: entry.date) {
                Text("Next: \(next.title)")
                    .font(.caption)
                    .lineLimit(1)
                    .privacySensitive()
            } else {
                Text(summary.remainingCount > 0 ? "Planned for later." : (summary.totalCount > 0 ? "No steps waiting." : "Room to begin."))
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func visibleSteps(_ summary: DailySummary) -> [DailyOccurrence] {
        let items = entry.agenda?.occurrences ?? summary.occurrences
        return Array((items.filter { $0.isReady(at: entry.date) }
                      + items.filter { !$0.isResolved && !$0.isReady(at: entry.date) }
                      + items.filter(\.isResolved)).prefix(3))
    }

    private func fraction(_ value: Int, of total: Int) -> Double {
        total > 0 ? min(Double(value) / Double(total), 1) : 0
    }
}
