import Foundation

/// Converts the public API into the existing calculator's decimal-string format.
/// Provider keys are retained; canonical model names are never used for billing.
enum ModelsDevCatalog {
    private struct Provider: Decodable { let models: [String: Model] }
    private struct Model: Decodable { let cost: Cost? }
    private struct Cost: Decodable {
        let input: Decimal
        let output: Decimal
        let cache_read: Decimal?
        let cache_write: Decimal?
        let reasoning: Decimal?
        let tiers: [Tier]?
        let context_over_200k: BaseCost?
    }
    private struct BaseCost: Decodable {
        let input: Decimal
        let output: Decimal
        let cache_read: Decimal?
        let cache_write: Decimal?
        let reasoning: Decimal?
    }
    private struct Tier: Decodable {
        let tier: Boundary
        let input: Decimal
        let output: Decimal
        let cache_read: Decimal?
        let cache_write: Decimal?
        let reasoning: Decimal?
    }
    private struct Boundary: Decodable { let type: String?; let size: Int64 }

    static func convert(_ data: Data, bundledData: Data) throws -> Data {
        guard data.count <= 20_000_000 else { throw PricingError.invalidCatalog }
        let providers = try JSONDecoder().decode([String: Provider].self, from: data)
        let bundled = (try JSONSerialization.jsonObject(with: bundledData) as? [String: Any])?["models"] as? [String: [String: Any]] ?? [:]
        var models: [String: Any] = [:]
        func rates(input: Decimal, output: Decimal, cached: Decimal?, writes: Decimal?, reasoning: Decimal?,
                   anthropic: Bool, override: [String: Any]?) throws -> [String: Any] {
            guard [input, output, cached, writes, reasoning].compactMap({ $0 }).allSatisfy({ !$0.isNaN && $0 >= 0 }) else {
                throw PricingError.invalidCatalog
            }
            func string(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
            var result: [String: Any] = ["input": string(input), "output": string(output)]
            if let cached { result["cached"] = string(cached) }
            if let writes { result["writes"] = string(writes) }
            if anthropic {
                if let writes { result["writes5m"] = string(writes) }
                // Keep a verified one-hour rate only while its base input rate still matches.
                // New/changed rates stay unpriced for one-hour writes rather than guessing.
                if let base = override?["input"] as? String, Decimal(string: base) == input,
                   let hour = override?["writes1h"] as? String { result["writes1h"] = hour }
            }
            return result
        }
        for (provider, entry) in providers {
            guard !provider.isEmpty else { throw PricingError.invalidCatalog }
            for (model, value) in entry.models {
                guard !model.isEmpty else { throw PricingError.invalidCatalog }
                guard let cost = value.cost else { continue }
                let original = provider == "anthropic" ? bundled[model] : nil
                var result: [String: Any] = ["short": try rates(input: cost.input, output: cost.output,
                    cached: cost.cache_read, writes: cost.cache_write, reasoning: cost.reasoning,
                    anthropic: provider == "anthropic", override: original?["short"] as? [String: Any])]
                var tiers: [[String: Any]] = []
                var sizes = Set<Int64>()
                var unsupportedReasoning = cost.reasoning.map { $0 != cost.output } ?? false
                for tier in cost.tiers ?? [] {
                    guard (tier.tier.type ?? "context") == "context", tier.tier.size > 0,
                          sizes.insert(tier.tier.size).inserted else { throw PricingError.invalidCatalog }
                    let originalThreshold = (original?["longContextThreshold"] as? NSNumber)?.int64Value ?? 272_000
                    let override = tier.tier.size == originalThreshold ? original?["long"] as? [String: Any] : nil
                    tiers.append(["threshold": tier.tier.size, "rates": try rates(input: tier.input, output: tier.output,
                        cached: tier.cache_read, writes: tier.cache_write, reasoning: tier.reasoning,
                        anthropic: provider == "anthropic", override: override)])
                    unsupportedReasoning = unsupportedReasoning || (tier.reasoning.map { $0 != tier.output } ?? false)
                }
                // Legacy API entries use an explicit 200k threshold. Never infer it from context limits.
                if cost.tiers?.isEmpty ?? true, let tier = cost.context_over_200k {
                    tiers.append(["threshold": 200_000, "rates": try rates(input: tier.input, output: tier.output,
                        cached: tier.cache_read, writes: tier.cache_write, reasoning: tier.reasoning,
                        anthropic: provider == "anthropic", override: nil)])
                    unsupportedReasoning = unsupportedReasoning || (tier.reasoning.map { $0 != tier.output } ?? false)
                }
                result["tiers"] = tiers
                if unsupportedReasoning { result["issue"] = "Separate reasoning-token rate unsupported" }
                models[provider + "/" + model] = result
            }
        }
        guard !models.isEmpty else { throw PricingError.invalidCatalog }
        return try JSONSerialization.data(withJSONObject: models, options: [.sortedKeys])
    }
}
