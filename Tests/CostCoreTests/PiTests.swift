import Foundation
import Testing
@testable import CostCore

struct PiTests {
    @Test func parsesDisjointCategoriesAndIgnoresRecordedCostAndReasoningSubset() throws {
        let scan = PiSessionParser.parse(data: piData(piFixture()))
        let event = try #require(scan.events.first)
        #expect(event.model == "gpt-6.1-sol")
        #expect(event.piProvider == "openai-codex")
        #expect(event.requestInput == 1300)
        #expect(try PricingCatalog.load().cost(for: event).usd == Decimal(string: "0.00427"))
        #expect(scan.diagnostics == 0)
    }
    @Test func pricesProviderSpecificRatesAndContextBoundary() throws {
        let pricing = try PricingCatalog.load()
        for (provider, model, writes, hour, expected) in [
            ("fireworks", "accounts/fireworks/models/deepseek-v4p1-flash", 0, "null", "0.0005412"),
            ("fireworks", "accounts/fireworks/models/glm-5p3-flash", 0, "null", "0.000256"),
            ("anthropic", "claude-sonnet-5-5", 100, "40", "0.00433")
        ] {
            let event = try #require(PiSessionParser.parse(data: piData(piFixture(provider: provider, model: model, writes: Int64(writes), hour: hour))).events.first)
            #expect(pricing.cost(for: event).usd == Decimal(string: expected))
        }
        for (input, expected) in [(Int64(271700), "0.54567"), (Int64(271701), "1.090344")] {
            let event = try #require(PiSessionParser.parse(data: piData(piFixture(input: input))).events.first)
            #expect(pricing.cost(for: event).usd == Decimal(string: expected))
        }
    }
    @Test func unsupportedProvidersModelsAndCacheDurationsStayExplicit() throws {
        let pricing = try PricingCatalog.load()
        for fixture in [piFixture(provider: "openrouter"), piFixture(provider: "custom"),
                        piFixture(provider: "fireworks", model: "gpt-6.1-sol"),
                        piFixture(model: "unknown"), piFixture(provider: "anthropic", model: "claude-sonnet-5-5", hour: "null"),
                        piFixture(provider: "fireworks", model: "accounts/fireworks/models/glm-5p3-flash")] {
            let event = try #require(PiSessionParser.parse(data: piData(fixture)).events.first)
            #expect(pricing.cost(for: event).usd == nil)
            #expect(pricing.cost(for: event).reason != nil)
            let summary = SummaryBuilder.build(events: [event], now: ISO8601DateFormatter().date(from: "2026-10-12T17:00:00Z")!, calendar: .current, pricing: pricing)
            #expect(summary.today.unpricedCount == 1)
            #expect(summary.today.models.first?.reasons.isEmpty == false)
        }
    }
    @Test func rejectsMalformedCountsTimestampsAndUnsupportedVersions() {
        for fixture in [piFixture(id: ""), piFixture(input: -1), piFixture(input: Int64.max),
                        piFixture(hour: "101"), piFixture().replacingOccurrences(of: "\"input\":1000", with: "\"input\":true"),
                        piFixture().replacingOccurrences(of: "\"input\":1000", with: "\"input\":1.5"),
                        piFixture().replacingOccurrences(of: "1791806400000", with: "-1")] {
            let scan = PiSessionParser.parse(data: piData(fixture))
            #expect(scan.events.isEmpty)
            #expect(scan.diagnostics == 1)
        }
        #expect(PiSessionParser.parse(data: piData(piFixture(), version: 99)).events.isEmpty)
        #expect(PiSessionParser.parse(data: Data("{broken".utf8)).diagnostics == 1)
    }
    @Test func scannerDeduplicatesCopiesAndRetainsSeparateCallsAcrossProviders() throws {
        try withPiHome { home in
            let first = piData(piFixture())
            let original = home.appendingPathComponent("sessions/original.jsonl")
            try first.write(to: original)
            let nested = home.appendingPathComponent("sessions/project/child.jsonl")
            try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
            try piData(piFixture(id: "fork-copy") + "\n" + piFixture(id: "fresh", response: "resp_fresh") + "\n" + piFixture(provider: "custom"), session: "child").write(to: nested)
            let scanner = PiSessionScanner()
            #expect(try scanner.scan(home: home).events.count == 3)
            #expect(try scanner.scan(home: home).events.count == 3)
            #expect(try Data(contentsOf: original) == first)
            try FileManager.default.removeItem(at: nested)
            #expect(try scanner.scan(home: home).events.count == 1)
        }
    }
    @Test func fallbackEntryIdentityDeduplicatesInheritedHistoryAndDetectsConflicts() throws {
        try withPiHome { home in
            let fixture = piFixture(response: "")
            try piData(fixture + "\n" + fixture + "\n" + piFixture(response: "", provider: "custom")).write(to: home.appendingPathComponent("sessions/a.jsonl"))
            try piData(fixture, session: "child").write(to: home.appendingPathComponent("sessions/b.jsonl"))
            #expect(try PiSessionScanner().scan(home: home).events.count == 2)
            try piData(piFixture(output: 201, response: ""), session: "child").write(to: home.appendingPathComponent("sessions/b.jsonl"))
            let scan = try PiSessionScanner().scan(home: home)
            #expect(scan.events.count == 2)
            #expect(scan.diagnostics > 0)
            #expect(try PricingCatalog.load().cost(for: scan.events.first { $0.piProvider == "openai-codex" }!).usd == nil)
        }
    }
    @Test func attributedAuxiliaryUsageIsPricedAndUnattributedSummariesRemainVisible() throws {
        let records = [piAuxiliaryFixture(type: "usage", id: "warm"),
                       piAuxiliaryFixture(type: "compaction", id: "compact"),
                       piAuxiliaryFixture(type: "branch_summary", id: "branch")].joined(separator: "\n")
        let scan = PiSessionParser.parse(data: piData(records))
        #expect(scan.events.count == 3)
        #expect(scan.diagnostics == 2)
        let pricing = try PricingCatalog.load()
        let attributed = try #require(scan.events.first { $0.model != nil })
        #expect(pricing.cost(for: attributed).usd == Decimal(string: "0.002"))
        let formatter = ISO8601DateFormatter()
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let summary = SummaryBuilder.build(events: scan.events, now: formatter.date(from: "2026-10-12T17:00:00Z")!, calendar: calendar, pricing: pricing)
        #expect(summary.today.total == Decimal(string: "0.002"))
        #expect(summary.today.unpricedCount == 2)
        let unknown = try #require(summary.today.models.first { $0.model == "Unknown model" })
        #expect(unknown.unpricedCount == 2)
        #expect(unknown.reasons == ["Pi compaction usage provider/model unavailable", "Pi branch_summary usage provider/model unavailable"])
    }
    @Test func auxiliaryUsageUsesISOTimestampAndInheritedCopiesCountOnce() throws {
        try withPiHome { home in
            let records = [piAuxiliaryFixture(type: "usage", id: "prior-month", timestamp: "2026-10-01T03:59:59Z"),
                           piAuxiliaryFixture(type: "usage", id: "prior-day", timestamp: "2026-10-12T03:59:59.999Z"),
                           piAuxiliaryFixture(type: "usage", id: "today", timestamp: "2026-10-12T04:00:00.000Z"),
                           piAuxiliaryFixture(type: "compaction", id: "summary")].joined(separator: "\n")
            try piData(records, version: 2).write(to: home.appendingPathComponent("sessions/a.jsonl"))
            try piData(records, session: "fork").write(to: home.appendingPathComponent("sessions/b.jsonl"))
            let scan = try PiSessionScanner().scan(home: home)
            #expect(scan.events.count == 4)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
            let summary = SummaryBuilder.build(events: scan.events, now: ISO8601DateFormatter().date(from: "2026-10-12T17:00:00Z")!, calendar: calendar, pricing: try PricingCatalog.load())
            #expect(summary.today.total == Decimal(string: "0.002"))
            #expect(summary.month.total == Decimal(string: "0.004"))
            #expect(summary.today.unpricedCount == 1)
        }
    }
    @Test func sharedProviderResponseIDDeduplicatesAssistantAndAuxiliaryRecords() throws {
        try withPiHome { home in
            let auxiliary = piAuxiliaryFixture(type: "usage", id: "imported")
                .replacingOccurrences(of: "\"usage\":", with: "\"responseId\":\"resp_one\",\"usage\":")
                .replacingOccurrences(of: "\"output\":0,\"cacheRead\":0,\"cacheWrite\":0", with: "\"output\":200,\"cacheRead\":200,\"cacheWrite\":100,\"cacheWrite1h\":0,\"reasoning\":50")
            try piData(piFixture() + "\n" + auxiliary).write(to: home.appendingPathComponent("sessions/a.jsonl"))
            let scan = try PiSessionScanner().scan(home: home)
            #expect(scan.events.count == 1)
            #expect(scan.diagnostics == 0)
            #expect(try PricingCatalog.load().cost(for: scan.events[0]).usd == Decimal(string: "0.00427"))
        }
    }
    @Test func auxiliaryMissingAttributionIsUnpricedAndInvalidDataIsDiagnosed() throws {
        let missing = PiSessionParser.parse(data: piData(piAuxiliaryFixture(type: "usage", id: "missing").replacingOccurrences(of: "\"provider\":\"openai-codex\",\"model\":\"gpt-6.1-sol\",", with: "")))
        let event = try #require(missing.events.first)
        #expect(event.model == nil)
        #expect(try PricingCatalog.load().cost(for: event).usd == nil)
        #expect(missing.diagnostics == 1)
        for fixture in [piAuxiliaryFixture(type: "usage", id: "", timestamp: "2026-10-12T13:00:00Z"),
                        piAuxiliaryFixture(type: "usage", id: "bad-time", timestamp: "invalid"),
                        piAuxiliaryFixture(type: "branch_summary", id: "negative").replacingOccurrences(of: "\"input\":1000", with: "\"input\":-1")] {
            let scan = PiSessionParser.parse(data: piData(fixture))
            #expect(scan.events.isEmpty)
            #expect(scan.diagnostics == 1)
        }
        let withoutUsage = "{\"type\":\"compaction\",\"id\":\"no-usage\"}"
        #expect(PiSessionParser.parse(data: piData(withoutUsage)).diagnostics == 0)
    }
    @Test func fallbackModelConflictCountsOnceAndRemainsUnpriced() throws {
        try withPiHome { home in
            try piData(piFixture(response: "")).write(to: home.appendingPathComponent("sessions/a.jsonl"))
            try piData(piFixture(response: "", model: "gpt-6-astra"), session: "fork").write(to: home.appendingPathComponent("sessions/b.jsonl"))
            let scan = try PiSessionScanner().scan(home: home)
            let event = try #require(scan.events.first)
            #expect(scan.events.count == 1)
            #expect(scan.diagnostics == 1)
            #expect(try PricingCatalog.load().cost(for: event).usd == nil)
        }
    }
    @Test func missingRootIsEmptyBadRootThrowsAndChangesInvalidateCache() throws {
        try withPiHome { home in
            let scanner = PiSessionScanner()
            let file = home.appendingPathComponent("sessions/a.jsonl")
            try piData(piFixture()).write(to: file)
            #expect(try scanner.scan(home: home).events.count == 1)
            try piData(piFixture() + "\n" + piFixture(id: "second", response: "resp_second")).write(to: file)
            #expect(try scanner.scan(home: home).events.count == 2)
            try FileManager.default.removeItem(at: home.appendingPathComponent("sessions"))
            #expect(try scanner.scan(home: home).fileCount == 0)
            try Data("bad".utf8).write(to: home.appendingPathComponent("sessions"))
            #expect(throws: (any Error).self) { try scanner.scan(home: home) }
        }
    }
    @Test func partialActiveLineIsDiagnosedAndCompletionIsReadOnNextScan() throws {
        try withPiHome { home in
            let file = home.appendingPathComponent("sessions/active.jsonl")
            let next = piFixture(id: "second", response: "resp_second")
            try (piData(piFixture()) + Data(("\n" + String(next.prefix(40))).utf8)).write(to: file)
            let scanner = PiSessionScanner()
            let partial = try scanner.scan(home: home)
            #expect(partial.events.count == 1)
            #expect(partial.diagnostics == 1)
            let handle = try FileHandle(forWritingTo: file)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(next.dropFirst(40).utf8))
            try handle.close()
            let complete = try scanner.scan(home: home)
            #expect(complete.events.count == 2)
            #expect(complete.diagnostics == 0)
        }
    }
    @Test func summaryUsesRequestDateLocalBoundariesAndDistinctProviderRows() throws {
        let stamps = ["2026-10-01T03:59:59Z", "2026-10-12T03:59:59Z", "2026-10-12T04:00:00Z", "2026-10-12T16:00:01Z"]
        let formatter = ISO8601DateFormatter()
        let events = stamps.enumerated().flatMap { index, stamp in
            PiSessionParser.parse(data: piData(piFixture(id: "\(index)", response: "resp_\(index)", milliseconds: Int64(formatter.date(from: stamp)!.timeIntervalSince1970 * 1000)))).events
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let summary = SummaryBuilder.build(events: events, now: formatter.date(from: "2026-10-12T16:00:00Z")!, calendar: calendar, pricing: try PricingCatalog.load())
        #expect(summary.today.total == Decimal(string: "0.00427"))
        #expect(summary.month.total == Decimal(string: "0.00854"))
        #expect(summary.today.models.first?.model == "openai-codex/gpt-6.1-sol")
    }
}

