import Foundation

public struct RhythmNotificationPreferences: Codable, Equatable, Sendable {
    public var version = 1
    public var timedSteps = false
    public var dailyClose = false
    public var closeHour = 20
    public var closeMinute = 30

    public init() {}
    public func validate() throws {
        guard version == 1, (0...23).contains(closeHour), (0...59).contains(closeMinute) else {
            throw RhythmNotificationError.invalidPreferences
        }
    }
}

public enum RhythmNotificationPreferenceChange: Sendable {
    case timedSteps(Bool), dailyClose(Bool), closeTime(hour: Int, minute: Int)

    func apply(to preferences: inout RhythmNotificationPreferences) {
        switch self {
        case .timedSteps(let enabled): preferences.timedSteps = enabled
        case .dailyClose(let enabled): preferences.dailyClose = enabled
        case .closeTime(let hour, let minute): preferences.closeHour = hour; preferences.closeMinute = minute
        }
    }
}

/// Notification routes never perform a mutation or resolve a replacement occurrence.
public enum RhythmNotificationDestination: Codable, Hashable, Sendable {
    case occurrence(String)
    case day(String)

    public var url: URL {
        var components = URLComponents()
        components.scheme = "daily-rhythm"
        switch self {
        case .occurrence(let id):
            components.host = "step"
            components.queryItems = [URLQueryItem(name: "id", value: id)]
        case .day(let key):
            components.host = "review"
            components.queryItems = [URLQueryItem(name: "day", value: key)]
        }
        return components.url!
    }

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "daily-rhythm", parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let query = parts.queryItems, query.count == 1, let value = query[0].value else { return nil }
        switch (parts.host, query[0].name) {
        case ("step", "id"):
            let pieces = value.split(separator: "|", omittingEmptySubsequences: false)
            guard pieces.count == 2, let uuid = UUID(uuidString: String(pieces[0])),
                  uuid.uuidString == pieces[0], LocalDay.utc.date(for: String(pieces[1])) != nil else { return nil }
            self = .occurrence(value)
        case ("review", "day"):
            guard LocalDay.utc.date(for: value) != nil else { return nil }
            self = .day(value)
        default: return nil
        }
    }
}

public struct RhythmNotificationRequest: Equatable, Sendable, Identifiable {
    public static let prefix = "daily-rhythm.notification."
    public let id: String
    public let fireDate: Date
    public let title: String
    public let body: String
    public let destination: RhythmNotificationDestination

    public init(id: String, fireDate: Date, title: String, body: String,
                destination: RhythmNotificationDestination) {
        self.id = id
        self.fireDate = fireDate
        self.title = title
        self.body = body
        self.destination = destination
    }
}

public enum RhythmNotificationAuthorization: Sendable {
    case notDetermined, denied, authorized
}

public struct RhythmPendingNotification: Sendable {
    public let id: String
    public let request: RhythmNotificationRequest?
    public init(id: String, request: RhythmNotificationRequest?) { self.id = id; self.request = request }
}

public protocol RhythmNotificationClient: Sendable {
    func authorization() async -> RhythmNotificationAuthorization
    func pending() async -> [RhythmPendingNotification]
    func deliveredIDs() async -> [String]
    func removePending(_ identifiers: [String]) async
    func removeDelivered(_ identifiers: [String]) async
    func add(_ request: RhythmNotificationRequest) async throws
}

public struct RhythmNotificationStatus: Sendable {
    public let preferences: RhythmNotificationPreferences
    public let authorization: RhythmNotificationAuthorization
    public let pendingCount: Int
}

public enum RhythmNotificationError: Error, LocalizedError {
    case invalidPreferences, busy
    public var errorDescription: String? {
        switch self {
        case .invalidPreferences: "Notification preferences could not be read. Your habit data has been kept."
        case .busy: "Notifications are being updated by another action. Try again shortly."
        }
    }
}
