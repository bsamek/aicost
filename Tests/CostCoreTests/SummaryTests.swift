import Foundation
import Testing

@testable import CostCore

struct SummaryTests {
    @Test func rowsGroupByServingProviderAndFamilyWithNewerVersionsFirst() throws {
        let expected = [
            "claude-fable-5-1", "claude-fable-5", "anthropic/claude-haiku-5-5",
            "claude-opus-5-5", "claude-opus-5", "claude-opus-4-8", "claude-sonnet-5-5",
            "fireworks-ai/accounts/fireworks/models/deepseek-v4p1-flash",
            "fireworks/accounts/fireworks/models/deepseek-v4p1-flash",
            "fireworks-ai/accounts/fireworks/models/glm-5p3-flash", "fireworks/glm-5p3-flash",
            "gpt-6-astra", "gpt-5.5", "gpt-5.4-mini", "gpt-6-luna", "o4-mini", "o3",
            "gpt-6.10-sol", "gpt-6.9-sol", "openai-codex/gpt-6.1-sol", "openai/gpt-6-sol",
            "gpt-5.6-terra",
            "opencode/claude-opus-5", "opencode-go/gpt-6-sol",
            "openrouter/anthropic/claude-sonnet-5-5",
            "anthropic/claude-mystery-9", "gpt-9-unfamiliar", "mystery", "Unknown model",
        ]
        let events = expected.reversed().map { testEvent(model: $0 == "Unknown model" ? nil : $0) }
        let summary = try orderedSummary(events, models: expected)
        #expect(summary.today.models.map(\.model) == expected)
        #expect(summary.month.models.map(\.model) == expected)
        #expect(summary.today.total == Decimal(expected.count - 1))
        #expect(summary.today.unpricedCount == 1)
        #expect(summary.today.models.last?.unpricedCount == 1)
    }

    @Test func equalVersionsAndUnknownRowsHaveDeterministicFallback() throws {
        let expected = [
            "gpt-6.1-sol", "gpt-6.1-sol-preview", "openai-codex/gpt-6.1-sol",
            "openai/gpt-6.1-sol", "fireworks/aaa", "fireworks/zzz", "unknown/aaa", "unknown/zzz",
        ]
        for models in [
            expected, Array(expected.reversed()), Array(expected.dropFirst()) + [expected[0]],
        ] {
            let summary = try orderedSummary(models.map { testEvent(model: $0) }, models: expected)
            #expect(summary.today.models.map(\.model) == expected)
        }
    }

    @Test func modelOrderDoesNotDependOnDifferentTodayAndMonthCosts() throws {
        let expected = ["claude-opus-5", "gpt-6.1-sol", "gpt-6-sol"]
        let summary = try orderedSummary(
            [
                testEvent(model: "gpt-6-sol", usage: TokenUsage(input: 9_000_000)),
                testEvent(model: "gpt-6.1-sol", usage: TokenUsage(input: 2_000_000)),
                testEvent(model: "claude-opus-5", usage: TokenUsage(input: 1_000_000)),
                testEvent(
                    model: "gpt-6.1-sol", usage: TokenUsage(input: 20_000_000),
                    timestamp: "2026-10-09T12:00:00Z"),
            ], models: expected)
        #expect(summary.today.models.map(\.model) == expected)
        #expect(summary.month.models.map(\.model) == expected)
        #expect(summary.today.total == 12)
        #expect(summary.month.total == 32)
        #expect(summary.today.models.map(\.total) == [1, 2, 9])
        #expect(summary.month.models.map(\.total) == [1, 22, 9])
    }

    @Test func decimalAndHyphenVersionsSortNumericallyAcrossFamilies() throws {
        let expected = [
            "claude-opus-5-10", "claude-opus-5-9", "claude-opus-5", "claude-opus-4-8",
            "fireworks/deepseek-v4p10-flash", "fireworks/deepseek-v4p9-flash",
            "fireworks/glm-5p10-flash", "fireworks/glm-5p3-flash", "gpt-5.10", "gpt-5.9", "o10",
            "o9",
        ]
        let summary = try orderedSummary(
            expected.reversed().map { testEvent(model: $0) }, models: expected)
        #expect(summary.today.models.map(\.model) == expected)
    }

