import Foundation

public struct CostResult: Sendable {
    public var usd: Decimal?
    public var reason: String?
}

public struct PricingCatalog: Sendable {
    private struct Rates: Decodable, Sendable {
        let input: Decimal
        let cached: Decimal?
        let output: Decimal
        let writes: Decimal?
        let writes5m: Decimal?
        let writes1h: Decimal?
        enum CodingKeys: String, CodingKey {
            case input, cached, output, writes, writes5m, writes1h
        }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            func decimal(_ key: CodingKeys) throws -> Decimal {
                let string = try values.decode(String.self, forKey: key)
                guard
                    let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
                    !value.isNaN, value >= 0
                else {
                    throw PricingError.invalidCatalog
                }
                return value
            }
            input = try decimal(.input)
            output = try decimal(.output)
            writes =
                try values.decodeIfPresent(String.self, forKey: .writes) == nil
                ? nil : decimal(.writes)
            writes5m =
                try values.decodeIfPresent(String.self, forKey: .writes5m) == nil
                ? nil : decimal(.writes5m)
            writes1h =
                try values.decodeIfPresent(String.self, forKey: .writes1h) == nil
                ? nil : decimal(.writes1h)
            cached =
                try values.decodeIfPresent(String.self, forKey: .cached) == nil
                ? nil : decimal(.cached)
        }
    }
    private struct ModelRates: Decodable, Sendable {
        let short: Rates
        let long: Rates?
        let longContextThreshold: Int64?
        let tiers: [Tier]?
        let issue: String?
        struct Tier: Decodable, Sendable {
            let threshold: Int64
            let rates: Rates
        }
        func selected(_ input: Int64?, threshold: Int64) -> Rates {
            guard let input else { return short }
            if let tier = tiers?.filter({ input > $0.threshold }).max(by: {
                $0.threshold < $1.threshold
            }) {
                return tier.rates
            }
            if let long, input > (longContextThreshold ?? threshold) { return long }
            return short
        }
        var isTiered: Bool { long != nil || !(tiers?.isEmpty ?? true) }
        func firstThreshold(_ fallback: Int64) -> Int64 {
            tiers?.map(\.threshold).min() ?? longContextThreshold ?? fallback
        }
    }
    private struct Catalog: Decodable {
        let source: String
        let verifiedAt: String
        let longContextThreshold: Int64
        let models: [String: ModelRates]
    }
    public let source: String
    public let verifiedAt: String
    public let fetchedAt: Date?
    private let threshold: Int64
    private let models: [String: ModelRates]
    private let openCodePricing: OpenCodePricingCatalog?

    private let piModels: [String: ModelRates]
    private let apiModels: [String: ModelRates]

    public init(
        data: Data, piData: Data? = nil, openCodeData: Data? = nil, modelsDevData: Data? = nil,
        fetchedAt: Date? = nil
    ) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard catalog.longContextThreshold > 0, !catalog.models.isEmpty else {
            throw PricingError.invalidCatalog
        }
        let piCatalog = try piData.map { try JSONDecoder().decode(Catalog.self, from: $0) }
        piModels = piCatalog?.models ?? [:]
        let converted = try modelsDevData.map {
            try ModelsDevCatalog.convert($0, bundledData: data)
        }
        apiModels =
            try converted.map { try JSONDecoder().decode([String: ModelRates].self, from: $0) }
            ?? [:]
        openCodePricing = try openCodeData.map {
            try OpenCodePricingCatalog(data: $0, apiModelsData: converted)
        }
        source =
            (modelsDevData == nil ? "" : "https://models.dev/api.json ; bundled fallback: ")
            + catalog.source + (piCatalog.map { " ; " + $0.source } ?? "")
        verifiedAt = min(catalog.verifiedAt, piCatalog?.verifiedAt ?? catalog.verifiedAt)
        self.fetchedAt = modelsDevData == nil ? nil : fetchedAt
        threshold = catalog.longContextThreshold
        models = catalog.models
    }
    public static func load(modelsDevData: Data? = nil, fetchedAt: Date? = nil) throws
        -> PricingCatalog
    {
        func resource(_ name: String) throws -> Data {
            let url: URL?
            if Bundle.main.bundleURL.pathExtension == "app" {
                url = Bundle.main.resourceURL?.appendingPathComponent(
                    "CodexCost_CostCore.bundle/\(name).json")
            } else {
                url = Bundle.module.url(forResource: name, withExtension: "json")
            }
            guard let url, FileManager.default.fileExists(atPath: url.path) else {
                throw PricingError.missingCatalog
            }
            return try Data(contentsOf: url)
        }
        return try PricingCatalog(
            data: resource("pricing"), piData: resource("pi-pricing"),
            openCodeData: OpenCodePricingCatalog.bundledData(), modelsDevData: modelsDevData,
            fetchedAt: fetchedAt)
    }
    public func cost(for event: UsageEvent) -> CostResult {
        func unpriced(_ reason: String) -> CostResult { CostResult(usd: nil, reason: reason) }
        if let issue = event.issue { return unpriced(issue) }
        if let usage = event.piUsage { return piCost(for: event, usage: usage) }
        if let usage = event.claudeUsage { return claudeCost(for: event, usage: usage) }
        if let usage = event.openCodeUsage {
            guard let openCodePricing else {
                return unpriced("OpenCode pricing catalog unavailable")
            }
            return openCodePricing.cost(for: event, usage: usage)
        }
        guard event.usage.isValid else { return unpriced("Invalid token counts") }
        guard let model = event.model,
            let modelRates = apiModels["openai/" + model]
                ?? (model.hasPrefix("claude-") ? nil : models[model])
        else { return unpriced("Model rate unavailable") }
        if let issue = modelRates.issue { return unpriced(issue) }
        let usage = event.usage
        // Available local samples have zero writes. Do not assume whether a future
        // nonzero write count is included in input until that schema is verified.
        guard usage.writes == 0 else { return unpriced("Cache-write accounting unavailable") }
        if modelRates.isTiered {
            if let requestInput = event.requestInput {
                guard requestInput >= 0 else { return unpriced("Invalid request token count") }
            } else if usage.input > modelRates.firstThreshold(threshold) {
                return unpriced("Request context unavailable")
            }
        }
        let rates = modelRates.selected(event.requestInput, threshold: threshold)
        guard usage.cached == 0 || rates.cached != nil else {
            return unpriced("Cached-input rate unavailable")
        }
        let amount =
            (Decimal(usage.input - usage.cached) * rates.input
                + Decimal(usage.cached) * (rates.cached ?? 0)
                + Decimal(usage.output) * rates.output) / 1_000_000
        return CostResult(usd: amount, reason: nil)
    }
    private func piCost(for event: UsageEvent, usage: PiTokenUsage) -> CostResult {
        func unpriced(_ reason: String) -> CostResult { CostResult(usd: nil, reason: reason) }
        guard usage.isValid else { return unpriced("Invalid Pi token counts") }
        guard let provider = event.piProvider, let model = event.model else {
            return unpriced("Pi provider/model unavailable")
        }
        let modelRates: ModelRates?
        let apiProvider =
            provider == "openai-codex"
            ? "openai" : provider == "fireworks" ? "fireworks-ai" : provider
        if provider == "openrouter" {
            return unpriced("Pi OpenRouter serving-route rate unavailable")
        }
        if let remote = apiModels[apiProvider + "/" + model] {
            modelRates = remote
        } else {
            switch provider {
            case "anthropic": modelRates = model.hasPrefix("claude-") ? models[model] : nil
            case "openai", "openai-codex":
                modelRates = !model.hasPrefix("claude-") ? models[model] : nil
            case "fireworks": modelRates = piModels[provider + "/" + model]
            default: return unpriced("Pi provider rate unavailable: " + provider)
            }
        }
        guard let modelRates else { return unpriced("Pi model rate unavailable for " + provider) }
        if let issue = modelRates.issue { return unpriced(issue) }
        let rates = modelRates.selected(usage.requestInput, threshold: threshold)
        guard usage.cacheRead == 0 || rates.cached != nil else {
            return unpriced("Pi cache-read rate unavailable")
        }
        var writes: Decimal = 0
        if provider == "anthropic" {
            if usage.cacheWrite > 0 {
                guard let hour = usage.cacheWrite1h else {
                    return unpriced("Pi Anthropic cache-write duration unavailable")
                }
                let five = usage.cacheWrite - hour
                guard five == 0 || rates.writes5m != nil, hour == 0 || rates.writes1h != nil else {
                    return unpriced("Pi Anthropic cache-write rate unavailable")
                }
                writes =
                    Decimal(five) * (rates.writes5m ?? 0) + Decimal(hour) * (rates.writes1h ?? 0)
            }
        } else {
            guard (usage.cacheWrite1h ?? 0) == 0 else {
                return unpriced("Pi provider cache-write duration rate unavailable")
            }
            guard usage.cacheWrite == 0 || rates.writes != nil else {
                return unpriced("Pi cache-write rate unavailable")
            }
            writes = Decimal(usage.cacheWrite) * (rates.writes ?? 0)
        }
        let amount =
            (Decimal(usage.input) * rates.input + Decimal(usage.cacheRead) * (rates.cached ?? 0)
                + writes + Decimal(usage.output) * rates.output) / 1_000_000
        return CostResult(usd: amount, reason: nil)
    }
    private func claudeCost(for event: UsageEvent, usage: ClaudeTokenUsage) -> CostResult {
        func unpriced(_ reason: String) -> CostResult { CostResult(usd: nil, reason: reason) }
        guard usage.isValid else { return unpriced("Invalid Claude token counts") }
        if let issue = usage.cacheIssue { return unpriced(issue) }
        guard let model = event.model,
            let modelRates = apiModels["anthropic/" + model]
                ?? (model.hasPrefix("claude-") ? models[model] : nil)
        else { return unpriced("Model rate unavailable") }
        if let issue = modelRates.issue { return unpriced(issue) }
        let rates = modelRates.selected(usage.requestInput, threshold: threshold)
        guard usage.cacheRead == 0 || rates.cached != nil else {
            return unpriced("Cached-input rate unavailable")
        }
        let five = usage.cacheWrite5m ?? 0
        let hour = usage.cacheWrite1h ?? 0
        guard five == 0 || rates.writes5m != nil, hour == 0 || rates.writes1h != nil else {
            return unpriced("Claude cache-write rate unavailable")
        }
        let amount =
            (Decimal(usage.input) * rates.input + Decimal(usage.cacheRead) * (rates.cached ?? 0)
                + Decimal(five) * (rates.writes5m ?? 0) + Decimal(hour) * (rates.writes1h ?? 0)
                + Decimal(usage.output) * rates.output) / 1_000_000
        return CostResult(usd: amount, reason: nil)
    }

}

public enum PricingError: LocalizedError {
    case invalidCatalog, missingCatalog
    public var errorDescription: String? {
        switch self {
        case .invalidCatalog: "The bundled pricing data is invalid."
        case .missingCatalog: "The bundled pricing data is missing. Rebuild the app."
        }
    }
}
