import Foundation

/// Converts the public API into `provider/model` rates.
/// Provider keys are retained; canonical model names are never used for billing.
enum ModelsDevCatalog {
    static let maximumResponseBytes = 20_000_000

    private struct Provider: Decodable { let models: [String: Model] }
    private struct Model: Decodable { let cost: Cost? }
    private struct Cost: Decodable {
        let input: Decimal
        let output: Decimal
        let cacheRead: Decimal?
        let cacheWrite: Decimal?
        let reasoning: Decimal?
        let tiers: [Tier]?
        let contextOver200k: BaseCost?
        enum CodingKeys: String, CodingKey {
            case input, output, reasoning, tiers
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
            case contextOver200k = "context_over_200k"
        }
    }
    private struct BaseCost: Decodable {
        let input: Decimal
        let output: Decimal
        let cacheRead: Decimal?
        let cacheWrite: Decimal?
        let reasoning: Decimal?
        enum CodingKeys: String, CodingKey {
            case input, output, reasoning
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }
    }
    private struct Tier: Decodable {
        struct Boundary: Decodable {
            let type: String?
            let size: Int64
        }
        let tier: Boundary
        let input: Decimal
        let output: Decimal
        let cacheRead: Decimal?
        let cacheWrite: Decimal?
        let reasoning: Decimal?
        enum CodingKeys: String, CodingKey {
            case tier, input, output, reasoning
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }
    }

    /// `bundled` supplies verified Anthropic one-hour cache-write rates, which the API lacks.
    static func convert(_ data: Data, bundled: [String: ModelRates], defaultThreshold: Int64)
        throws -> [String: ModelRates]
    {
        guard data.count <= maximumResponseBytes else { throw PricingError.invalidCatalog }
        let providers = try JSONDecoder().decode([String: Provider].self, from: data)
        var models: [String: ModelRates] = [:]
        for (provider, entry) in providers {
            guard !provider.isEmpty else { throw PricingError.invalidCatalog }
            let anthropic = provider == "anthropic"
            for (model, value) in entry.models {
                guard !model.isEmpty else { throw PricingError.invalidCatalog }
                guard let cost = value.cost else { continue }
                let original = anthropic ? bundled[model] : nil
                func rates(
                    input: Decimal, output: Decimal, cached: Decimal?, writes: Decimal?,
                    reasoning: Decimal?, override: Rates?
                ) throws -> Rates {
                    guard
                        [input, output, cached, writes, reasoning].compactMap({ $0 }).allSatisfy({
                            !$0.isNaN && $0 >= 0
                        })
                    else { throw PricingError.invalidCatalog }
                    var result = Rates(input: input, output: output, cached: cached, writes: writes)
                    if anthropic {
                        result.writes5m = writes
                        // Keep a verified one-hour rate only while its base input rate still matches.
                        // New/changed rates stay unpriced for one-hour writes rather than guessing.
                        if let override, override.input == input {
                            result.writes1h = override.writes1h
                        }
                    }
                    return result
                }
                var unsupportedReasoning = cost.reasoning.map { $0 != cost.output } ?? false
                var tiers: [ModelRates.Tier] = []
                var sizes = Set<Int64>()
                for tier in cost.tiers ?? [] {
                    guard (tier.tier.type ?? "context") == "context", tier.tier.size > 0,
                        sizes.insert(tier.tier.size).inserted
                    else { throw PricingError.invalidCatalog }
                    let originalThreshold = original?.longContextThreshold ?? defaultThreshold
                    tiers.append(
                        ModelRates.Tier(
                            threshold: tier.tier.size,
                            rates: try rates(
                                input: tier.input, output: tier.output, cached: tier.cacheRead,
                                writes: tier.cacheWrite, reasoning: tier.reasoning,
                                override: tier.tier.size == originalThreshold
                                    ? original?.long : nil)))
                    unsupportedReasoning =
                        unsupportedReasoning || (tier.reasoning.map { $0 != tier.output } ?? false)
                }
                // Legacy API entries use an explicit 200k threshold. Never infer it from context limits.
                if tiers.isEmpty, let tier = cost.contextOver200k {
                    tiers.append(
                        ModelRates.Tier(
                            threshold: 200_000,
                            rates: try rates(
                                input: tier.input, output: tier.output, cached: tier.cacheRead,
                                writes: tier.cacheWrite, reasoning: tier.reasoning, override: nil)))
                    unsupportedReasoning =
                        unsupportedReasoning || (tier.reasoning.map { $0 != tier.output } ?? false)
                }
                models[provider + "/" + model] = ModelRates(
                    short: try rates(
                        input: cost.input, output: cost.output, cached: cost.cacheRead,
                        writes: cost.cacheWrite, reasoning: cost.reasoning,
                        override: original?.short),
                    tiers: tiers,
                    issue: unsupportedReasoning ? "Separate reasoning-token rate unsupported" : nil)
            }
        }
        guard !models.isEmpty else { throw PricingError.invalidCatalog }
        return models
    }
}
