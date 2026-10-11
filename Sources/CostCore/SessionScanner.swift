import Foundation
import Darwin

public final class SessionScanner {
    private struct Cached {
        let size: UInt64
        let modified: Date
        let inode: UInt64
        let session: ParsedSession
    }
    private var cache: [URL: Cached] = [:]
    public init() {}

    public func scan(home: URL) throws -> ScanResult {
        let manager = FileManager.default
        var files: [URL] = []
        for name in ["sessions", "archived_sessions"] {
            let root = home.appendingPathComponent(name)
            var metadata = stat()
            if Darwin.fstatat(AT_FDCWD, root.path, &metadata, 0) != 0 {
                let errorCode = errno
                if errorCode == ENOENT { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errorCode), userInfo: [NSFilePathErrorKey: root.path])
            }
            guard metadata.st_mode & S_IFMT == S_IFDIR else { throw ScanError.unreadable(root.path) }
            var enumerationError: Error?
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { _, error in
                enumerationError = error; return false
            }) else { throw ScanError.unreadable(root.path) }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                if values.isRegularFile == true && url.pathExtension == "jsonl" { files.append(url) }
            }
            if let enumerationError { throw enumerationError }
        }
        let existing = Set(files)
        cache = cache.filter { existing.contains($0.key) }
        var sessions: [ParsedSession] = []
        for url in files.sorted(by: { $0.path < $1.path }) {
            let attributes = try manager.attributesOfItem(atPath: url.path)
            guard manager.isReadableFile(atPath: url.path) else { throw ScanError.unreadable(url.path) }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            if let cached = cache[url], cached.size == size, cached.modified == modified, cached.inode == inode {
                sessions.append(cached.session)
            } else {
                let session = try autoreleasepool { SessionParser.parse(data: try Data(contentsOf: url), fileID: url.lastPathComponent) }
                cache[url] = Cached(size: size, modified: modified, inode: inode, session: session)
                sessions.append(session)
            }
        }
        // Active and archived copies can have different intermediate snapshots.
        // Merge their raw counters before turning those counters into billable deltas.
        var merged: [String: ParsedSession] = [:]
        sessions.sort { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }
        for session in sessions {
            if var existing = merged[session.id] {
                existing.snapshots.append(contentsOf: session.snapshots)
                merged[session.id] = existing
            } else { merged[session.id] = session }
        }
        // A copied fork may preserve parent snapshots that another copy omitted.
        // Feed those inherited counters back into the ancestor's merged stream,
        // while retaining them in the child stream as its starting baseline.
        for source in Array(merged.values) {
            for snapshot in source.snapshots {
                var owner = source
                var visited: Set<String> = [source.id]
                while let parent = owner.parent, let created = owner.created,
                      snapshot.timestamp < created, visited.insert(parent).inserted {
                    var ancestor = merged[parent] ?? ParsedSession(id: parent, parent: nil, created: nil, events: [], diagnostics: 0)
                    ancestor.snapshots.append(snapshot)
                    merged[parent] = ancestor
                    owner = ancestor
                }
            }
        }
        var normalizationDiagnostics = 0
        let mergedSessions = merged.values.sorted { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }
        var parents: [String: String] = [:]
        for session in mergedSessions { if let parent = session.parent, parent != session.id { parents[session.id] = parent } }
        func lineageRoot(_ id: String) -> String {
            var root = id; var visited: Set<String> = [id]
            while let next = parents[root], !visited.contains(next) { visited.insert(next); root = next }
            return root
        }
        var seen: Set<String> = []
        var events: [UsageEvent] = []
        // Prefer original parent records to inherited copies for model attribution.
        for session in mergedSessions {
            let root = lineageRoot(session.id)
            for event in SessionParser.normalize(session, diagnostics: &normalizationDiagnostics) where seen.insert(root + "|" + event.identity).inserted { events.append(event) }
        }
        events.sort { ($0.timestamp, $0.sessionID, $0.identity) < ($1.timestamp, $1.sessionID, $1.identity) }
        return ScanResult(events: events, diagnostics: max(normalizationDiagnostics, sessions.reduce(0) { $0 + $1.diagnostics }), fileCount: files.count)
    }
}
public enum ScanError: LocalizedError {
    case unreadable(String)
    public var errorDescription: String? {
        switch self { case .unreadable(let path): "Cannot read Codex log: \(path)" }
    }
}
