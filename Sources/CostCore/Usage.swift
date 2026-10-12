import Foundation
import CoreFoundation

public struct TokenUsage: Equatable, Sendable {
    public var input: Int64
    public var cached: Int64
    public var writes: Int64
    public var output: Int64
    public var reasoning: Int64

    public init(input: Int64, cached: Int64 = 0, writes: Int64 = 0, output: Int64 = 0, reasoning: Int64 = 0) {
        self.input = input; self.cached = cached; self.writes = writes
        self.output = output; self.reasoning = reasoning
    }
    static let zero = TokenUsage(input: 0)
    var isValid: Bool {
        input >= 0 && cached >= 0 && writes >= 0 && output >= 0 && reasoning >= 0 && cached <= input && reasoning <= output
    }
    var hasTokens: Bool { input > 0 || output > 0 || writes > 0 }
    var fingerprint: String { "\(input),\(cached),\(writes),\(output),\(reasoning)" }

    init?(_ dictionary: [String: Any]) {
        func count(_ key: String, required: Bool = false) -> Int64? {
            guard let value = dictionary[key] else { return required ? nil : 0 }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int64(number.stringValue)
        }
        guard let input = count("input_tokens", required: true), let cached = count("cached_input_tokens"),
              let writes = count("cache_write_input_tokens"), let output = count("output_tokens", required: true),
              let reasoning = count("reasoning_output_tokens") else { return nil }
        self.init(input: input, cached: cached, writes: writes, output: output, reasoning: reasoning)
        guard isValid else { return nil }
    }
    func delta(from previous: TokenUsage) -> TokenUsage {
        // Compaction and restarts can reset the counters.
        if input < previous.input || output < previous.output { return self }
        return TokenUsage(input: input - previous.input, cached: cached - previous.cached,
                          writes: writes - previous.writes, output: output - previous.output,
                          reasoning: reasoning - previous.reasoning)
    }
}

public struct UsageEvent: Sendable {
    public var piUsage: PiTokenUsage? = nil
    public var piProvider: String? = nil
    public var claudeUsage: ClaudeTokenUsage? = nil
    public var requestID: String? = nil
    public var identity: String
    public var sessionID: String
    public var timestamp: Date
    public var model: String?
    public var usage: TokenUsage
    public var requestInput: Int64?
    public var issue: String?
    public init(identity: String, sessionID: String, timestamp: Date, model: String?, usage: TokenUsage, requestInput: Int64?, issue: String? = nil) {
        self.identity = identity; self.sessionID = sessionID; self.timestamp = timestamp; self.model = model
        self.usage = usage; self.requestInput = requestInput; self.issue = issue
    }
}
public struct ParsedSession: Sendable {
    public var id: String
    public var parent: String?
    public var created: Date?
    public var events: [UsageEvent]
    public var diagnostics: Int
    var snapshots: [UsageSnapshot] = []
}
struct UsageSnapshot: Sendable {
    var identity: String
    var timestamp: Date
    var model: String?
    var total: TokenUsage
    var last: TokenUsage?
    var ordinal: Int
}
public struct ScanResult: Sendable {
    public var events: [UsageEvent]
    public var diagnostics: Int
    public var fileCount: Int
}
