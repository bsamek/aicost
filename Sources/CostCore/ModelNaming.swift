import Foundation

/// Provider aliases and readable model names shared by pricing, ordering, and display.
/// Raw provider/model IDs remain the accounting identity everywhere else.
public enum ModelNaming {
    /// models.dev provider IDs for names agents record for the same Standard API rates.
    static func pricingProvider(_ provider: String) -> String {
        switch provider {
        case "openai-codex": "openai"
        case "fireworks": "fireworks-ai"
        default: provider
        }
    }

    /// Serving providers recognized for row ordering, keyed by their pricing provider ID.
    static func orderingProvider(_ namespace: String) -> String? {
        let provider = pricingProvider(namespace)
        let known = [
            "anthropic", "fireworks-ai", "openai", "opencode", "opencode-go", "openrouter",
        ]
        return known.contains(provider) ? provider : nil
    }

    /// A readable model name for a summary row, without the agent or serving provider.
    /// Rows that name the same model share a label, so the panel shows one line per model.
    public static func displayName(_ row: String) -> String {
        // Prefixed rows end in the model slug, e.g. `fireworks-ai/accounts/fireworks/routers/glm-5p3-fast`.
        let name = row.split(separator: "/").last.map(String.init) ?? row
        if let match = ModelOrder.capture(
            "^claude-(fable|haiku|opus|sonnet)-([0-9]+)(?:-([0-9]{1,2}))?$", in: name)
        {
            let version = match[3].isEmpty ? match[2] : match[2] + "." + match[3]
            return "Claude \(match[1].capitalized) \(version)"
        }
        if let match = ModelOrder.capture(
            "^gpt-([0-9]+(?:\\.[0-9]+)?)((?:-(?:astra|luna|sol|terra|mini|nano|pro|codex))*)$",
            in: name)
        {
            let suffixes = match[2].split(separator: "-").map { $0.capitalized }
            return (["GPT-" + match[1]] + suffixes).joined(separator: " ")
        }
        // Fireworks writes versions as `v4p1`. A numeric release suffix names a distinct model.
        if let match = ModelOrder.capture(
            "^(deepseek|glm)-v?([0-9]+(?:[p.][0-9]+)?)((?:-(?:flash|fast|air|pro))*)(?:-([0-9]{4,8}))?$",
            in: name)
        {
            let family = match[1] == "glm" ? "GLM" : "DeepSeek"
            let version =
                (match[1] == "deepseek" ? "V" : "")
                + match[2].replacingOccurrences(of: "p", with: ".")
            let suffixes = match[3].split(separator: "-").map { $0.capitalized }
            let release = match[4].isEmpty ? [] : [match[4]]
            return ([family, version] + suffixes + release).joined(separator: " ")
        }
        return name
    }

    /// Where a row's usage came from: the serving provider for prefixed rows, or the agent
    /// for bare IDs, which only Codex and Claude Code record.
    public static func source(_ row: String) -> String {
        let parts = row.split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return row.hasPrefix("claude-") ? "Claude Code" : "Codex" }
        switch parts[0] {
        case "anthropic": return "Anthropic"
        case "openai": return "OpenAI"
        // Only Pi records the `openai-codex` provider, for ChatGPT sign-in.
        case "openai-codex": return "Pi · ChatGPT"
        case "fireworks", "fireworks-ai": return "Fireworks"
        case "openrouter": return "OpenRouter"
        case "opencode": return "OpenCode Zen"
        case "opencode-go": return "OpenCode Go"
        default: return String(parts[0])
        }
    }
}
