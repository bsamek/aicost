import Foundation

public final class CodexSessionScanner {
    private let logs = JSONLLogCache<CodexSession>(agent: "Codex")
    public init() {}

    public func scan(home: URL) throws -> ScanResult {
        var sessions = try logs.load(
            roots: ["sessions", "archived_sessions"].map { home.appendingPathComponent($0) }
        ) { data, url in CodexSessionParser.parse(data: data, fileID: url.lastPathComponent) }
        // Active and archived copies can have different intermediate snapshots.
        // Merge their raw counters before turning those counters into billable deltas.
        var merged: [String: CodexSession] = [:]
        sessions.sort { ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id) }
        for session in sessions {
            if var existing = merged[session.id] {
                existing.snapshots.append(contentsOf: session.snapshots)
                merged[session.id] = existing
            } else {
                merged[session.id] = session
            }
        }
        // A copied fork may preserve parent snapshots that another copy omitted.
        // Feed those inherited counters back into the ancestor's merged stream,
        // while retaining them in the child stream as its starting baseline.
        for source in Array(merged.values) {
            for snapshot in source.snapshots {
                var owner = source
                var visited: Set<String> = [source.id]
                while let parent = owner.parent, let created = owner.created,
                    snapshot.timestamp < created, visited.insert(parent).inserted
                {
                    var ancestor = merged[parent] ?? CodexSession(id: parent)
                    ancestor.snapshots.append(snapshot)
                    merged[parent] = ancestor
                    owner = ancestor
                }
            }
        }
        var diagnostics = sessions.reduce(0) { $0 + $1.diagnostics }
        let mergedSessions = merged.values.sorted {
            ($0.created ?? .distantPast, $0.id) < ($1.created ?? .distantPast, $1.id)
        }
        var parents: [String: String] = [:]
        for session in mergedSessions {
            if let parent = session.parent, parent != session.id { parents[session.id] = parent }
        }
        func lineageRoot(_ id: String) -> String {
            var root = id
            var visited: Set<String> = [id]
            while let next = parents[root], !visited.contains(next) {
                visited.insert(next)
                root = next
            }
            return root
        }
        var seen: Set<String> = []
        var events: [UsageEvent] = []
        // Prefer original parent records to inherited copies for model attribution.
        for session in mergedSessions {
            let root = lineageRoot(session.id)
            for event in CodexSessionParser.normalize(session, diagnostics: &diagnostics)
            where seen.insert(root + "|" + event.identity).inserted { events.append(event) }
        }
        events.sort {
            ($0.timestamp, $0.sessionID, $0.identity) < ($1.timestamp, $1.sessionID, $1.identity)
        }
        return ScanResult(
            events: events,
            diagnostics: diagnostics,
            fileCount: sessions.count)
    }
}
