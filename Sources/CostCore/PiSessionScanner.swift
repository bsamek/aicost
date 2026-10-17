import Foundation

public final class PiSessionScanner {
    private let logs = JSONLLogCache<ScanResult>(agent: "Pi")
    public init() {}
    public func scan(home: URL) throws -> ScanResult {
        let scans = try logs.load(roots: [home.appendingPathComponent("sessions")]) { data, _ in
            PiSessionParser.parse(data: data)
        }
        let unique = deduplicateByIdentity(
            scans.flatMap(\.events), conflictIssue: "Conflicting Pi message usage")
        return ScanResult(
            events: unique.events,
            diagnostics: scans.reduce(0) { $0 + $1.diagnostics } + unique.conflicts,
            fileCount: scans.count)
    }
}
