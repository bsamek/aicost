import Foundation
import Testing

@testable import CostCore

struct ModelsDevTests {
    @Test func apiPricesOverrideBundledRatesAndRespectContextBoundaries() throws {
        let pricing = try PricingCatalog.load(modelsDevData: apiFixture(), fetchedAt: apiDate)
        var event = testEvent(
            model: "gpt-6.1-sol", usage: TokenUsage(input: 100_000, cached: 20_000, output: 1_000))
        #expect(pricing.cost(for: event).usd == Decimal(string: "0.259"))
        event.requestInput = 100_001
        #expect(pricing.cost(for: event).usd == Decimal(string: "0.518"))
        event.requestInput = 200_001
        #expect(pricing.cost(for: event).usd == Decimal(string: "0.777"))
        #expect(pricing.source.contains("models.dev"))
        // Fetch time must not masquerade as provider verification.
        #expect(pricing.verifiedAt == "2026-10-10")
    }

    @Test func apiKeepsExactProvidersAndAddsModelsWithoutGuessing() throws {
        let pricing = try PricingCatalog.load(modelsDevData: apiFixture(), fetchedAt: apiDate)
        let usage = OpenCodeTokenUsage(
            input: 1_000, cacheRead: 0, cacheWrite: 0, output: 0, reasoning: 0)
        func cost(_ provider: String, _ model: String) -> Decimal? {
            var event = testEvent(model: model)
            event.usage = .openCode(usage, provider: provider)
            return pricing.cost(for: event).usd
        }
        #expect(cost("example", "new-model") == Decimal(string: "0.007"))
        #expect(cost("custom", "new-model") == nil)
        #expect(cost("example", "free-model") == 0)
        #expect(cost("opencode", "gpt-6.1-sol") == Decimal(string: "0.004"))
        // A missing API entry still uses an exact bundled rate.
        #expect(pricing.cost(for: testEvent(model: "gpt-4.1")).usd != nil)
    }

    @Test func claudeRetainsDurationRatesAndRejectsUnknownHourRates() throws {
        let pricing = try PricingCatalog.load(modelsDevData: apiFixture(), fetchedAt: apiDate)
        var event = testEvent(model: "claude-sonnet-5-5")
        event.usage = .claude(
            try JSONDecoder().decode(
                ClaudeTokenUsage.self,
                from: Data(
                    """
                    {"input_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":100000,
                     "output_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":100000}}
                    """.utf8)))
        #expect(pricing.cost(for: event).usd == Decimal(string: "0.4"))
        event.model = "claude-new"
        #expect(pricing.cost(for: event).usd == nil)
    }

    @Test func bundledFallbackDoesNotBorrowAnotherProvidersModel() throws {
        let pricing = try PricingCatalog.load(modelsDevData: apiFixture(), fetchedAt: apiDate)
        var event = testEvent(model: "gpt-6.1-sol")
        event.usage = .claude(
            try JSONDecoder().decode(
                ClaudeTokenUsage.self,
                from: Data(
                    """
                    {"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}
                    """.utf8)))
        #expect(pricing.cost(for: event).usd == nil)
        event = testEvent(model: "claude-sonnet-5-5")
        #expect(pricing.cost(for: event).usd == nil)
    }

