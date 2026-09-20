import Foundation

/// The non-personal generation survives erasure so old drafts cannot become current again.
public struct RoutineDataLifecycle: Codable, Equatable, Sendable {
    public static let initialGeneration = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public var version = 1
    public var generation = initialGeneration
    public var erasurePending = false

    static func read(from url: URL) throws -> Self {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return .init() }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["version", "generation", "erasurePending"]) else {
            throw LocalDataError.invalidLifecycle
        }
        let state = try JSONDecoder().decode(Self.self, from: data)
        guard state.version == 1 else { throw LocalDataError.invalidLifecycle }
        return state
    }

    func write(to url: URL) throws {
        try LocalDataFiles.write(JSONEncoder().encode(self), to: url)
    }
}

public enum LocalDataError: Error, LocalizedError, Equatable {
    case staleAction, erasurePending, invalidLifecycle
    public var errorDescription: String? {
        switch self {
        case .staleAction: "Local data changed after this action was prepared. Open Daily Rhythm and start again."
        case .erasurePending: "Local data erase is unfinished. Open Habits → Data & Privacy to finish it."
        case .invalidLifecycle: "The local data recovery marker could not be read. Existing files have been kept."
        }
    }
}

enum LocalDataFiles {
    static func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    static func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
    }
}

public enum RoutineExportFormat: String, CaseIterable, Sendable { case json, csv }

struct RoutineJSONExport: Encodable {
    let format = "daily-rhythm-export"
    let exportVersion = 1
    let exportedAt: String
    let dateEncoding = "Data dates are seconds since 2001-01-01T00:00:00Z (Foundation reference date), preserving stored precision."
    let data: StoreDocument
}

enum RoutineDataExport {
    static func encode(_ state: StoreDocument, format: RoutineExportFormat, at date: Date) throws -> Data {
        if format == .json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .deferredToDate
            return try encoder.encode(RoutineJSONExport(exportedAt: timestamp(date), data: state))
        }
        let habits = Dictionary(uniqueKeysWithValues: state.habits.map { ($0.id, $0) })
        var rows = [["occurrence_id", "habit_id", "planned_day", "title", "normal_target", "light_target",
                     "outcome", "due_day", "due_at_utc", "due_timezone", "duration_minutes",
                     "completed_at_utc", "skipped_at_utc", "deferred_until_utc", "completion_source", "archived_at_utc"]]
        for record in state.records.sorted(by: { $0.dayKey == $1.dayKey ? $0.id < $1.id : $0.dayKey < $1.dayKey }) {
            let zone: String
            if case .timed(_, let value) = record.due { zone = value } else { zone = "" }
            rows.append([record.id, record.habitID.uuidString, record.dayKey, record.title,
                         record.normalTarget, record.lightTarget ?? "", record.outcome?.rawValue ?? "pending",
                         record.due.dayKey(), record.due.instant.map(timestamp) ?? "", zone,
                         record.durationMinutes.map(String.init) ?? "", record.completedAt.map(timestamp) ?? "",
                         record.skippedAt.map(timestamp) ?? "", record.deferredUntil.map(timestamp) ?? "",
                         record.completionSource?.rawValue ?? "", habits[record.habitID]?.archivedAt.map(timestamp) ?? ""])
        }
        return Data((rows.map { $0.map(csvCell).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func csvCell(_ text: String) -> String {
        // Quotes preserve CSV structure; the apostrophe also prevents spreadsheet formulas.
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first
        let safe = first.map { "=+-@".contains($0) } == true || text.first == "\t" || text.first == "\r"
            ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
