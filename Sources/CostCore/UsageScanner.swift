import Foundation

/// Both the panel and report use this aggregation path.
public final class UsageScanner {
    private let codex = SessionScanner()
    private let claude = ClaudeSessionScanner()
    private let openCode = OpenCodeSessionScanner()
    public init() {}
    public func scan(codexHome: URL, claudeHome: URL?, openCodeHome: URL? = nil) throws -> ScanResult {
        var scans = [try codex.scan(home: codexHome)]
        if let claudeHome { scans.append(try claude.scan(home: claudeHome)) }
        if let openCodeHome { scans.append(try openCode.scan(home: openCodeHome)) }
        return ScanResult(events: scans.flatMap(\.events), diagnostics: scans.reduce(0) { $0 + $1.diagnostics },
                          fileCount: scans.reduce(0) { $0 + $1.fileCount })
    }
}