    @Test func rejectsMalformedPricesAndUnsupportedTiers() throws {
        for bad in [
            "{}", "[]", "{\"x\":{\"models\":{\"a\":{\"cost\":{\"input\":-1,\"output\":2}}}}}",
            "{\"x\":{\"models\":{\"a\":{\"cost\":{\"input\":true,\"output\":2}}}}}",
        ] {
            #expect(throws: (any Error).self) {
                try PricingCatalog.load(modelsDevData: Data(bad.utf8), fetchedAt: apiDate)
            }
        }
        let data = Data(
            """
            {"openai":{"models":{"gpt-6.1-sol":{"cost":{"input":1,"output":2,"tiers":[
              {"tier":{"type":"context","size":100},"input":2,"output":4},
              {"tier":{"type":"context","size":100},"input":3,"output":6}]}}}}}
            """.utf8)
        #expect(throws: (any Error).self) {
            try PricingCatalog.load(modelsDevData: data, fetchedAt: apiDate)
        }
    }

    @Test func missingAPICacheRatesDoNotBorrowBundledRatesAndReasoningPremiumsStayUnpriced() throws
    {
        let data = Data(
            """
            {"openai":{"models":{"gpt-6.1-sol":{"cost":{"input":3,"output":15}}}},
             "opencode":{"models":{"gpt-6.1-sol":{"cost":{"input":2,"output":10,"reasoning":20}}}},
             "openrouter":{"models":{"gpt-6.1-sol":{"cost":{"input":2,"output":10}}}}}
            """.utf8)
        let pricing = try PricingCatalog.load(modelsDevData: data, fetchedAt: apiDate)
        var event = testEvent(model: "gpt-6.1-sol", usage: TokenUsage(input: 1_000, cached: 500))
        #expect(pricing.cost(for: event).reason == "Cached-input rate unavailable")
        let usage = OpenCodeTokenUsage(
            input: 1_000, cacheRead: 0, cacheWrite: 0, output: 20, reasoning: 10)
        event.usage = .openCode(usage, provider: "opencode")
        #expect(pricing.cost(for: event).reason == "Separate reasoning-token rate unsupported")
        event.usage = .openCode(usage, provider: "openrouter")
        #expect(pricing.cost(for: event).usd == nil)
    }

    @Test func legacyContextTierUsesExplicit200kBoundary() throws {
        let data = Data(
            """
            {"openai":{"models":{"gpt-6.1-sol":{"cost":{"input":2,"output":10,
              "context_over_200k":{"input":4,"output":15}}}}}}
            """.utf8)
        let pricing = try PricingCatalog.load(modelsDevData: data, fetchedAt: apiDate)
        var event = testEvent(model: "gpt-6.1-sol", usage: TokenUsage(input: 1000))
        event.requestInput = 200_000
        #expect(pricing.cost(for: event).usd == Decimal(string: "0.002"))
        event.requestInput = 200_001
        #expect(pricing.cost(for: event).usd == Decimal(string: "0.004"))
    }

    @Test func concurrentRefreshesShareOneDownload() async throws {
        let root = try apiTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = DeferredTransport()
        let store = PricingStore(cacheDirectory: root, fetch: { await transport.fetch($0) })
        let first = Task { await store.refreshIfNeeded(now: apiDate) }
        await transport.waitUntilStarted()
        #expect(await store.refreshIfNeeded(now: apiDate) == false)
        // The current catalog remains available while a download is suspended.
        #expect(try await store.catalog().fetchedAt == nil)
        await transport.finish()
        #expect(await first.value)
    }

    @Test func refreshPersistsCacheAndThrottlesAcrossStoreInstances() async throws {
        let root = try apiTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = CatalogTransport(data: apiFixture())
        let store = PricingStore(cacheDirectory: root, fetch: { try await transport.fetch($0) })
        #expect(await store.refreshIfNeeded(now: apiDate))
        #expect(await transport.calls == 1)
        let restored = PricingStore(cacheDirectory: root, fetch: { try await transport.fetch($0) })
        #expect(await restored.refreshIfNeeded(now: apiDate.addingTimeInterval(86_399)) == false)
        #expect(await transport.calls == 1)
        #expect(
            try await restored.catalog().cost(
                for: testEvent(model: "gpt-6.1-sol", usage: TokenUsage(input: 1_000))
            ).usd == Decimal(string: "0.003"))
        #expect(await restored.refreshIfNeeded(now: apiDate.addingTimeInterval(86_400)))
        #expect(await transport.calls == 2)
    }

    @Test func failedOrInvalidRefreshKeepsLastGoodCacheAndDoesNotRetryEveryTick() async throws {
        let root = try apiTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let good = PricingStore(cacheDirectory: root, fetch: { _ in (apiFixture(), 200) })
        #expect(await good.refreshIfNeeded(now: apiDate))
        for (index, response) in [(Data("{}".utf8), 200), (apiFixture(), 503)].enumerated() {
            let transport = CatalogTransport(data: response.0, status: response.1)
            let store = PricingStore(cacheDirectory: root, fetch: { try await transport.fetch($0) })
            let now = apiDate.addingTimeInterval(Double(index + 1) * 86_400)
            #expect(await store.refreshIfNeeded(now: now) == false)
            #expect(await store.refreshIfNeeded(now: now.addingTimeInterval(30)) == false)
            #expect(await transport.calls == 1)
            let restarted = PricingStore(
                cacheDirectory: root, fetch: { try await transport.fetch($0) })
            #expect(await restarted.refreshIfNeeded(now: now.addingTimeInterval(60)) == false)
            #expect(await transport.calls == 1)
            #expect(
                try await store.catalog().cost(
                    for: testEvent(model: "gpt-6.1-sol", usage: TokenUsage(input: 1_000))
                ).usd == Decimal(string: "0.003"))
        }
        let offline = PricingStore(
            cacheDirectory: root, fetch: { _ in throw URLError(.notConnectedToInternet) })
        #expect(await offline.refreshIfNeeded(now: apiDate.addingTimeInterval(4 * 86_400)) == false)
        #expect(
            try await offline.catalog().cost(
                for: testEvent(model: "gpt-6.1-sol", usage: TokenUsage(input: 1_000))
            ).usd == Decimal(string: "0.003"))
    }

    @Test func emptyOrCorruptCacheUsesBundledPrices() async throws {
        let root = try apiTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PricingStore(
            cacheDirectory: root, fetch: { _ in throw URLError(.notConnectedToInternet) })
        #expect(
            try await store.catalog().cost(
                for: testEvent(model: "gpt-6.1-sol", usage: TokenUsage(input: 1_000))
            ).usd == Decimal(string: "0.002"))
        try Data("broken".utf8).write(to: root.appendingPathComponent("models-dev.json"))
        #expect(
            try PricingStore.cachedCatalog(cacheDirectory: root).cost(
                for: testEvent(model: "gpt-6.1-sol", usage: TokenUsage(input: 1_000))
            ).usd == Decimal(string: "0.002"))
    }
}

