import Foundation
import Testing
@testable import CostCore

struct ClaudeTests {
    @Test func parsesSeparateCacheCategoriesAndDoesNotSumIterations() throws {
        let scan = ClaudeSessionParser.parse(data: Data(claudeFixture().utf8))
        let event = try #require(scan.events.first)
        #expect(event.claudeUsage?.input == 2)
        #expect(event.claudeUsage?.cacheRead == 23422)
        #expect(event.claudeUsage?.cacheWrite1h == 19357)
        #expect(event.requestInput == 42781)
        #expect(try PricingCatalog.load().cost(for: event).usd == Decimal(string: "0.206991"))
    }
    @Test func deduplicatesInheritedCopiesAndIncludesNestedAgents() throws {
        try withClaudeHome { home in
            let original = Data(claudeFixture().utf8)
            try original.write(to: home.appendingPathComponent("projects/a.jsonl"))
            let nested = home.appendingPathComponent("projects/session/subagents")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data((claudeFixture(session: "child") + "\n" + claudeFixture(id: "msg_other", session: "agent")).utf8).write(to: nested.appendingPathComponent("agent.jsonl"))
            let scanner = ClaudeSessionScanner()
            let scan = try scanner.scan(home: home)
            #expect(scan.events.count == 2)
            #expect(scan.fileCount == 2)
            #expect(try scanner.scan(home: home).events.count == 2)
            #expect(try Data(contentsOf: home.appendingPathComponent("projects/a.jsonl")) == original)
            try FileManager.default.removeItem(at: nested.appendingPathComponent("agent.jsonl"))
            #expect(try scanner.scan(home: home).events.count == 1)
        }
    }
    @Test func malformedIdentityAndNonIntegerCountsAreSkipped() {
        for fixture in [claudeFixture(id: ""), claudeFixture(input: Int64.max),
                        claudeFixture().replacingOccurrences(of: "\"input_tokens\":2", with: "\"input_tokens\":true"),
                        claudeFixture().replacingOccurrences(of: "\"input_tokens\":2", with: "\"input_tokens\":1.5")] {
            let scan = ClaudeSessionParser.parse(data: Data(fixture.utf8))
            #expect(scan.events.isEmpty)
            #expect(scan.diagnostics == 1)
        }
    }
    @Test func missingDirectoryIsEmptyAndBadRootThrows() throws {
        try withClaudeHome { home in
            try FileManager.default.removeItem(at: home.appendingPathComponent("projects"))
            #expect(try ClaudeSessionScanner().scan(home: home).events.isEmpty)
            try Data("invalid".utf8).write(to: home.appendingPathComponent("projects"))
            #expect(throws: (any Error).self) { try ClaudeSessionScanner().scan(home: home) }
        }
    }
    @Test func conflictingDuplicatesAreUnpriced() throws {
        try withClaudeHome { home in
            try Data((claudeFixture() + "\n" + claudeFixture(output: 99)).utf8).write(to: home.appendingPathComponent("projects/a.jsonl"))
            let scan = try ClaudeSessionScanner().scan(home: home)
            #expect(scan.events.count == 1)
            #expect(try PricingCatalog.load().cost(for: scan.events[0]).usd == nil)
            #expect(scan.diagnostics > 0)
        }
    }
    @Test func missingTTLAndInvalidCountsAreDiagnosed() throws {
        let unknown = ClaudeSessionParser.parse(data: Data(claudeFixture(split: "null").utf8))
        #expect(try PricingCatalog.load().cost(for: unknown.events[0]).usd == nil)
        let bad = ClaudeSessionParser.parse(data: Data(claudeFixture(input: -1).utf8))
        #expect(bad.events.isEmpty)
        #expect(bad.diagnostics == 1)
        let mismatch = ClaudeSessionParser.parse(data: Data(claudeFixture(split: "{\"ephemeral_5m_input_tokens\":1,\"ephemeral_1h_input_tokens\":1}").utf8))
        #expect(try PricingCatalog.load().cost(for: mismatch.events[0]).usd == nil)
        #expect(ClaudeSessionParser.parse(data: Data("{broken".utf8)).diagnostics == 1)
    }
    @Test func mixedTTLAndModelSpecificContextBoundary() throws {
        let pricing = try PricingCatalog.load()
        for (input, expected) in [(Int64(99970), "0.01000085"), (Int64(99971), "0.05000475") ] {
            let fixture = claudeFixture(model: "claude-haiku-5-5", input: input, read: 10, writes: 20, output: 1,
                split: "{\"ephemeral_5m_input_tokens\":10,\"ephemeral_1h_input_tokens\":10}")
            let event = try #require(ClaudeSessionParser.parse(data: Data(fixture.utf8)).events.first)
            #expect(pricing.cost(for: event).usd == Decimal(string: expected))
        }
    }
    @Test func datesUseLocalCalendarAndEarliestDuplicateTimestamp() throws {
        try withClaudeHome { home in
            let lines = [claudeFixture(id: "prior", timestamp: "2026-10-01T03:59:59Z"),
                         claudeFixture(timestamp: "2026-10-11T03:59:59Z"),
                         claudeFixture(session: "child", timestamp: "2026-10-11T04:00:01Z"),
                         claudeFixture(id: "future", timestamp: "2026-10-11T04:00:02Z")]
            try Data(lines.joined(separator: "\n").utf8).write(to: home.appendingPathComponent("projects/a.jsonl"))
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
            let events = try ClaudeSessionScanner().scan(home: home).events
            let summary = SummaryBuilder.build(events: events, now: ISO8601DateFormatter().date(from: "2026-10-11T04:00:01Z")!, calendar: calendar, pricing: try PricingCatalog.load())
            #expect(summary.today.total == 0)
            #expect(summary.month.total == Decimal(string: "0.206991"))
        }
    }
}
func withClaudeHome(_ body: (URL) throws -> Void) throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("projects"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try body(home)
}
func claudeFixture(id: String = "msg_one", session: String = "s", timestamp: String = "2026-10-10T12:00:00Z", model: String = "claude-opus-5", input: Int64 = 2, read: Int64 = 23422, writes: Int64 = 19357, output: Int64 = 68, split: String = "{\"ephemeral_5m_input_tokens\":0,\"ephemeral_1h_input_tokens\":19357}") -> String {
    """
    {"type":"assistant","timestamp":"\(timestamp)","uuid":"\(UUID().uuidString)","sessionId":"\(session)","requestId":"req_\(id)","message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":\(input),"cache_read_input_tokens":\(read),"cache_creation_input_tokens":\(writes),"output_tokens":\(output),"cache_creation":\(split),"iterations":[{"input_tokens":999999}]}}}
    """
}
