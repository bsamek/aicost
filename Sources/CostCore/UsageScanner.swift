import Foundation

/// Both the panel and report use this aggregation path.
public final class UsageScanner {
    private let codex = SessionScanner()
    private let claude = ClaudeSessionScanner()
    private let pi = PiSessionScanner()
    private let openCode = OpenCodeSessionScanner()
    public init() {}
    public func scan(codexHome: URL, claudeHome: URL?, piHome: URL? = nil, openCodeHome: URL? = nil) throws -> ScanResult {
        let first = try codex.scan(home: codexHome)
        var result = first
        if let claudeHome {
            let scan = try claude.scan(home: claudeHome)
            result.events += scan.events; result.diagnostics += scan.diagnostics; result.fileCount += scan.fileCount
        }
        if let piHome {
            let scan = try pi.scan(home: piHome)
            result.events += scan.events; result.diagnostics += scan.diagnostics; result.fileCount += scan.fileCount
        }
        if let openCodeHome {
            let scan = try openCode.scan(home: openCodeHome)
            result = ScanResult(events: result.events + scan.events, diagnostics: result.diagnostics + scan.diagnostics,
                                fileCount: result.fileCount + scan.fileCount)
        }
        return result
    }
}
