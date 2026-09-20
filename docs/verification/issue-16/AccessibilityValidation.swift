import DailyRhythmCore
import SwiftUI
import UIKit

// Isolated app-model and resolved-colour checks. This is not a VoiceOver/layout audit.
@MainActor enum AccessibilityValidation {
    static var started = false

    static func run(model: AppModel, setup: OnboardingPreferences) async {
        guard !started, ProcessInfo.processInfo.environment["DAILY_RHYTHM_ACCESSIBILITY_VALIDATION"] == "1",
              Bundle.main.bundleIdentifier?.hasPrefix("com.lumetechllc.DailyRhythm.Validation16.") == true else { return }
        started = true
        var report: [String: Any] = ["passed": false, "environment": UIDevice.current.systemVersion,
            "execution": "AppModel mutations and UIKit-resolved colours; no UI interaction, rendering or physical haptic verification"]
        var checks: [String] = []
        var ratios: [String: Double] = [:]
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: "AccessibilityValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        do {
            let store = try SharedRoutineStore.makeStore()
            try check(try store.habits(includeArchived: true).isEmpty, "isolated store starts empty")
            model.refresh()
            let day = LocalDay(calendar: .current).key(for: Date())
            let definition = HabitDefinition(title: "Read a long chapter at my own pace", normalTarget: "Ten pages", lightTarget: "One page",
                                             dayPart: .morning, recurrence: .once(dayKey: day))
            try check(model.addHabit(definition, expectedGeneration: model.dataGeneration), "create succeeds through AppModel")
            try check(model.completionFeedback == 0, "creation does not signal completion")
            let pending = model.today!.occurrences[0]
            model.complete(pending, outcome: .full)
            try check(model.today?.fullCount == 1 && model.completionFeedback == 1, "saved full completion emits one event")
            try check(model.lastActionDescription?.contains("full step saved") == true, "full result has explicit text")
            let completedBytes = try Data(contentsOf: store.fileURL)
            model.complete(pending, outcome: .full)
            try check(model.operationError != nil && model.completionFeedback == 1, "stale repeat fails without success feedback")
            try check(try Data(contentsOf: store.fileURL) == completedBytes, "stale repeat preserves saved bytes")
            model.undoLastAction()
            try check(model.today?.completedCount == 0 && model.completionFeedback == 1 && model.lastActionDescription == nil,
                      "undo clears result text without a completion event")
            model.complete(model.today!.occurrences[0], outcome: .light)
            try check(model.today?.lightCount == 1 && model.completionFeedback == 2, "saved light completion emits one event")
            try check(model.lastActionDescription?.contains("light step saved") == true, "light result has explicit text")
            model.reopen(model.today!.occurrences[0])
            try check(model.today?.completedCount == 0 && model.completionFeedback == 2, "reopen does not signal completion")
            model.skip(model.today!.occurrences[0])
            try check(model.today?.skippedCount == 1 && model.today?.completedCount == 0 && model.completionFeedback == 2,
                      "skip is saved without completion feedback or completion count")
            try check(model.lastActionDescription?.contains("skipped, not completed") == true, "skip text distinguishes its outcome")
            model.undoLastAction()
            model.later(model.today!.occurrences[0])
            try check(model.today?.occurrences[0].deferredUntil != nil && model.completionFeedback == 2,
                      "later is saved without completion feedback")
            try check(model.lastActionDescription?.contains("postponed by one hour") == true, "later has explicit result text")
            model.undoLastAction()
            let current = model.today!.occurrences[0]
            _ = try store.perform(.skip, on: current)
            model.complete(current, outcome: .full)
            try check(model.operationError != nil && model.completionFeedback == 2 && model.today?.skippedCount == 1,
                      "concurrent mutation rejects stale app completion without success feedback")
            model.refresh()
            try check(model.completionFeedback == 2, "refresh does not replay completion feedback")
            model.clearForErasure()
            try check(model.completionFeedback == 2 && model.lastUndo == nil && model.lastActionDescription == nil,
                      "clearing app state does not change the feedback trigger")
            model.refresh()
            let saved = try Data(contentsOf: store.fileURL)
            try Data("invalid fixture store".utf8).write(to: store.fileURL, options: .atomic)
            model.reopen(model.today!.occurrences[0])
            try check(model.operationError != nil && model.loadError != nil && model.completionFeedback == 2,
                      "unreadable store rejects mutation and shows errors without success feedback")
            try saved.write(to: store.fileURL, options: .atomic)
            model.operationError = nil
            model.refresh()
            setup.finish()

            for style in [UIUserInterfaceStyle.light, .dark] {
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = UITraitCollection(traitsFrom: [UITraitCollection(userInterfaceStyle: style),
                                                               UITraitCollection(accessibilityContrast: contrast)])
                    let mode = "\(style == .dark ? "dark" : "light")-\(contrast == .high ? "increased" : "normal")"
                    let canvas = rgb(RhythmTheme.canvas, traits), card = rgb(RhythmTheme.card, traits)
                    let coral = rgb(RhythmPalette.coral, traits), ink = rgb(RhythmTheme.ink, traits)
                    let nextUp = zip(coral, canvas).map { $0 * 0.075 + $1 * 0.925 }
                    let foregrounds = ["ink": ink, "muted": rgb(RhythmTheme.muted, traits),
                                       "coral": coral, "leaf": rgb(RhythmPalette.leaf, traits)]
                    for (surface, background) in ["canvas": canvas, "card": card, "next-up": nextUp] {
                        for (name, foreground) in foregrounds {
                            let key = "\(mode)/\(name)-on-\(surface)"
                            ratios[key] = ratio(foreground, background)
                            try check(ratios[key]! >= 4.5, "text contrast >= 4.5:1: \(key)")
                        }
                    }
                    let widgetBackground = rgb(Color(uiColor: .systemBackground), traits)
                    for name in ["leaf", "coral"] {
                        let key = "\(mode)/widget-\(name)"
                        ratios[key] = ratio(foregrounds[name]!, widgetBackground)
                        try check(ratios[key]! >= 4.5, "widget text contrast >= 4.5:1: \(key)")
                    }
                    let key = "\(mode)/widget-button-white-text"
                    ratios[key] = ratio([1, 1, 1], rgb(RhythmPalette.actionFill, traits))
                    try check(ratios[key]! >= 4.5, "widget filled-button contrast >= 4.5:1: \(key)")
                }
            }
            report["passed"] = true
        } catch { report["error"] = error.localizedDescription }
        report["checks"] = checks
        report["contrastRatios"] = ratios
        let output = URL.documentsDirectory.appendingPathComponent("accessibility-validation-result.json")
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    }

    private static func rgb(_ color: Color, _ traits: UITraitCollection) -> [Double] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [Double(red), Double(green), Double(blue)]
    }

    private static func ratio(_ first: [Double], _ second: [Double]) -> Double {
        func luminance(_ values: [Double]) -> Double {
            zip(values, [0.2126, 0.7152, 0.0722]).reduce(0) {
                $0 + ($1.0 <= 0.04045 ? $1.0 / 12.92 : pow(($1.0 + 0.055) / 1.055, 2.4)) * $1.1
            }
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
