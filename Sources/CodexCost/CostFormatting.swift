import CostCore
import Foundation

func dollars(_ value: Decimal) -> String {
    if value > 0 && value < Decimal(string: "0.01")! { return "<$0.01" }
    return value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
}

/// One panel line per model. Models without published rates stay visible and say so,
/// rather than disappearing or reading as free.
struct PanelRow: Identifiable {
    let name: String
    let amount: String
    /// Agents and serving providers stay out of the row and appear on hover.
    let detail: String
    var id: String { name }

    static func rows(_ period: PeriodCost) -> [PanelRow] {
        period.displayedModels.map { row in
            var lines: [(source: String, total: Decimal, unpriced: Int)] = []
            for source in row.sources {
                let name = ModelNaming.source(source.model)
                if let index = lines.firstIndex(where: { $0.source == name }) {
                    lines[index].total += source.total
                    lines[index].unpriced += source.unpricedCount
                } else {
                    lines.append((name, source.total, source.unpricedCount))
                }
            }
            let detail = lines.map { line in
                let requests = line.unpriced == 1 ? "1 request" : "\(line.unpriced) requests"
                return line.total == 0 && line.unpriced > 0
                    ? "\(line.source): unpriced (\(requests))"
                    : "\(line.source): \(dollars(line.total))"
                        + (line.unpriced > 0 ? " + \(requests) unpriced" : "")
            }
            return PanelRow(
                name: row.model, amount: row.pricedCount > 0 ? dollars(row.total) : "Unpriced",
                detail: detail.joined(separator: "\n"))
        }
    }
}
