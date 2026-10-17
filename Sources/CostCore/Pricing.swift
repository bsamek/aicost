import Foundation

public struct CostResult: Sendable {
    public var usd: Decimal?
    public var reason: String?
    static func priced(_ usd: Decimal) -> CostResult { CostResult(usd: usd, reason: nil) }
    static func unpriced(_ reason: String) -> CostResult { CostResult(usd: nil, reason: reason) }
}

/// Merged rate tables. Provider-specific cost rules live in `ProviderPricing.swift`.
public struct PricingCatalog: Sendable {
    public let source: String
    public let verifiedAt: String
    public let fetchedAt: Date?
    /// Applies to bundled long-context rates without their own threshold.
    let defaultThreshold: Int64
    /// `pricing.json`: raw OpenAI and Anthropic model IDs.
    let bundled: [String: ModelRates]
    /// `pi-pricing.json`: `provider/model` routes not covered elsewhere.
    let piBundled: [String: ModelRates]
    /// `opencode-pricing.json` overlaid with API routes; nil when that catalog was not supplied.
    let openCode: [String: ModelRates]?
    /// models.dev `provider/model` rates.
    let api: [String: ModelRates]

    public init(
        data: Data, piData: Data? = nil, openCodeData: Data? = nil, modelsDevData: Data? = nil,
        fetchedAt: Date? = nil
    ) throws {
        let catalog = try RateCatalogFile.decode(data)
        guard let threshold = catalog.longContextThreshold, threshold > 0,
            !catalog.models.isEmpty
        else { throw PricingError.invalidCatalog }
        let piCatalog = try piData.map(RateCatalogFile.decode)
        let api =
            try modelsDevData.map {
                try ModelsDevCatalog.convert(
                    $0, bundled: catalog.models, defaultThreshold: threshold)
            } ?? [:]
        openCode = try openCodeData.map { data in
            let models = try RateCatalogFile.decode(data).models
            guard !models.isEmpty,
                models.values.allSatisfy({ $0.long == nil || ($0.longContextThreshold ?? 0) > 0 })
            else { throw PricingError.invalidCatalog }
            // Aggregator routes cannot be inferred from their model's canonical identity.
            return models.merging(api.filter { !$0.key.hasPrefix("openrouter/") }) { _, api in api }
        }
        source =
            (modelsDevData == nil ? "" : "https://models.dev/api.json ; bundled fallback: ")
            + catalog.source + (piCatalog.map { " ; " + $0.source } ?? "")
        verifiedAt = min(catalog.verifiedAt, piCatalog?.verifiedAt ?? catalog.verifiedAt)
        self.fetchedAt = modelsDevData == nil ? nil : fetchedAt
        defaultThreshold = threshold
        bundled = catalog.models
        piBundled = piCatalog?.models ?? [:]
        self.api = api
    }

    public static func load(modelsDevData: Data? = nil, fetchedAt: Date? = nil) throws
        -> PricingCatalog
    {
        try PricingCatalog(
            data: RateCatalogFile.bundledData("pricing"),
            piData: RateCatalogFile.bundledData("pi-pricing"),
            openCodeData: RateCatalogFile.bundledData("opencode-pricing"),
            modelsDevData: modelsDevData, fetchedAt: fetchedAt)
    }

    public func cost(for event: UsageEvent) -> CostResult {
        if let issue = event.issue { return .unpriced(issue) }
        switch event.usage {
        case .codex(let usage): return codexCost(for: event, usage: usage)
        case .claude(let usage): return claudeCost(for: event, usage: usage)
        case .pi(let usage, let provider):
            return piCost(for: event, usage: usage, provider: provider)
        case .openCode(let usage, let provider):
            return openCodeCost(for: event, usage: usage, provider: provider)
        }
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
