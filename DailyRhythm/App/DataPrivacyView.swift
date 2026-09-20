import CoreSpotlight
import DailyRhythmCore
import SwiftUI
import UIKit

struct RoutineExportShare: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class DataPrivacyModel: ObservableObject {
    static let shared = DataPrivacyModel()
    @Published private(set) var busy = false
    @Published private(set) var erasurePending = false
    @Published var error: String?
    @Published var notice: String?
    @Published var share: RoutineExportShare?
    private var stagedExportURL: URL?
    private let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("DailyRhythmExports", isDirectory: true)

    private init() {
        // A cold launch cannot still have a live share controller from the previous process.
        do { try removeIfPresent(exportDirectory) }
        catch { self.error = "A previous temporary export couldn't be removed: \(error.localizedDescription)" }
    }

    func refresh() {
        do { erasurePending = try SharedRoutineStore.makeStore().dataLifecycle().erasurePending }
        catch { self.error = error.localizedDescription }
    }

    func export(_ format: RoutineExportFormat) {
        guard !busy, share == nil else { return }
        error = nil
        do {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            let url = exportDirectory.appendingPathComponent("DailyRhythm-\(UUID().uuidString).\(format.rawValue)")
            do { try SharedRoutineStore.makeStore().writeExport(format: format, to: url) }
            catch { try? removeIfPresent(url); throw error }
            stagedExportURL = url
            share = RoutineExportShare(url: url)
        } catch { self.error = "Export couldn't be prepared: \(error.localizedDescription)" }
    }

    func endShare(url: URL, completed: Bool, failure: String?) {
        do { try removeIfPresent(url) }
        catch { self.error = "The temporary export couldn't be removed: \(error.localizedDescription)" }
        share = nil
        stagedExportURL = nil
        if let failure { error = "Export wasn't shared: \(failure)" }
        else if completed { notice = "Export shared. Copies saved outside Daily Rhythm are controlled by you." }
    }

    func dismissShare() {
        if let url = stagedExportURL { endShare(url: url, completed: false, failure: nil) }
    }

    func erase(expectedGeneration: UUID, model: AppModel, setup: OnboardingPreferences) async {
        guard !busy, share == nil else { return }
        busy = true; error = nil; notice = nil
        defer { busy = false; refresh() }
        do {
            let store = try SharedRoutineStore.makeStore()
            let lifecycle = try store.beginErasure(expectedGeneration: expectedGeneration)
            erasurePending = true
            model.clearForErasure()
            // All hooks must succeed before finishErasure releases the durable barrier.
            // Future session/Live Activity cleanup belongs here before that final call.
            try await RhythmNotifications.coordinator().erasePreferences()
            #if DAILY_RHYTHM_SCHEMA_SPIKE && compiler(>=6.4)
            if #available(iOS 27.0, *) { try await ReminderSchemaIndex.shared.clearForErasure() }
            else { try await clearSearchIndex() }
            #else
            try await clearSearchIndex()
            #endif
            setup.clearForErasure()
            try removeIfPresent(exportDirectory)
            let documents = URL.documentsDirectory
            for url in try FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) {
                let stem = url.deletingPathExtension().lastPathComponent
                if url.pathExtension == "json", stem.hasPrefix("schema-smoke-"),
                   UUID(uuidString: String(stem.dropFirst("schema-smoke-".count))) != nil {
                    try removeIfPresent(url)
                }
            }
            try store.finishErasure(generation: lifecycle.generation)
            NotificationSettingsModel.shared.clearAfterErasure()
            RhythmNavigation.shared.openToday()
            RhythmSurfaceRefresh.reload()
            model.refresh()
            notice = "Local data erased. Saved exports outside this app and iOS permission choices are unchanged."
        } catch {
            self.error = "Erase couldn't finish: \(error.localizedDescription) You can retry from Data & Privacy."
            RhythmSurfaceRefresh.reload()
            model.refresh()
        }
    }

    private func clearSearchIndex() async throws {
        try await CSSearchableIndex(name: "DailyRhythmReminderSchemas").deleteAllSearchableItems()
    }

    private func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
    }
}

