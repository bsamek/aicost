import Foundation

@testable import CostCore

/// Bundled rates as of their October 10–12, 2026 verification, for parser and scanner tests.
/// Bundled price updates change `BundledPricingTests`, not accounting expectations.
func fixturePricing() throws -> PricingCatalog {
    try PricingCatalog(
        data: Data(
            """
            {"source":"fixture","verifiedAt":"2026-10-10","longContextThreshold":272000,"models":{
              "claude-opus-5":{"short":{"input":"5","cached":".50","output":"25","writes5m":"6.25","writes1h":"10"}},
              "claude-sonnet-5-5":{"short":{"input":"2","cached":".10","output":"10","writes5m":"2.50","writes1h":"4"}},
              "claude-haiku-5-5":{"longContextThreshold":100000,
                "short":{"input":".10","cached":".01","output":".50","writes5m":"0.1250","writes1h":"0.20"},
                "long":{"input":".50","cached":".05","output":"2.50","writes5m":".625","writes1h":"1"}},
              "gpt-6.1-sol":{"short":{"input":"2.00","cached":"0.10","writes":"2.50","output":"10.00"},
                "long":{"input":"4.00","cached":"0.20","writes":"5.00","output":"15.00"}},
              "gpt-6-astra":{"short":{"input":"10.00","cached":"1.00","writes":"12.50","output":"50.00"},
                "long":{"input":"20.00","cached":"2.00","writes":"25.00","output":"75.00"}}
            }}
            """.utf8),
        piData: Data(
            """
            {"source":"fixture","verifiedAt":"2026-10-12","longContextThreshold":272000,"models":{
              "fireworks/accounts/fireworks/models/deepseek-v4p1-flash":{"short":{"input":"0.30","cached":"0.006","output":"1.20"}},
              "fireworks/accounts/fireworks/models/glm-5p3-flash":{"short":{"input":"0.15","cached":"0.03","output":"0.50"}}
            }}
            """.utf8),
        openCodeData: Data(
            """
            {"source":"fixture","verifiedAt":"2026-10-12","models":{
              "opencode/claude-sonnet-4-6":{"short":{"input":"3","cached":".30","writes":"3.75","output":"15"}},
              "opencode/gpt-5.1":{"short":{"input":"1.07","cached":".107","writes":null,"output":"8.50"}},
              "openai/gpt-5.1":{"short":{"input":"1.25","cached":"0.125","writes":null,"output":"10.00"}},
              "opencode/big-pickle":{"short":{"input":"0","cached":"0","writes":null,"output":"0"}},
              "fireworks-ai/accounts/fireworks/models/deepseek-v4p1-flash":{"short":{"input":".30","cached":".006","writes":null,"output":"1.20"}},
              "opencode/gpt-5.6-luna":{"longContextThreshold":272000,
                "short":{"input":".20","cached":".02","writes":".25","output":"1.20"},
                "long":{"input":"0.40","cached":"0.04","writes":"0.50","output":"1.800"}}
            }}
            """.utf8))
}

/// Two Codex models: one flat, one with a long-context tier.
func testPricing() throws -> PricingCatalog {
    try PricingCatalog(
        data: Data(
            """
            {"source":"fixture","verifiedAt":"2026-10-10","longContextThreshold":272000,"models":{
                "plain":{"short":{"input":"2","cached":"0.10","output":"10"}},
                "tiered":{"short":{"input":"2","cached":"0.10","output":"10"},"long":{"input":"4","cached":"0.20","output":"15"}}
            }}
            """.utf8))
}

func testEvent(
    model: String? = "plain", usage: TokenUsage = TokenUsage(input: 1_000_000),
    timestamp: String = "2026-10-10T12:00:00Z"
) -> UsageEvent {
    UsageEvent(
        identity: UUID().uuidString, sessionID: "s",
        timestamp: ISO8601DateFormatter().date(from: timestamp)!, model: model,
        usage: .codex(usage),
        requestInput: usage.input)
}
