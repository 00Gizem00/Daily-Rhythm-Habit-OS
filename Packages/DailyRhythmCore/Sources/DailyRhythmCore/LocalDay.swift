import Foundation

public struct LocalDay: Sendable {
    public let calendar: Calendar

    public static let utc: LocalDay = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return LocalDay(calendar: calendar)
    }()

    public init(calendar: Calendar) {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = gregorian
    }

    public func key(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    /// Noon avoids midnight transitions in timezones that change DST at midnight.
    public func date(for key: String) -> Date? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              self.key(for: date) == key else { return nil }
        return date
    }

    func weekday(for key: String) -> Int? {
        date(for: key).map { calendar.component(.weekday, from: $0) }
    }

    func keys(days: Int, endingOn date: Date) throws -> [String] {
        guard (1...366).contains(days) else { throw RoutineStoreError.invalidHistoryRange }
        let finalDay = calendar.startOfDay(for: date)
        return try (0..<days).reversed().map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: finalDay) else {
                throw RoutineStoreError.invalidHistoryRange
            }
            return key(for: day)
        }
    }
}
