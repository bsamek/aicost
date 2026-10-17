import Foundation
import Testing

@testable import CostCore

struct ModelNamingTests {
    @Test func derivedNamesMatchPreviouslyHandWrittenLabels() {
        let expected = [
            "gpt-6.1-sol": "GPT-6.1 Sol", "gpt-6-sol": "GPT-6 Sol", "gpt-6-astra": "GPT-6 Astra",
            "gpt-6-luna": "GPT-6 Luna", "gpt-5.6-sol": "GPT-5.6 Sol",
            "gpt-5.6-terra": "GPT-5.6 Terra", "claude-opus-5": "Claude Opus 5",
            "claude-opus-4-8": "Claude Opus 4.8", "claude-fable-5": "Claude Fable 5",
            "claude-fable-5-1": "Claude Fable 5.1", "claude-sonnet-5-5": "Claude Sonnet 5.5",
            "claude-opus-5-5": "Claude Opus 5.5", "claude-haiku-5-5": "Claude Haiku 5.5",
        ]
        for (raw, label) in expected { #expect(ModelNaming.displayName(raw) == label) }
    }

    @Test func namesOmitAgentsAndServingProviders() {
        let expected = [
            "anthropic/claude-sonnet-5-5": "Claude Sonnet 5.5",
            "openai/gpt-6-sol": "GPT-6 Sol", "openai-codex/gpt-6.1-sol": "GPT-6.1 Sol",
            "opencode/claude-opus-5": "Claude Opus 5",
            "fireworks/accounts/fireworks/models/deepseek-v4p1-flash": "DeepSeek V4.1 Flash",
            "fireworks-ai/accounts/fireworks/models/glm-5p3-flash": "GLM 5.3 Flash",
            "fireworks-ai/accounts/fireworks/routers/glm-5p3-fast": "GLM 5.3 Fast",
            "openrouter/deepseek/deepseek-v4.1-flash-1017": "DeepSeek V4.1 Flash 1017",
        ]
        for (raw, label) in expected { #expect(ModelNaming.displayName(raw) == label) }
    }

    @Test func newReleasesGetReadableNamesAndUnknownIDsShowTheirSlug() {
        #expect(ModelNaming.displayName("claude-opus-6-1") == "Claude Opus 6.1")
        #expect(ModelNaming.displayName("gpt-5.4-mini") == "GPT-5.4 Mini")
        #expect(ModelNaming.displayName("gpt-7.2-sol") == "GPT-7.2 Sol")
        for raw in ["claude-sonnet-4-5-20250929", "o4-mini", "mystery", "Unknown model"] {
            #expect(ModelNaming.displayName(raw) == raw)
        }
        #expect(ModelNaming.displayName("fireworks-ai/accounts/acme/models/custom") == "custom")
    }

    @Test func sourcesNameTheProviderOrTheAgentForBareIDs() {
        #expect(ModelNaming.source("claude-opus-5-5") == "Claude Code")
        #expect(ModelNaming.source("gpt-6.1-sol") == "Codex")
        // OpenCode and Pi both record `anthropic/`, so the label must not claim either agent.
        #expect(ModelNaming.source("anthropic/claude-sonnet-5-5") == "Anthropic")
        #expect(ModelNaming.source("openai-codex/gpt-6.1-sol") == "Pi · ChatGPT")
        #expect(
            ModelNaming.source("fireworks/accounts/fireworks/models/glm-5p3-flash") == "Fireworks")
        #expect(
            ModelNaming.source("fireworks-ai/accounts/fireworks/models/glm-5p3-flash")
                == "Fireworks")
        #expect(ModelNaming.source("acme/model") == "acme")
    }

    @Test func pricingProviderAliasesMatchModelsDev() {
        #expect(ModelNaming.pricingProvider("openai-codex") == "openai")
        #expect(ModelNaming.pricingProvider("fireworks") == "fireworks-ai")
        #expect(ModelNaming.pricingProvider("opencode") == "opencode")
    }
}
