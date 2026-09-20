import Foundation

/// A future StoreKit adapter must return Pro only from verified entitlement state.
/// Entitlements are not stored in the habit document or controlled by a user toggle.
public enum HabitEntitlement: Equatable, Sendable {
    case free, pro
}

public protocol HabitEntitlementProvider: Sendable {
    /// Read a current, locally available snapshot. Called inside the store lock for
    /// each activation, so implementations must be quick and must not reenter the store.
    /// Unknown, expired or unverified access should resolve to Free.
    func currentEntitlement() -> HabitEntitlement
}

/// The only production provider until verified StoreKit integration is available.
public struct FreeHabitEntitlementProvider: HabitEntitlementProvider {
    public init() {}
    public func currentEntitlement() -> HabitEntitlement { .free }
}

/// Shared policy for individual creation, routine/proposal batches and restoration.
/// Reads and changes to existing habits/occurrences do not require an entitlement.
public enum HabitActivationPolicy {
    public static let freeActiveHabitLimit = 3
    public static let freePlanDescription =
        "Free includes up to \(freeActiveHabitLimit) active recurring habits. Archive a habit to make room; its history stays available."
    public static let limitMessage =
        "Free allows up to \(freeActiveHabitLimit) active recurring habits. Archive a habit before adding or restoring more. One-off tasks do not count toward this limit."

    static func validate(activeCount: Int, activatingCount: Int, entitlement: HabitEntitlement) throws {
        // One-offs remain available even after a downgrade leaves the store over capacity.
        guard activatingCount > 0, entitlement == .free else { return }
        guard activeCount <= freeActiveHabitLimit,
              activatingCount <= freeActiveHabitLimit - activeCount else {
            throw RoutineStoreError.activeHabitLimitReached
        }
    }
}

extension Recurrence {
    public var isRecurring: Bool {
        if case .weekly = self { return true }
        return false
    }
}
