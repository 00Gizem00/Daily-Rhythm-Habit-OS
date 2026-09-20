import Combine
import DailyRhythmCore
import Foundation

/// A resumable local draft, separate from the shared routine document. Losing the
/// finished flag cannot duplicate habits because confirmation uses stable draft IDs.
@MainActor
final class OnboardingPreferences: ObservableObject {
    @Published private(set) var progress: OnboardingProgress
    @Published private(set) var loadError: String?
    private let defaults: UserDefaults
    private let key = "dailyRhythm.onboarding.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        progress = OnboardingProgress()
        guard let data = defaults.data(forKey: key) else { return }
        do {
            let saved = try JSONDecoder().decode(OnboardingProgress.self, from: data)
            guard saved.version == 1 else { throw RoutineStoreError.unsupportedVersion(saved.version) }
            progress = saved
        } catch {
            // Preserve unreadable/unknown drafts. Normal manual creation remains usable.
            loadError = "Your setup draft couldn't be read. It has been kept. You can still create a habit from Today."
        }
    }

    func begin() { update { $0.status = .inProgress } }
    func pause() { update { if $0.status != .finished { $0.status = .skipped } } }
    func finish() { update { $0.status = .finished; $0.draft = nil } }
    func choose(_ template: OnboardingTemplate) {
        update { $0.status = .inProgress; $0.draft = OnboardingDraft(template: template) }
    }
    func updateEntry(id: UUID, form: HabitFormDraft) {
        update { progress in
            guard let index = progress.draft?.entries.firstIndex(where: { $0.id == id }) else { return }
            progress.draft?.entries[index].form = form
        }
    }
    func removeEntry(id: UUID) { update { $0.draft?.entries.removeAll { $0.id == id } } }
    func addEntry() {
        update { progress in
            guard let count = progress.draft?.entries.count, count < 3 else { return }
            progress.draft?.entries.append(contentsOf: OnboardingDraft(template: .manual).entries)
        }
    }

    private func update(_ body: (inout OnboardingProgress) -> Void) {
        guard loadError == nil else { return }
        var next = progress
        body(&next)
        guard next != progress else { return }
        guard let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: key)
        progress = next
    }
}
