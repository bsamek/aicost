import Foundation

struct OpenCodePricingCatalog: Sendable {
    private struct Rates: Decodable, Sendable {
        let input: String
        let cached: String?
        let writes: String?
        let output: String
        var values: [Decimal]? {
            let raw = [input, cached ?? "0", writes ?? "0", output]
            let values = raw.compactMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
            guard values.count == 4, values.allSatisfy({ !$0.isNaN && $0 >= 0 }) else { return nil }
            return values
        }
    }
    private struct ModelRates: Decodable, Sendable {
        let short: Rates
        let long: Rates?
        let longContextThreshold: Int64?
        let tiers: [Tier]?
        let issue: String?
        struct Tier: Decodable, Sendable { let threshold: Int64; let rates: Rates }
    }
    private struct Catalog: Decodable {
        let source: String
        let verifiedAt: String
        let models: [String: ModelRates]
    }
    private let models: [String: ModelRates]
    init(data: Data, apiModelsData: Data? = nil) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard !catalog.models.isEmpty,
              catalog.models.values.allSatisfy({ $0.short.values != nil && ($0.long == nil || ($0.long!.values != nil && ($0.longContextThreshold ?? 0) > 0)) }) else { throw PricingError.invalidCatalog }
        let remote = try apiModelsData.map { try JSONDecoder().decode([String: ModelRates].self, from: $0) } ?? [:]
        // Aggregator routes cannot be inferred from their model's canonical identity.
        models = catalog.models.merging(remote.filter { !$0.key.hasPrefix("openrouter/") }) { _, api in api }
    }
    static func bundledData() throws -> Data {
        let url: URL?
        if Bundle.main.bundleURL.pathExtension == "app" {
            url = Bundle.main.resourceURL?.appendingPathComponent("CodexCost_CostCore.bundle/opencode-pricing.json")
        } else { url = Bundle.module.url(forResource: "opencode-pricing", withExtension: "json") }
        guard let url else { throw PricingError.missingCatalog }
        return try Data(contentsOf: url)
    }
    func cost(for event: UsageEvent, usage: OpenCodeTokenUsage) -> CostResult {
        func unpriced(_ reason: String) -> CostResult { CostResult(usd: nil, reason: reason) }
        guard let provider = event.openCodeProvider, let model = event.model else { return unpriced("OpenCode provider/model unavailable") }
        guard let modelRates = models[provider + "/" + model] else { return unpriced("OpenCode rate unavailable for \(provider)/\(model)") }
        if let issue = modelRates.issue { return unpriced(issue) }
        let tier = modelRates.tiers?.filter { usage.requestInput > $0.threshold }.max { $0.threshold < $1.threshold }
        let rates = tier?.rates ?? (usage.requestInput > (modelRates.longContextThreshold ?? Int64.max) ? (modelRates.long ?? modelRates.short) : modelRates.short)
        guard usage.cacheRead == 0 || rates.cached != nil else { return unpriced("OpenCode cache-read rate unavailable") }
        guard usage.cacheWrite == 0 || rates.writes != nil else { return unpriced("OpenCode cache-write rate unavailable") }
        guard let values = rates.values else { return unpriced("Invalid OpenCode pricing data") }
        let amount = (Decimal(usage.input) * values[0] + Decimal(usage.cacheRead) * values[1]
                      + Decimal(usage.cacheWrite) * values[2] + Decimal(usage.billableOutput) * values[3]) / 1_000_000
        return CostResult(usd: amount, reason: nil)
    }
}
