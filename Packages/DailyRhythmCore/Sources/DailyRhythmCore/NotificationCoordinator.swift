import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A separate advisory lock serializes OS queue updates and preference changes
/// across app/extension processes. It is never held while requesting permission.
public final class RhythmNotificationCoordinator: Sendable {
    private let preferencesURL: URL
    private let client: any RhythmNotificationClient
    private let now: @Sendable () -> Date
    private let plan: @Sendable (RhythmNotificationPreferences, Date) throws -> [RhythmNotificationRequest]
    private let validateAccess: @Sendable () throws -> Void

    public init(preferencesURL: URL, client: any RhythmNotificationClient,
                now: @escaping @Sendable () -> Date = { Date() },
                validateAccess: @escaping @Sendable () throws -> Void = {},
                plan: @escaping @Sendable (RhythmNotificationPreferences, Date) throws -> [RhythmNotificationRequest]) {
        self.preferencesURL = preferencesURL
        self.client = client
        self.now = now
        self.plan = plan
        self.validateAccess = validateAccess
    }

    public func preferences() throws -> RhythmNotificationPreferences {
        guard FileManager.default.fileExists(atPath: preferencesURL.path) else { return .init() }
        let bytes = try Data(contentsOf: preferencesURL)
        guard let dictionary = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              Set(dictionary.keys) == Set(["version", "timedSteps", "dailyClose", "closeHour", "closeMinute"]) else {
            throw RhythmNotificationError.invalidPreferences
        }
        let preferences = try JSONDecoder().decode(RhythmNotificationPreferences.self, from: bytes)
        try preferences.validate()
        return preferences
    }

    public func reconcile() async throws -> RhythmNotificationStatus { try await run(change: nil) }
    public func update(_ change: RhythmNotificationPreferenceChange) async throws -> RhythmNotificationStatus {
        try await run(change: change)
    }

    /// The caller has already persisted the store's erase barrier. Use this same
    /// queue lock so any earlier add finishes before cancellation, then discard preferences.
    public func erasePreferences() async throws {
        let descriptor = try await acquireLock()
        defer { _ = flock(descriptor, LOCK_UN); close(descriptor) }
        await client.removePending(await client.pending().map(\.id).filter { $0.hasPrefix(RhythmNotificationRequest.prefix) })
        await client.removeDelivered(await client.deliveredIDs().filter { $0.hasPrefix(RhythmNotificationRequest.prefix) })
        let pending = await client.pending()
        let delivered = await client.deliveredIDs()
        guard !pending.contains(where: { $0.id.hasPrefix(RhythmNotificationRequest.prefix) }),
              !delivered.contains(where: { $0.hasPrefix(RhythmNotificationRequest.prefix) }) else {
            throw RhythmNotificationError.cancellationIncomplete
        }
        try LocalDataFiles.removeIfPresent(preferencesURL)
    }

    private func run(change: RhythmNotificationPreferenceChange?) async throws -> RhythmNotificationStatus {
        let descriptor = try await acquireLock()
        defer { _ = flock(descriptor, LOCK_UN); close(descriptor) }
        do {
            try validateAccess()
            var preferences = try preferences()
            if let change {
                change.apply(to: &preferences)
                try preferences.validate()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let bytes = try encoder.encode(preferences)
                #if os(iOS)
                try bytes.write(to: preferencesURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try bytes.write(to: preferencesURL, options: .atomic)
                #endif
            }
            let authorization = await client.authorization()
            let desired = authorization == .authorized && (preferences.timedSteps || preferences.dailyClose)
                ? try plan(preferences, now()) : []
            let byID = Dictionary(uniqueKeysWithValues: desired.map { ($0.id, $0) })
            let pending = await client.pending()
            let owned = pending.filter { $0.id.hasPrefix(RhythmNotificationRequest.prefix) }
            let obsolete = owned.filter { $0.request == nil || $0.request != byID[$0.id] }.map(\.id)
            await client.removePending(obsolete)
            // Clear our delivered notices at each reconciliation opportunity. A tap
            // already in flight keeps its exact destination, and still does no write.
            await client.removeDelivered(await client.deliveredIDs().filter { $0.hasPrefix(RhythmNotificationRequest.prefix) })
            let unchanged = Set(owned.filter { $0.request != nil && $0.request == byID[$0.id] }.map(\.id))
            for request in desired where !unchanged.contains(request.id) && request.fireDate > now() {
                try await client.add(request)
            }
            return RhythmNotificationStatus(preferences: preferences, authorization: authorization,
                pendingCount: await client.pending().filter { $0.id.hasPrefix(RhythmNotificationRequest.prefix) }.count)
        } catch LocalDataError.staleAction {
            // A previous generation has no authority over the new generation's queue.
            // Its own requests were already drained by the completed erase.
            throw LocalDataError.staleAction
        } catch {
            // A partial schedule or an unreadable plan is not a trustworthy queue.
            // Keep data/preferences intact, clear only our requests, and surface failure.
            await client.removePending(await client.pending().map(\.id).filter { $0.hasPrefix(RhythmNotificationRequest.prefix) })
            await client.removeDelivered(await client.deliveredIDs().filter { $0.hasPrefix(RhythmNotificationRequest.prefix) })
            throw error
        }
    }

    private func acquireLock() async throws -> Int32 {
        guard preferencesURL.isFileURL else { throw RhythmNotificationError.invalidPreferences }
        let directory = preferencesURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = preferencesURL.appendingPathExtension("lock")
        let descriptor = lockURL.path.withCString { open($0, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600)) }
        guard descriptor >= 0 else { throw RhythmNotificationError.busy }
        do {
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                 ofItemAtPath: lockURL.path)
            #endif
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
                guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR,
                      ContinuousClock.now < deadline else { throw RhythmNotificationError.busy }
                try await Task.sleep(for: .milliseconds(25))
            }
            return descriptor
        } catch { close(descriptor); throw error }
    }
}
