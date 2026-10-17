import Foundation

/// USD per million tokens. Absent optional rates leave matching nonzero usage unpriced.
struct Rates: Decodable, Sendable {
    var input: Decimal
    var cached: Decimal?
    var output: Decimal
    var writes: Decimal?
    var writes5m: Decimal?
    var writes1h: Decimal?

    init(
        input: Decimal, output: Decimal, cached: Decimal? = nil, writes: Decimal? = nil,
        writes5m: Decimal? = nil, writes1h: Decimal? = nil
    ) {
        self.input = input
        self.output = output
        self.cached = cached
        self.writes = writes
        self.writes5m = writes5m
        self.writes1h = writes1h
    }

    private enum CodingKeys: String, CodingKey {
        case input, cached, output, writes, writes5m, writes1h
    }

    /// Bundled catalogs store rates as decimal strings, so no binary rounding occurs.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func decimal(_ key: CodingKeys) throws -> Decimal? {
            guard let string = try values.decodeIfPresent(String.self, forKey: key) else {
                return nil
            }
            guard
                let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
                !value.isNaN, value >= 0
            else { throw PricingError.invalidCatalog }
            return value
        }
        guard let input = try decimal(.input), let output = try decimal(.output) else {
            throw PricingError.invalidCatalog
        }
        self.init(
            input: input, output: output, cached: try decimal(.cached),
            writes: try decimal(.writes), writes5m: try decimal(.writes5m),
            writes1h: try decimal(.writes1h))
    }
}

struct ModelRates: Decodable, Sendable {
    struct Tier: Decodable, Sendable {
        var threshold: Int64
        var rates: Rates
    }
    var short: Rates
    var long: Rates?
    var longContextThreshold: Int64?
    var tiers: [Tier]?
    var issue: String?

    /// The highest tier whose threshold the request input exceeds; otherwise long or short.
    func rates(forRequestInput input: Int64?, defaultThreshold: Int64) -> Rates {
        guard let input else { return short }
        if let tier = tiers?.filter({ input > $0.threshold }).max(by: {
            $0.threshold < $1.threshold
        }) {
            return tier.rates
        }
        if let long, input > (longContextThreshold ?? defaultThreshold) { return long }
        return short
    }
    var isTiered: Bool { long != nil || !(tiers?.isEmpty ?? true) }
    func firstThreshold(_ fallback: Int64) -> Int64 {
        tiers?.map(\.threshold).min() ?? longContextThreshold ?? fallback
    }
}

/// The shape of each bundled `Resources/*-pricing.json` catalog.
struct RateCatalogFile: Decodable {
    let source: String
    let verifiedAt: String
    let longContextThreshold: Int64?
    let models: [String: ModelRates]

    static func decode(_ data: Data) throws -> RateCatalogFile {
        try JSONDecoder().decode(Self.self, from: data)
    }

    static func bundledData(_ name: String) throws -> Data {
        let url: URL?
        // App builds copy SwiftPM's resource bundle into Contents/Resources.
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
}
