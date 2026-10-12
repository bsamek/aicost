import Foundation

public struct ModelCost: Identifiable, Sendable {
    public var model: String
    public var total: Decimal = 0
    public var pricedCount: Int = 0
    public var unpricedCount: Int = 0
    public var reasons: Set<String> = []
    public var id: String { model }
}
public struct PeriodCost: Sendable {
    public var total: Decimal = 0
    public var models: [ModelCost] = []
    public var unpricedCount: Int = 0
}
public struct CostSummary: Sendable {
    public var today: PeriodCost
    public var month: PeriodCost
}
public enum SummaryBuilder {
    public static func build(events: [UsageEvent], now: Date, calendar: Calendar, pricing: PricingCatalog) -> CostSummary {
        let day = calendar.dateInterval(of: .day, for: now)!
        let month = calendar.dateInterval(of: .month, for: now)!
        func period(_ interval: DateInterval) -> PeriodCost {
            var rows: [String: ModelCost] = [:]
            var result = PeriodCost()
            for event in events where event.timestamp >= interval.start && event.timestamp < interval.end && event.timestamp <= now {
                let name = event.model ?? "Unknown model"
                var row = rows[name] ?? ModelCost(model: name)
                let cost = pricing.cost(for: event)
                if let usd = cost.usd {
                    result.total += usd; row.total += usd; row.pricedCount += 1
                } else {
                    result.unpricedCount += 1; row.unpricedCount += 1
                    row.reasons.insert(cost.reason ?? "Unavailable")
                }
                rows[name] = row
            }
            result.models = rows.values.map { (row: $0, order: ModelOrder(model: $0.model)) }
                .sorted { $0.order < $1.order }.map(\.row)
            return result
        }
        return CostSummary(today: period(day), month: period(month))
    }
}
