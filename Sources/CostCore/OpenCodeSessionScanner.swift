import Foundation
import SQLite3

public final class OpenCodeSessionScanner {
    private let manager: FileManager
    public init(fileManager: FileManager = .default) { manager = fileManager }
    public func scan(home: URL) throws -> ScanResult {
        let source = home.appendingPathComponent("opencode.db")
        // Inspect only the usage database; never read auth/configuration files.
        do { _ = try manager.attributesOfItem(atPath: source.path) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return ScanResult(events: [], diagnostics: 0, fileCount: 0)
        }
        let snapshot = manager.temporaryDirectory.appendingPathComponent("aicost-opencode-\(UUID().uuidString)")
        try manager.createDirectory(at: snapshot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: snapshot) }
        let database = snapshot.appendingPathComponent("opencode.db")
        // Opening a live WAL database can create/write its SHM sidecar, even in
        // SQLite read-only mode. Copy a stable DB + committed WAL to private temp
        // storage first. Never use immutable=1 (which would ignore live WAL).
        var stable = false
        for _ in 0..<3 {
            let before = try stamps(source)
            for suffix in ["", "-wal"] {
                let target = URL(fileURLWithPath: database.path + suffix)
                if manager.fileExists(atPath: target.path) { try manager.removeItem(at: target) }
                if before[suffix] != nil {
                    try manager.copyItem(at: URL(fileURLWithPath: source.path + suffix), to: target)
                    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                }
            }
            if before == (try stamps(source)) { stable = true; break }
        }
        guard stable else { throw OpenCodeScanError.changingDatabase }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(database.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let db = handle else {
            if let handle { sqlite3_close(handle) }
            throw OpenCodeScanError.unreadable
        }
        defer { sqlite3_close(db) }
        try execute(db, "BEGIN")
        defer { try? execute(db, "ROLLBACK") }
        let tables = Set(try rows(db, "SELECT name FROM sqlite_master WHERE type='table'").map { $0[0] })
        guard tables.contains("message") || tables.contains("session_message") else { throw OpenCodeScanError.unsupportedSchema }
        var sessions: [String: Int64] = [:]
        for table in ["session", "session_v2"] where tables.contains(table) {
            for row in try rows(db, "SELECT id,time_created FROM \(table)") {
                if let created = Int64(row[1]) { sessions[row[0]] = min(sessions[row[0]] ?? created, created) }
            }
        }
        var records: [String: OpenCodeRecord] = [:]
        var modernIDs: Set<String> = []
        var diagnostics = 0
        // Prefer the modern projection, including invalid/incomplete modern rows,
        // over their old migration source. Do not resurrect stale legacy counters.
        for modern in [true, false] {
            let table = modern ? "session_message" : "message"
            guard tables.contains(table) else { continue }
            let filter = modern ? "type='assistant' OR (type='compaction' AND json_valid(data) AND json_extract(data,'$.status')='completed')" : "NOT json_valid(data) OR json_extract(data,'$.role')='assistant'"
            // Fetch metadata only, excluding conversation content and tool parts.
            let fields = ["role", "model", "providerID", "modelID", "tokens", "time", "status"].map {
                "'\($0)',json_extract(data,'$.\($0)')"
            }.joined(separator: ",")
            let typeField = modern ? "'type',type," : ""
            let sql = "SELECT id,session_id,CASE WHEN json_valid(data) THEN json_object(\(typeField)\(fields)) ELSE '{}' END FROM \(table) WHERE \(filter) ORDER BY id,session_id"
            for row in try rows(db, sql) {
                if !modern && modernIDs.contains(row[0]) { continue }
                if modern { modernIDs.insert(row[0]) }
                let parsed = OpenCodeSessionParser.record(data: Data(row[2].utf8), id: row[0], sessionID: row[1], modern: modern)
                diagnostics += parsed.diagnostics
                guard let record = parsed.record else { continue }
                if var original = records[row[0]] {
                    if original.event.openCodeUsage != record.event.openCodeUsage || original.event.model != record.event.model || original.event.openCodeProvider != record.event.openCodeProvider || original.created != record.created || original.completed != record.completed {
                        original.event.issue = "Conflicting OpenCode message usage"; diagnostics += 1
                    }
                    original.event.timestamp = min(original.event.timestamp, record.event.timestamp)
                    records[row[0]] = original
                } else { records[row[0]] = record }
            }
        }
        let sorted = records.values.sorted { ($0.created, $0.event.identity) < ($1.created, $1.event.identity) }
        var originals: [String: OpenCodeRecord] = [:]
        var events: [UsageEvent] = []
        // V1 forks generate new IDs but preserve the entire original time span.
        // Only a record predating its own session is an inherited candidate.
        // Unrelated calls with identical counters/timestamps remain separate.
        for record in sorted where sessions[record.event.sessionID].map({ $0 > record.completed }) != true {
            originals[record.copyKey] = record; events.append(record.event)
        }
        var inherited: [String: OpenCodeRecord] = [:]
        for record in sorted where sessions[record.event.sessionID].map({ $0 > record.completed }) == true {
            if let original = originals[record.copyKey], original.event.sessionID != record.event.sessionID { continue }
            if let original = inherited[record.copyKey], original.event.sessionID != record.event.sessionID { continue }
            inherited[record.copyKey] = record; events.append(record.event)
        }
        return ScanResult(events: events.sorted { ($0.timestamp, $0.identity) < ($1.timestamp, $1.identity) }, diagnostics: diagnostics, fileCount: 1)
    }

    private struct Stamp: Equatable { let size: UInt64; let modified: Date; let inode: UInt64 }
    private func stamps(_ source: URL) throws -> [String: Stamp] {
        var result: [String: Stamp] = [:]
        for suffix in ["", "-wal"] {
            do {
                let attributes = try manager.attributesOfItem(atPath: source.path + suffix)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      manager.isReadableFile(atPath: source.path + suffix) else { throw OpenCodeScanError.unreadable }
                result[suffix] = Stamp(size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                                      modified: attributes[.modificationDate] as? Date ?? .distantPast,
                                      inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0)
            } catch let error as NSError where suffix != "" && error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { continue }
        }
        return result
    }
    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw OpenCodeScanError.unreadable }
    }
    private func rows(_ db: OpaquePointer, _ sql: String) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw OpenCodeScanError.unsupportedSchema }
        defer { sqlite3_finalize(statement) }
        var result: [[String]] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw OpenCodeScanError.unreadable }
            var row: [String] = []
            for index in 0..<sqlite3_column_count(statement) {
                row.append(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "")
            }
            result.append(row)
        }
    }
}
public enum OpenCodeScanError: LocalizedError, Equatable {
    case unreadable, unsupportedSchema, changingDatabase
    public var errorDescription: String? {
        switch self {
        case .unreadable: "Cannot read OpenCode usage database."
        case .unsupportedSchema: "OpenCode usage database schema is unsupported."
        case .changingDatabase: "OpenCode usage database changed during the scan. Try refreshing again."
        }
    }
}
