import Foundation

/// Both the panel and report use this aggregation path.
public final class UsageScanner {
    private let codex = CodexSessionScanner()
    private let claude = ClaudeSessionScanner()
    private let pi = PiSessionScanner()
    private let openCode = OpenCodeSessionScanner()
    public init() {}
    public func scan(_ sources: UsageSources) throws -> ScanResult {
        var result = ScanResult(events: [], diagnostics: 0, fileCount: 0)
        if let home = sources.codex { result.append(try codex.scan(home: home)) }
        if let home = sources.claude { result.append(try claude.scan(home: home)) }
        if let home = sources.pi { result.append(try pi.scan(home: home)) }
        if let home = sources.openCode { result.append(try openCode.scan(home: home)) }
        return result
    }
}
