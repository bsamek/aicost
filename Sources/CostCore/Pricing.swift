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
        enum CodingKeys: String, CodingKey { case input, cached, output }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            func decimal(_ key: CodingKeys) throws -> Decimal {
                let string = try values.decode(String.self, forKey: key)
                guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN, value >= 0 else {
                    throw PricingError.invalidCatalog
                }
                return value
            }
            input = try decimal(.input); output = try decimal(.output)
            cached = try values.decodeIfPresent(String.self, forKey: .cached) == nil ? nil : decimal(.cached)
        }
    }
    private struct ModelRates: Decodable, Sendable {
        let short: Rates
        let long: Rates?
    }
    private struct Catalog: Decodable {
        let source: String
        let verifiedAt: String
        let longContextThreshold: Int64
        let models: [String: ModelRates]
    }
    public let source: String
    public let verifiedAt: String
    private let threshold: Int64
    private let models: [String: ModelRates]

    public init(data: Data) throws {
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        guard catalog.longContextThreshold > 0, !catalog.models.isEmpty else { throw PricingError.invalidCatalog }
        source = catalog.source; verifiedAt = catalog.verifiedAt
        threshold = catalog.longContextThreshold; models = catalog.models
    }
    public static func load() throws -> PricingCatalog {
        let url: URL?
        if Bundle.main.bundleURL.pathExtension == "app" {
            url = Bundle.main.resourceURL?.appendingPathComponent("CodexCost_CostCore.bundle/pricing.json")
        } else {
            url = Bundle.module.url(forResource: "pricing", withExtension: "json")
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { throw PricingError.missingCatalog }
        return try PricingCatalog(data: Data(contentsOf: url))
    }
    public func cost(for event: UsageEvent) -> CostResult {
        func unpriced(_ reason: String) -> CostResult { CostResult(usd: nil, reason: reason) }
        if let issue = event.issue { return unpriced(issue) }
        guard event.usage.isValid else { return unpriced("Invalid token counts") }
        guard let model = event.model, let modelRates = models[model] else { return unpriced("Model rate unavailable") }
        let usage = event.usage
        // Available local samples have zero writes. Do not assume whether a future
        // nonzero write count is included in input until that schema is verified.
        guard usage.writes == 0 else { return unpriced("Cache-write accounting unavailable") }
        var rates = modelRates.short
        if let long = modelRates.long {
            if let requestInput = event.requestInput {
                guard requestInput >= 0 else { return unpriced("Invalid request token count") }
                if requestInput > threshold { rates = long }
            } else if usage.input > threshold {
                return unpriced("Request context unavailable")
            }
        }
        guard usage.cached == 0 || rates.cached != nil else { return unpriced("Cached-input rate unavailable") }
        let amount = (Decimal(usage.input - usage.cached) * rates.input
            + Decimal(usage.cached) * (rates.cached ?? 0)
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
