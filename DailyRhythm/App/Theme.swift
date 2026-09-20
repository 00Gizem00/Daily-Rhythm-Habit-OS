import SwiftUI
import UIKit

enum RhythmTheme {
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.10, blue: 0.14, alpha: 1)
            : UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.16, blue: 0.20, alpha: 1)
            : .white
    })
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1)
            : UIColor(red: 0.12, green: 0.19, blue: 0.25, alpha: 1)
    })
    static let muted = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.67, green: 0.73, blue: 0.77, alpha: 1)
            : UIColor(red: 0.39, green: 0.44, blue: 0.47, alpha: 1)
    })
    static let coral = Color(red: 0.91, green: 0.34, blue: 0.24)
    static let leaf = Color(red: 0.26, green: 0.52, blue: 0.43)
    static let navy = Color(red: 0.12, green: 0.19, blue: 0.25)
}

struct RhythmCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RhythmTheme.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct RhythmPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 15)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .foregroundStyle(.white)
            .background(RhythmTheme.navy, in: RoundedRectangle(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct RhythmSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(RhythmTheme.ink)
            .background(RhythmTheme.ink.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct RhythmProgressRing: View {
    let full: Int
    let light: Int
    let planned: Int

    private var fullFraction: Double {
        planned > 0 ? min(Double(full) / Double(planned), 1) : 0
    }

    private var totalFraction: Double {
        planned > 0 ? min(Double(full + light) / Double(planned), 1) : 0
    }

    var body: some View {
        ZStack {
            Circle().stroke(RhythmTheme.ink.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: totalFraction)
                .stroke(RhythmTheme.coral.opacity(0.55), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: fullFraction)
                .stroke(RhythmTheme.leaf, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(full + light)/\(planned)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.7)
                Text("steps")
                    .font(.caption)
                    .foregroundStyle(RhythmTheme.muted)
            }
            .padding(12)
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(full) full completions, \(light) light completions, \(planned) planned")
    }
}

struct RhythmEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(RhythmTheme.coral)
                .frame(width: 78, height: 78)
                .background(RhythmTheme.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 25))
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(RhythmTheme.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .foregroundStyle(RhythmTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
