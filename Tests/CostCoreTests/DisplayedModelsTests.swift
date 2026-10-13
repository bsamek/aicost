import Foundation
import Testing

@testable import CostCore

struct DisplayedModelsTests {
    @Test func verifiedFireworksAliasesCombineWithoutChangingSourceRows() throws {
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
        #expect(
            shown.map(\.model) == [
                "claude-haiku-5-5",
                "fireworks/accounts/fireworks/models/deepseek-v4p1-flash", "gpt-6-astra",
            ])
        let deepseek = try #require(shown.first { $0.model.contains("deepseek") })
        #expect(deepseek.total == Decimal(string: "0.218609784"))
        #expect(deepseek.pricedCount == 88)
        #expect(deepseek.unpricedCount == 1)
        #expect(deepseek.reasons == ["Pi cache-write rate unavailable"])
        #expect(shown.reduce(Decimal.zero) { $0 + $1.total } == period.total)
        #expect(period.models.count == 4)
        #expect(period.models[1].model.hasPrefix("fireworks-ai/"))
        #expect(period.models[1].total == Decimal(string: "0.215900484"))
    }

    @Test func glmAliasesCombineButOtherProvidersAndUnknownModelsStaySeparate() {
        let ids = [
            "fireworks-ai/accounts/fireworks/models/glm-5p3-flash",
            "fireworks/accounts/fireworks/models/glm-5p3-flash",
            "openrouter/accounts/fireworks/models/glm-5p3-flash",
            "fireworks-ai/custom-model", "fireworks/custom-model",
        ]
        let period = PeriodCost(models: ids.map { ModelCost(model: $0, total: 1, pricedCount: 1) })
        #expect(period.displayedModels.map(\.model) == Array(ids.dropFirst()))
        #expect(period.displayedModels.first?.total == 2)
        #expect(period.models.count == 5)
    }
}
