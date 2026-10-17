@testable import CostCore

// Read-only views for assertions; production code switches on `usage` directly.
extension UsageEvent {
    var codexUsage: TokenUsage? {
        if case .codex(let usage) = usage { usage } else { nil }
    }
    var claudeUsage: ClaudeTokenUsage? {
        if case .claude(let usage) = usage { usage } else { nil }
    }
    var piUsage: PiTokenUsage? {
        if case .pi(let usage, _) = usage { usage } else { nil }
    }
    var openCodeUsage: OpenCodeTokenUsage? {
        if case .openCode(let usage, _) = usage { usage } else { nil }
    }
}
