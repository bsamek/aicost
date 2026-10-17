import Foundation
import Testing

@testable import CostCore

struct DisplayedModelsTests {
    @Test func rowsForTheSameModelCombineWithoutChangingSourceRows() throws {
        let raw = [
            ModelCost(model: "claude-haiku-5-5", total: 1, pricedCount: 1),
            ModelCost(
                model: "fireworks-ai/accounts/fireworks/models/deepseek-v4p1-flash",
                total: Decimal(string: "0.215900484")!, pricedCount: 87),
            ModelCost(
                model: "fireworks/accounts/fireworks/models/deepseek-v4p1-flash",
                total: Decimal(string: "0.0027093")!, pricedCount: 1,
                unpricedCount: 1, reasons: ["Pi cache-write rate unavailable"]),
            ModelCost(model: "gpt-6-astra", total: 2, pricedCount: 1),
        ]
        let period = PeriodCost(
            total: Decimal(string: "3.218609784")!, models: raw, unpricedCount: 1)
        let shown = period.displayedModels
        #expect(shown.map(\.model) == ["Claude Haiku 5.5", "DeepSeek V4.1 Flash", "GPT-6 Astra"])
        let deepseek = shown[1]
        #expect(deepseek.total == Decimal(string: "0.218609784"))
        #expect(deepseek.pricedCount == 88)
        #expect(deepseek.unpricedCount == 1)
        #expect(deepseek.reasons == ["Pi cache-write rate unavailable"])
        #expect(deepseek.sources.map(\.model) == [raw[1].model, raw[2].model])
        #expect(shown.reduce(Decimal.zero) { $0 + $1.total } == period.total)
        #expect(period.models.count == 4)
        #expect(period.models[1].model.hasPrefix("fireworks-ai/"))
        #expect(period.models[1].total == Decimal(string: "0.215900484"))
    }

    @Test func agentsAndProvidersCombineButDistinctModelsStaySeparate() {
        let ids = [
            "gpt-6.1-sol", "openai-codex/gpt-6.1-sol", "openai/gpt-6.1-sol",
            "fireworks-ai/accounts/fireworks/models/glm-5p3-flash",
            "fireworks-ai/accounts/fireworks/routers/glm-5p3-fast",
            "fireworks-ai/accounts/fireworks/models/deepseek-v4p1-flash",
            "openrouter/deepseek/deepseek-v4.1-flash-1017",
        ]
        let period = PeriodCost(models: ids.map { ModelCost(model: $0, total: 1, pricedCount: 1) })
        #expect(
            period.displayedModels.map(\.model) == [
                "GPT-6.1 Sol", "GLM 5.3 Flash", "GLM 5.3 Fast", "DeepSeek V4.1 Flash",
                "DeepSeek V4.1 Flash 1017",
            ])
        #expect(period.displayedModels.first?.total == 3)
        #expect(period.models.count == 7)
    }
}
