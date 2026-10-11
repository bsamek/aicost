import Foundation

/// Both the panel and report use this aggregation path.
public final class UsageScanner {
    private let codex = SessionScanner()
    private let claude = ClaudeSessionScanner()
    public init() {}
    public func scan(codexHome: URL, claudeHome: URL?) throws -> ScanResult {
        let first = try codex.scan(home: codexHome)
        guard let claudeHome else { return first }
        let second = try claude.scan(home: claudeHome)
        return ScanResult(events: first.events + second.events, diagnostics: first.diagnostics + second.diagnostics,
                          fileCount: first.fileCount + second.fileCount)
    }
}
