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

    /// Verified identical Fireworks models that Pi (`fireworks`) and OpenCode (`fireworks-ai`)
    /// record under different provider names. Display combines them; accounting does not.
    static func displayRow(_ row: String) -> String {
        switch row {
        case "fireworks-ai/accounts/fireworks/models/deepseek-v4p1-flash",
            "fireworks-ai/accounts/fireworks/models/glm-5p3-flash":
            "fireworks/" + row.dropFirst("fireworks-ai/".count)
        default: row
        }
    }

    /// A readable label for a summary row, falling back to the raw ID.
    public static func displayName(_ row: String) -> String {
        // Bare IDs come from Codex and Claude Code; prefixes distinguish routed providers.
        for (prefix, label) in [
            ("openai-codex/", "Pi"), ("openai/", "OpenAI"), ("anthropic/", "Anthropic"),
        ] where row.hasPrefix(prefix) {
            return label + " · " + displayName(String(row.dropFirst(prefix.count)))
        }
        switch row {
        case "fireworks/accounts/fireworks/models/deepseek-v4p1-flash":
            return "DeepSeek V4.1 Flash · Fireworks"
        case "fireworks/accounts/fireworks/models/glm-5p3-flash":
            return "GLM 5.3 Flash · Fireworks"
        default: break
        }
        if let match = ModelOrder.capture(
            "^claude-(fable|haiku|opus|sonnet)-([0-9]+)(?:-([0-9]{1,2}))?$", in: row)
        {
            let version = match[3].isEmpty ? match[2] : match[2] + "." + match[3]
            return "Claude \(match[1].capitalized) \(version)"
        }
        if let match = ModelOrder.capture(
            "^gpt-([0-9]+(?:\\.[0-9]+)?)((?:-(?:astra|luna|sol|terra|mini|nano|pro|codex))*)$",
            in: row)
        {
            let suffixes = match[2].split(separator: "-").map { $0.capitalized }
            return (["GPT-" + match[1]] + suffixes).joined(separator: " ")
        }
        return row
    }
}
