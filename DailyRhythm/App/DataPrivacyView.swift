import CoreSpotlight
import DailyRhythmCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RoutineExportShare: Identifiable {
    let id = UUID()
    let url: URL
}

struct RoutineRestorePreview: Identifiable {
    let id = UUID()
    let backup: RoutineBackup
    let generation: UUID
}

@MainActor
final class DataPrivacyModel: ObservableObject {
    static let shared = DataPrivacyModel()
    @Published private(set) var busy = false
    @Published private(set) var erasurePending = false
    @Published var error: String?
    @Published var notice: String?
    @Published var share: RoutineExportShare?
    @Published var restorePreview: RoutineRestorePreview?
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

    func prepareRestore(from url: URL) {
        guard !busy, share == nil else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: 20_000_001) ?? Data()
            let backup = try RoutineBackup(jsonExport: bytes)
            let generation = try SharedRoutineStore.makeStore().validateAccess()
            restorePreview = RoutineRestorePreview(backup: backup, generation: generation)
        } catch { self.error = error.localizedDescription }
    }

    func restore(_ preview: RoutineRestorePreview, model: AppModel, setup: OnboardingPreferences) throws {
        guard !busy, share == nil else { throw LocalDataError.staleAction }
        try SharedRoutineStore.makeStore(expectedGeneration: preview.generation).restoreBackup(preview.backup)
        restorePreview = nil
        setup.finish()
        RhythmNavigation.shared.openToday()
        RhythmSurfaceRefresh.reload()
        model.refresh()
        notice = "Restored \(preview.backup.planCount) plans and \(preview.backup.recordCount) saved records. Re-select habits in any configured Controls or Shortcuts. Reminder preferences are not included in backups."
        #if DAILY_RHYTHM_SCHEMA_SPIKE && compiler(>=6.4)
        if #available(iOS 27.0, *) { Task { await ReminderSchemaIndex.shared.refreshAfterMutation() } }
        #endif
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
                let ownedPrefixes = ["schema-smoke-", "restore-result-", "restore-"]
                if url.pathExtension == "json", ownedPrefixes.contains(where: {
                    stem.hasPrefix($0) && UUID(uuidString: String(stem.dropFirst($0.count))) != nil
                }) {
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
    @State private var choosingBackup = false

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
                Text("You choose where to save or share. Spreadsheet formula-like text is prefixed with an apostrophe in CSV; JSON preserves the original text.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.disabled(privacy.erasurePending)
            Section("Restore a JSON backup") {
                Button("Choose JSON backup", systemImage: "square.and.arrow.down") { choosingBackup = true }
                Text("Restore plans and history into an empty app. Existing data is never overwritten or merged. CSV cannot be restored. Reminder preferences and iOS permissions are not part of the backup.")
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
        .fileImporter(isPresented: $choosingBackup, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): privacy.prepareRestore(from: url)
            case .failure(let error): privacy.error = error.localizedDescription
            }
        }
        .sheet(item: $privacy.restorePreview) { preview in
            NavigationStack {
                Form {
                    Text("Restore \(preview.backup.planCount) plans and \(preview.backup.recordCount) saved records from this backup?")
                    Text("History and archive status are preserved. Configured Controls and Shortcuts must select the restored habits again. Existing plans or history will block this operation.")
                    Button("Restore backup") {
                        do { try privacy.restore(preview, model: model, setup: setup) }
                        catch { privacy.restorePreview = nil; privacy.error = error.localizedDescription }
                    }
                }
                .navigationTitle("Restore Backup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { privacy.restorePreview = nil } } }
            }
        }
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

#if DEBUG
/// Explicit developer recovery, using the same validated, empty-store-only API as
/// the picker. The UUID identifies one staged local export; no network or raw logs.
@MainActor
enum RoutineBackupRecovery {
    private static var started = false
    static func runIfRequested(model: AppModel, setup: OnboardingPreferences) {
        guard !started, let request = ProcessInfo.processInfo.environment["DAILY_RHYTHM_RESTORE_BACKUP"],
              let id = UUID(uuidString: request) else { return }
        started = true
        let source = URL.documentsDirectory.appendingPathComponent("restore-\(id.uuidString).json")
        let result = URL.documentsDirectory.appendingPathComponent("restore-result-\(id.uuidString).json")
        guard !FileManager.default.fileExists(atPath: result.path) else { return }
        var report: [String: Any] = ["restored": false, "verified": false]
        let reportStore = try? SharedRoutineStore.makeStore()
        do {
            guard let store = reportStore else { throw SharedStoreError.unavailableContainer }
            let backup = try RoutineBackup(jsonExport: Data(contentsOf: source))
            let preview = RoutineRestorePreview(backup: backup, generation: try store.validateAccess())
            try DataPrivacyModel.shared.restore(preview, model: model, setup: setup)
            report["restored"] = true
            report["verified"] = try store.matchesRestoredBackup(backup)
            report["plans"] = backup.planCount
            report["records"] = backup.recordCount
            try FileManager.default.removeItem(at: source)
            report["stagedFileRemoved"] = true
            try store.writeAuxiliaryData(JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), to: result)
        } catch {
            report["error"] = error.localizedDescription
            DataPrivacyModel.shared.error = error.localizedDescription
            if let store = reportStore {
                try? store.writeAuxiliaryData(JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), to: result)
            }
        }
    }
}
#endif

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
