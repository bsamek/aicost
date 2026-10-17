import Foundation

/// Each agent's token categories map onto rates differently. Missing rates stay unpriced.
extension PricingCatalog {
    /// Codex reports cached input as a subset of input and reasoning as a subset of output.
    func codexCost(for event: UsageEvent, usage: TokenUsage) -> CostResult {
        guard usage.isValid else { return .unpriced("Invalid token counts") }
        guard let model = event.model,
            let modelRates = api["openai/" + model]
                ?? (model.hasPrefix("claude-") ? nil : bundled[model])
        else { return .unpriced("Model rate unavailable") }
        if let issue = modelRates.issue { return .unpriced(issue) }
        // Available local samples have zero writes. Do not assume whether a future
        // nonzero write count is included in input until that schema is verified.
        guard usage.writes == 0 else { return .unpriced("Cache-write accounting unavailable") }
        if modelRates.isTiered {
            if let requestInput = event.requestInput {
                guard requestInput >= 0 else { return .unpriced("Invalid request token count") }
            } else if usage.input > modelRates.firstThreshold(defaultThreshold) {
                return .unpriced("Request context unavailable")
            }
        }
        let rates = modelRates.rates(
            forRequestInput: event.requestInput, defaultThreshold: defaultThreshold)
        guard usage.cached == 0 || rates.cached != nil else {
            return .unpriced("Cached-input rate unavailable")
        }
        return .priced(
            (Decimal(usage.input - usage.cached) * rates.input
                + Decimal(usage.cached) * (rates.cached ?? 0)
                + Decimal(usage.output) * rates.output) / 1_000_000)
    }

    /// Claude's input, cache reads, and five-minute/one-hour cache writes are disjoint.
    func claudeCost(for event: UsageEvent, usage: ClaudeTokenUsage) -> CostResult {
        guard usage.isValid else { return .unpriced("Invalid Claude token counts") }
        if let issue = usage.cacheIssue { return .unpriced(issue) }
        guard let model = event.model,
            let modelRates = api["anthropic/" + model]
                ?? (model.hasPrefix("claude-") ? bundled[model] : nil)
        else { return .unpriced("Model rate unavailable") }
        if let issue = modelRates.issue { return .unpriced(issue) }
        let rates = modelRates.rates(
            forRequestInput: usage.requestInput, defaultThreshold: defaultThreshold)
        guard usage.cacheRead == 0 || rates.cached != nil else {
            return .unpriced("Cached-input rate unavailable")
        }
        let five = usage.cacheWrite5m ?? 0
        let hour = usage.cacheWrite1h ?? 0
        guard five == 0 || rates.writes5m != nil, hour == 0 || rates.writes1h != nil else {
            return .unpriced("Claude cache-write rate unavailable")
        }
        return .priced(
            (Decimal(usage.input) * rates.input + Decimal(usage.cacheRead) * (rates.cached ?? 0)
                + Decimal(five) * (rates.writes5m ?? 0) + Decimal(hour) * (rates.writes1h ?? 0)
                + Decimal(usage.output) * rates.output) / 1_000_000)
    }

    /// Pi categories are disjoint; reasoning is already part of output.
    func piCost(for event: UsageEvent, usage: PiTokenUsage, provider: String?) -> CostResult {
        guard usage.isValid else { return .unpriced("Invalid Pi token counts") }
        guard let provider, let model = event.model else {
            return .unpriced("Pi provider/model unavailable")
        }
        if provider == "openrouter" {
            return .unpriced("Pi OpenRouter serving-route rate unavailable")
        }
        let apiProvider =
            provider == "openai-codex"
            ? "openai" : provider == "fireworks" ? "fireworks-ai" : provider
        let modelRates: ModelRates?
        if let remote = api[apiProvider + "/" + model] {
            modelRates = remote
        } else {
            switch provider {
            case "anthropic": modelRates = model.hasPrefix("claude-") ? bundled[model] : nil
            case "openai", "openai-codex":
                modelRates = !model.hasPrefix("claude-") ? bundled[model] : nil
            case "fireworks": modelRates = piBundled[provider + "/" + model]
            default: return .unpriced("Pi provider rate unavailable: " + provider)
            }
        }
        guard let modelRates else { return .unpriced("Pi model rate unavailable for " + provider) }
        if let issue = modelRates.issue { return .unpriced(issue) }
        let rates = modelRates.rates(
            forRequestInput: usage.requestInput, defaultThreshold: defaultThreshold)
        guard usage.cacheRead == 0 || rates.cached != nil else {
            return .unpriced("Pi cache-read rate unavailable")
        }
        var writes: Decimal = 0
        if provider == "anthropic" {
            if usage.cacheWrite > 0 {
                guard let hour = usage.cacheWrite1h else {
                    return .unpriced("Pi Anthropic cache-write duration unavailable")
                }
                let five = usage.cacheWrite - hour
                guard five == 0 || rates.writes5m != nil, hour == 0 || rates.writes1h != nil else {
                    return .unpriced("Pi Anthropic cache-write rate unavailable")
                }
                writes =
                    Decimal(five) * (rates.writes5m ?? 0) + Decimal(hour) * (rates.writes1h ?? 0)
            }
        } else {
            guard (usage.cacheWrite1h ?? 0) == 0 else {
                return .unpriced("Pi provider cache-write duration rate unavailable")
            }
            guard usage.cacheWrite == 0 || rates.writes != nil else {
                return .unpriced("Pi cache-write rate unavailable")
            }
            writes = Decimal(usage.cacheWrite) * (rates.writes ?? 0)
        }
        return .priced(
            (Decimal(usage.input) * rates.input + Decimal(usage.cacheRead) * (rates.cached ?? 0)
                + writes + Decimal(usage.output) * rates.output) / 1_000_000)
    }

    /// OpenCode categories are disjoint; reasoning is priced once as output.
    func openCodeCost(for event: UsageEvent, usage: OpenCodeTokenUsage, provider: String?)
        -> CostResult
    {
        guard let openCode else { return .unpriced("OpenCode pricing catalog unavailable") }
        guard let provider, let model = event.model else {
            return .unpriced("OpenCode provider/model unavailable")
        }
        guard let modelRates = openCode[provider + "/" + model] else {
            return .unpriced("OpenCode rate unavailable for \(provider)/\(model)")
        }
        if let issue = modelRates.issue { return .unpriced(issue) }
        // Bundled OpenCode long rates always declare their own threshold.
        let rates = modelRates.rates(forRequestInput: usage.requestInput, defaultThreshold: .max)
        guard usage.cacheRead == 0 || rates.cached != nil else {
            return .unpriced("OpenCode cache-read rate unavailable")
        }
        guard usage.cacheWrite == 0 || rates.writes != nil else {
            return .unpriced("OpenCode cache-write rate unavailable")
        }
        return .priced(
            (Decimal(usage.input) * rates.input + Decimal(usage.cacheRead) * (rates.cached ?? 0)
                + Decimal(usage.cacheWrite) * (rates.writes ?? 0)
                + Decimal(usage.billableOutput) * rates.output) / 1_000_000)
    }
}