private let apiDate = Date(timeIntervalSince1970: 1_791_800_000)
private func apiFixture() -> Data {
    Data(
        """
        {"openai":{"models":{"gpt-6.1-sol":{"cost":{"input":3,"output":15,"cache_read":0.2,
            "tiers":[{"tier":{"type":"context","size":100000},"input":6,"output":30,"cache_read":0.4},
                     {"tier":{"type":"context","size":200000},"input":9,"output":45,"cache_read":0.6}]}}}},
         "opencode":{"models":{"gpt-6.1-sol":{"cost":{"input":4,"output":20,"cache_read":0.3}}}},
         "anthropic":{"models":{"claude-sonnet-5-5":{"cost":{"input":2,"output":10,"cache_write":2.5}},
                                   "claude-new":{"cost":{"input":2,"output":10,"cache_write":2.5}}}},
         "example":{"models":{"new-model":{"cost":{"input":7,"output":21}},
                                "free-model":{"cost":{"input":0,"output":0}}}}}
        """.utf8)
}
private func apiTemporaryDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
private actor CatalogTransport {
    var calls = 0
    let data: Data
    let status: Int
    init(data: Data, status: Int = 200) {
        self.data = data
        self.status = status
    }
    func fetch(_ request: URLRequest) throws -> (Data, Int) {
        #expect(request.url?.absoluteString == "https://models.dev/api.json")
        #expect(request.httpMethod == nil || request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        calls += 1
        return (data, status)
    }
}

private actor DeferredTransport {
    private var reply: CheckedContinuation<(Data, Int), Never>?
    private var started: CheckedContinuation<Void, Never>?
    func fetch(_ request: URLRequest) async -> (Data, Int) {
        await withCheckedContinuation { continuation in
            reply = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if reply != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish() {
        reply?.resume(returning: (apiFixture(), 200))
        reply = nil
    }
}