struct DataPrivacyView: View {
    @ObservedObject private var privacy = DataPrivacyModel.shared
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var setup: OnboardingPreferences
    @State private var eraseGeneration: UUID?

    var body: some View {
        Form {
            Section("Your data stays local") {
                Text("Your plans and history are stored on this device in storage shared with Daily Rhythm widgets and Shortcuts. There is no account, analytics tracker or cloud sync in this build. Device backups are controlled by your iOS settings.")
                Text("AI planning is not enabled in this build. Any future optional cloud AI feature will explain what is sent before use; cloud processing is not entirely on-device. Manual tracking and export remain available without AI or Pro.")
            }
            Section("Export your data") {
                Button("Export JSON", systemImage: "doc") { privacy.export(.json) }
                Button("Export history CSV", systemImage: "tablecells") { privacy.export(.csv) }
                Text("JSON includes all saved plans, schedule revisions, archived plans, history records and Light Day choices. CSV includes recorded full/light/skipped outcomes and pending overrides, including archived records. Unrecorded planned days are not fabricated as history.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("You choose where to save or share. Spreadsheet formula-like text is prefixed with an apostrophe in CSV; JSON preserves the original text. This build does not import backups.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.disabled(privacy.erasurePending)
            Section("Erase local data") {
                if privacy.erasurePending {
                    Text("An erase is unfinished. Tracking is paused so older actions cannot restore removed data. Retry to finish cleanup.")
                }
                Button(privacy.erasurePending ? "Finish local erase" : "Erase Local Data", role: .destructive) {
                    do { eraseGeneration = try SharedRoutineStore.makeStore().dataLifecycle().generation }
                    catch { privacy.error = error.localizedDescription }
                }
                Text("Removes plans, recorded history, archived data, migration backups, setup drafts, reminder preferences, app-owned notifications, search entries and local test reports. This cannot be undone. Export first if you want a copy.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Copies you saved or shared elsewhere are not removed. iOS controls widget refresh timing. A small recovery marker and empty coordination lock files remain to reject old actions.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error = privacy.error {
                Section("Action needed") { Text(error); Button("Refresh status") { privacy.refresh() } }
            }
        }
        .navigationTitle("Data & Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(privacy.busy)
        .disabled(privacy.busy)
        .task { privacy.refresh() }
        .sheet(isPresented: Binding(
            get: { eraseGeneration != nil }, set: { if !$0 { eraseGeneration = nil } }
        )) {
            EraseLocalDataConfirmation {
                eraseGeneration = nil
            } confirm: {
                if let generation = eraseGeneration {
                    eraseGeneration = nil
                    Task { await privacy.erase(expectedGeneration: generation, model: model, setup: setup) }
                }
            }
        }
        .sheet(item: $privacy.share, onDismiss: {
            // The activity callback normally removes its file; swipe dismissal uses the same cleanup.
            privacy.dismissShare()
        }) { share in
            RoutineShareSheet(url: share.url) { completed, error in
                privacy.endShare(url: share.url, completed: completed, failure: error)
            }
        }
    }
}

private struct EraseLocalDataConfirmation: View {
    let cancel: () -> Void
    let confirm: () -> Void
    @State private var confirmation = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently removes all local plans and history. There is no Undo.")
                        .font(.headline)
                    Text("To keep a copy, cancel and export JSON first. Save the export outside Daily Rhythm before returning here. Previously shared copies and iOS permission choices remain.")
                }
                Section("Type ERASE to confirm") {
                    TextField("ERASE", text: $confirmation)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Type ERASE to confirm permanent deletion")
                    Button("Permanently erase local data", role: .destructive, action: confirm)
                        .disabled(confirmation != "ERASE")
                }
            }
            .navigationTitle("Erase Local Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) } }
        }
    }
}

private struct RoutineShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: @MainActor (Bool, String?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            let message = error?.localizedDescription
            Task { @MainActor in completion(completed, message) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
