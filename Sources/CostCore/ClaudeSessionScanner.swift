import Foundation

public final class ClaudeSessionScanner {
    private let logs = JSONLLogCache<ScanResult>(agent: "Claude")
    public init() {}
    public func scan(home: URL) throws -> ScanResult {
        let scans = try logs.load(roots: [home.appendingPathComponent("projects")]) { data, _ in
            ClaudeSessionParser.parse(data: data)
        }
        let unique = deduplicateByIdentity(
            scans.flatMap(\.events), conflictIssue: "Conflicting Claude message usage")
        return ScanResult(
            events: unique.events,
            diagnostics: scans.reduce(0) { $0 + $1.diagnostics } + unique.conflicts,
            fileCount: scans.count)
    }
}
