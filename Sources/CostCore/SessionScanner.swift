import Foundation

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
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            guard isDirectory.boolValue else { throw ScanError.unreadable(root.path) }
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
        var parents: [String: String] = [:]
        for session in sessions { if let parent = session.parent, parent != session.id { parents[session.id] = parent } }
        func lineageRoot(_ id: String) -> String {
            var root = id; var visited: Set<String> = [id]
            while let next = parents[root], !visited.contains(next) { visited.insert(next); root = next }
            return root
        }
        var seen: Set<String> = []
        var events: [UsageEvent] = []
        // Prefer original parent records to inherited copies for model attribution.
        sessions.sort { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }
        for session in sessions {
            let root = lineageRoot(session.id)
            for event in session.events where seen.insert(root + "|" + event.identity).inserted { events.append(event) }
        }
        events.sort { ($0.timestamp, $0.sessionID, $0.identity) < ($1.timestamp, $1.sessionID, $1.identity) }
        return ScanResult(events: events, diagnostics: sessions.reduce(0) { $0 + $1.diagnostics }, fileCount: files.count)
    }
}
public enum ScanError: LocalizedError {
    case unreadable(String)
    public var errorDescription: String? {
        switch self { case .unreadable(let path): "Cannot read Codex log: \(path)" }
    }
}
