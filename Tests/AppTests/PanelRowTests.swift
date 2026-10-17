import Foundation
import Testing

@testable import CodexCost
@testable import CostCore

struct PanelRowTests {
    @Test func unpricedReleaseStaysVisibleAndSeparateFromPricedModel() throws {
        let period = PeriodCost(
            total: Decimal(string: "0.42")!,
            models: [
                ModelCost(
                    model: "fireworks/accounts/fireworks/models/deepseek-v4p1-flash",
                    total: Decimal(string: "0.42")!, pricedCount: 3),
                ModelCost(
                    model: "openrouter/deepseek/deepseek-v4.1-flash-1017", unpricedCount: 16,
                    reasons: ["OpenCode rate unavailable"]),
            ], unpricedCount: 16)
        let rows = PanelRow.rows(period)
        #expect(rows.map(\.name) == ["DeepSeek V4.1 Flash", "DeepSeek V4.1 Flash 1017"])
        #expect(rows[0].amount == "$0.42")
        // A missing rate must say so, never disappear or read as $0.00.
        #expect(rows[1].amount == "Unpriced")
        #expect(rows[1].detail == "OpenRouter: unpriced (16 requests)")
    }

    @Test func partlyUnpricedModelsShowPricedCostAndNoteTheRest() {
        let period = PeriodCost(models: [
            ModelCost(model: "gpt-6.1-sol", total: 27, pricedCount: 40, unpricedCount: 1),
            ModelCost(model: "openai-codex/gpt-6.1-sol", total: 0, pricedCount: 1),
        ])
        let row = PanelRow.rows(period)[0]
        #expect(row.amount == "$27.00")
        #expect(row.detail == "Codex: $27.00 + 1 request unpriced\nPi · ChatGPT: $0.00")
    }
}
