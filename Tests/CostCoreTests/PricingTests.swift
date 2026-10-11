import Foundation
import Testing
@testable import CostCore

struct PricingTests {
    @Test func cachedInputAndReasoningAreNotChargedTwice() throws {
        let pricing = try testPricing()
        let event = testEvent(usage: TokenUsage(input: 1_000_000, cached: 250_000, output: 100_000, reasoning: 70_000))
        #expect(pricing.cost(for: event).usd == Decimal(string: "2.525"))
    }
    @Test func longContextUsesRequestNotCumulativeInput() throws {
        let pricing = try testPricing()
        var event = testEvent(model: "tiered", usage: TokenUsage(input: 272_000, output: 1000))
        #expect(pricing.cost(for: event).usd == Decimal(string: "0.554"))
        event.usage.input = 272_001; event.requestInput = 272_001
        #expect(pricing.cost(for: event).usd == Decimal(string: "1.103004"))
        event.usage.input = 1_000_000; event.requestInput = 100_000
        #expect(pricing.cost(for: event).usd == Decimal(string: "2.01"))
        event.requestInput = nil
        #expect(pricing.cost(for: event).usd == nil)
        #expect(pricing.cost(for: event).reason != nil)
    }
    @Test func unknownModelAndUnverifiedWritesStayUnpriced() throws {
        let pricing = try testPricing()
        #expect(pricing.cost(for: testEvent(model: "unknown")).usd == nil)
        #expect(pricing.cost(for: testEvent(model: nil)).usd == nil)
        #expect(pricing.cost(for: testEvent(usage: TokenUsage(input: 100, writes: 40))).usd == nil)
        var event = testEvent(); event.issue = "Fork baseline unavailable"
        #expect(pricing.cost(for: event).reason == "Fork baseline unavailable")
    }
    @Test func invalidCountsCannotProduceNegativeCosts() throws {
        #expect(try testPricing().cost(for: testEvent(usage: TokenUsage(input: 10, cached: 11))).usd == nil)
    }
}
func testPricing() throws -> PricingCatalog {
    try PricingCatalog(data: Data("""
    {"source":"fixture","verifiedAt":"2026-10-10","longContextThreshold":272000,"models":{
        "plain":{"short":{"input":"2","cached":"0.10","output":"10"}},
        "tiered":{"short":{"input":"2","cached":"0.10","output":"10"},"long":{"input":"4","cached":"0.20","output":"15"}}
    }}
    """.utf8))
}
func testEvent(model: String? = "plain", usage: TokenUsage = TokenUsage(input: 1_000_000), timestamp: String = "2026-10-10T12:00:00Z") -> UsageEvent {
    UsageEvent(identity: UUID().uuidString, sessionID: "s", timestamp: ISO8601DateFormatter().date(from: timestamp)!, model: model, usage: usage, requestInput: usage.input)
}
