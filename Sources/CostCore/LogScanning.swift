import Darwin
import Foundation

/// Identifies an unchanged file between scans without reading it.
struct FileStamp: Equatable {
    let size: UInt64
    let modified: Date
    let inode: UInt64

    init(_ attributes: [FileAttributeKey: Any]) {
        size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        modified = attributes[.modificationDate] as? Date ?? .distantPast
        inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
    }
}

/// Finds `.jsonl` logs below an agent's directories and reparses only files that changed.
/// Hidden files and symbolic links are skipped. Missing roots are empty; other failures throw.
final class JSONLLogCache<Parsed> {
    private var entries: [URL: (stamp: FileStamp, parsed: Parsed)] = [:]
    private let agent: String
    private let manager = FileManager.default

    init(agent: String) { self.agent = agent }

    /// Parsed files in path order.
    func load(roots: [URL], parse: (Data, URL) throws -> Parsed) throws -> [Parsed] {
        let files = try roots.flatMap(findLogs).sorted { $0.path < $1.path }
        let existing = Set(files)
        entries = entries.filter { existing.contains($0.key) }
        return try files.map { url in
            let attributes = try manager.attributesOfItem(atPath: url.path)
            guard manager.isReadableFile(atPath: url.path) else {
                throw LogScanError.unreadable(agent: agent, path: url.path)
            }
            let stamp = FileStamp(attributes)
            if let entry = entries[url], entry.stamp == stamp { return entry.parsed }
            let parsed = try autoreleasepool { try parse(try Data(contentsOf: url), url) }
            entries[url] = (stamp, parsed)
            return parsed
        }
    }

    private func findLogs(in root: URL) throws -> [URL] {
        var metadata = stat()
        if Darwin.fstatat(AT_FDCWD, root.path, &metadata, 0) != 0 {
            let errorCode = errno
            if errorCode == ENOENT { return [] }
            throw NSError(
                domain: NSPOSIXErrorDomain, code: Int(errorCode),
                userInfo: [NSFilePathErrorKey: root.path])
        }
        guard metadata.st_mode & S_IFMT == S_IFDIR else {
            throw LogScanError.unreadable(agent: agent, path: root.path)
        }
        var enumerationError: Error?
        guard
            let enumerator = manager.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles],
                errorHandler: { _, error in
                    enumerationError = error
                    return false
                })
        else { throw LogScanError.unreadable(agent: agent, path: root.path) }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true && url.pathExtension == "jsonl" { files.append(url) }
        }
        if let enumerationError { throw enumerationError }
        return files
    }
}

/// Copied history repeats a request under the same identity. Keep one event per identity,
/// dated at the earliest copy, and leave copies whose usage, model, or request ID disagree
/// unpriced with `conflictIssue`.
func deduplicateByIdentity(_ events: [UsageEvent], conflictIssue: String) -> (
    events: [UsageEvent], conflicts: Int
) {
    var unique: [String: UsageEvent] = [:]
    var conflicts = 0
    for event in events {
        guard var original = unique[event.identity] else {
            unique[event.identity] = event
            continue
        }
        let requestConflict =
            original.requestID != nil && event.requestID != nil
            && original.requestID != event.requestID
        if original.usage != event.usage || original.model != event.model || requestConflict {
            original.issue = conflictIssue
            conflicts += 1
        }
        // Inherited copies may receive a new transcript timestamp. Retain the original billing date.
        original.timestamp = min(original.timestamp, event.timestamp)
        if original.requestID == nil { original.requestID = event.requestID }
        unique[event.identity] = original
    }
    let sorted = unique.values.sorted { ($0.timestamp, $0.identity) < ($1.timestamp, $1.identity) }
    return (sorted, conflicts)
}

public enum LogScanError: LocalizedError {
    case unreadable(agent: String, path: String)
    public var errorDescription: String? {
        switch self {
        case .unreadable(let agent, let path): "Cannot read \(agent) log: \(path)"
        }
    }
}
