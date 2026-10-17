import Foundation
import Testing

@testable import CostCore

/// Validates the shipped fallback catalogs. Accounting tests use `fixturePricing()` instead.
struct BundledPricingTests {
    @Test func bundledCatalogsLoadWithProvenance() throws {
        let pricing = try PricingCatalog.load()
        #expect(pricing.source.contains("openai.com"))
        #expect(pricing.source.contains("fireworks.ai"))
        #expect(pricing.fetchedAt == nil)
        #expect(!pricing.bundled.isEmpty)
        #expect(!pricing.piBundled.isEmpty)
        #expect(pricing.openCode?.isEmpty == false)
    }

    @Test func everyBundledRatePricesSimpleUsage() throws {
        let pricing = try PricingCatalog.load()
        func event(_ model: String, _ usage: ProviderUsage) -> UsageEvent {
            UsageEvent(
                identity: model, sessionID: "s", timestamp: Date(), model: model, usage: usage,
                requestInput: 1_000)
        }
        let claude = try JSONDecoder().decode(
            ClaudeTokenUsage.self,
            from: Data(
                """
                {"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":100}
                """.utf8))
        for model in pricing.bundled.keys {
            let usage: ProviderUsage =
                model.hasPrefix("claude-")
                ? .claude(claude) : .codex(TokenUsage(input: 1_000, output: 100))
            #expect(pricing.cost(for: event(model, usage)).usd != nil, "\(model)")
        }
        let pi = PiTokenUsage(
            input: 1_000, output: 100, cacheRead: 0, cacheWrite: 0, cacheWrite1h: nil,
            reasoning: nil)
        for route in pricing.piBundled.keys {
            let (provider, model) = try split(route)
            #expect(
                pricing.cost(for: event(model, .pi(pi, provider: provider))).usd != nil, "\(route)")
        }
        let openCode = OpenCodeTokenUsage(
            input: 1_000, cacheRead: 0, cacheWrite: 0, output: 100, reasoning: 0)
        for route in try #require(pricing.openCode).keys {
            let (provider, model) = try split(route)
            #expect(
                pricing.cost(for: event(model, .openCode(openCode, provider: provider))).usd != nil,
                "\(route)")
        }
    }
}

private func split(_ route: String) throws -> (provider: String, model: String) {
    let slash = try #require(route.firstIndex(of: "/"))
    return (String(route[..<slash]), String(route[route.index(after: slash)...]))
}
