import Foundation
import Testing
@testable import CostCore

struct SummaryTests {
    @Test func localMidnightSeparatesDaysAndMonthBoundary() throws {
        let events = [
            testEvent(timestamp: "2026-10-01T03:59:00Z"), // Sep 30 23:59
            testEvent(timestamp: "2026-10-01T04:00:00Z"), // Oct 1 00:00
            testEvent(model: "tiered", usage: TokenUsage(input: 100_000), timestamp: "2026-10-02T04:00:00Z"),
            testEvent(timestamp: "2026-10-03T04:00:00Z") // future
        ]
        let summary = try buildSummary(events, now: "2026-10-02T12:00:00Z")
        #expect(summary.today.total == Decimal(string: "0.2"))
        #expect(summary.month.total == Decimal(string: "2.2"))
        #expect(summary.month.models.map(\.model) == ["plain", "tiered"])
        #expect(summary.month.models.reduce(Decimal.zero) { $0 + $1.total } == summary.month.total)
    }
    @Test func unknownModelsAreVisibleAndExcludedFromTotals() throws {
        let summary = try buildSummary([testEvent(), testEvent(model: "mystery"), testEvent(model: nil)], now: "2026-10-10T15:00:00Z")
        #expect(summary.today.total == 2)
        #expect(summary.today.unpricedCount == 2)
        #expect(summary.today.models.count == 3)
        #expect(summary.today.models.first(where: { $0.model == "mystery" })?.unpricedCount == 1)
    }
    @Test func daylightSavingRepeatedHourIsInTheSameDay() throws {
        let summary = try buildSummary([
            testEvent(timestamp: "2026-11-01T05:30:00Z"),
            testEvent(timestamp: "2026-11-01T06:30:00Z"),
            testEvent(timestamp: "2026-11-02T05:00:00Z")
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
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return SummaryBuilder.build(events: events, now: ISO8601DateFormatter().date(from: now)!, calendar: calendar, pricing: try testPricing())
}