    @Test func localMidnightSeparatesDaysAndMonthBoundary() throws {
        let events = [
            testEvent(timestamp: "2026-10-01T03:59:00Z"),  // Sep 30 23:59
            testEvent(timestamp: "2026-10-01T04:00:00Z"),  // Oct 1 00:00
            testEvent(
                model: "tiered", usage: TokenUsage(input: 100_000),
                timestamp: "2026-10-02T04:00:00Z"),
            testEvent(timestamp: "2026-10-03T04:00:00Z"),  // future
        ]
        let summary = try buildSummary(events, now: "2026-10-02T12:00:00Z")
        #expect(summary.today.total == Decimal(string: "0.2"))
        #expect(summary.month.total == Decimal(string: "2.2"))
        #expect(summary.month.models.map(\.model) == ["plain", "tiered"])
        #expect(summary.month.models.reduce(Decimal.zero) { $0 + $1.total } == summary.month.total)
    }
    @Test func unknownModelsAreVisibleAndExcludedFromTotals() throws {
        let summary = try buildSummary(
            [testEvent(), testEvent(model: "mystery"), testEvent(model: nil)],
            now: "2026-10-10T15:00:00Z")
        #expect(summary.today.total == 2)
        #expect(summary.today.unpricedCount == 2)
        #expect(summary.today.models.count == 3)
        #expect(summary.today.models.first(where: { $0.model == "mystery" })?.unpricedCount == 1)
    }
    @Test func daylightSavingRepeatedHourIsInTheSameDay() throws {
        let summary = try buildSummary(
            [
                testEvent(timestamp: "2026-11-01T05:30:00Z"),
                testEvent(timestamp: "2026-11-01T06:30:00Z"),
                testEvent(timestamp: "2026-11-02T05:00:00Z"),
            ], now: "2026-11-01T18:00:00Z")
        #expect(summary.today.total == 4)
    }
    @Test func emptyPeriodsAreZero() throws {
        let summary = try buildSummary([], now: "2026-10-10T15:00:00Z")
        #expect(summary.today.total == 0)
        #expect(summary.month.models.isEmpty)
    }
}
func buildSummary(_ events: [UsageEvent], now: String) throws -> CostSummary {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return SummaryBuilder.build(
        events: events, now: ISO8601DateFormatter().date(from: now)!, calendar: calendar,
        pricing: try testPricing())
}

private func orderedSummary(_ events: [UsageEvent], models: [String]) throws -> CostSummary {
    let rates = Dictionary(
        uniqueKeysWithValues: models.map { ($0, ["short": ["input": "1", "output": "1"]]) })
    let data = try JSONSerialization.data(withJSONObject: [
        "source": "fixture", "verifiedAt": "2026-10-10", "longContextThreshold": 272000,
        "models": rates,
    ])
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    // Raw Claude IDs belong to Claude usage; don't route ordering fixtures through Codex pricing.
    let attributed = try events.map { event in
        var event = event
        if event.model?.hasPrefix("claude-") == true, let codex = event.codexUsage {
            let data = try JSONSerialization.data(withJSONObject: [
                "input_tokens": codex.input,
                "cache_read_input_tokens": codex.cached, "cache_creation_input_tokens": 0,
                "output_tokens": codex.output,
            ])
            event.usage = .claude(try JSONDecoder().decode(ClaudeTokenUsage.self, from: data))
        }
        return event
    }
    return SummaryBuilder.build(
        events: attributed, now: ISO8601DateFormatter().date(from: "2026-10-10T15:00:00Z")!,
        calendar: calendar, pricing: try PricingCatalog(data: data))
}