private func piFixture(id: String = "a1b2c3d4", output: Int64 = 200, response: String = "resp_one", provider: String = "openai-codex", model: String = "gpt-6.1-sol", input: Int64 = 1000, writes: Int64 = 100, hour: String = "0", milliseconds: Int64 = 1791806400000) -> String {
    """
    {"type":"message","id":"\(id)","parentId":null,"timestamp":"2026-10-12T13:00:00Z","message":{"role":"assistant","provider":"\(provider)","model":"\(model)","responseId":"\(response)","timestamp":\(milliseconds),"stopReason":"toolUse","usage":{"input":\(input),"output":\(output),"cacheRead":200,"cacheWrite":\(writes),"cacheWrite1h":\(hour),"reasoning":50,"totalTokens":999999,"cost":{"total":99999}}}}
    """
}
private func piAuxiliaryFixture(type: String, id: String, timestamp: String = "2026-10-12T13:00:00Z") -> String {
    let attribution = type == "usage" ? "\"kind\":\"cache_warm\",\"provider\":\"openai-codex\",\"model\":\"gpt-6.1-sol\"," : ""
    return """
    {"type":"\(type)","id":"\(id)","parentId":null,"timestamp":"\(timestamp)",\(attribution)"usage":{"input":1000,"output":0,"cacheRead":0,"cacheWrite":0}}
    """
}
private func piData(_ records: String, session: String = "session", version: Int = 3) -> Data {
    Data(("{\"type\":\"session\",\"id\":\"\(session)\",\"version\":\(version),\"timestamp\":\"2026-10-12T00:00:00Z\"}\n" + records).utf8)
}
private func withPiHome(_ body: (URL) throws -> Void) throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try body(home)
}
