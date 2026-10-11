import SwiftUI
import CostCore

struct CostPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary = model.summary {
                period("Today", summary.today)
                Divider()
                period("This Month", summary.month)
            } else {
                Text(model.error == nil ? "Reading usage…" : "Usage unavailable")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 280)
    }

    private func period(_ title: String, _ value: PeriodCost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(dollars(value.total)).monospacedDigit()
                    .accessibilityLabel("\(title) total, \(dollars(value.total))")
            }.fontWeight(.semibold)
            ForEach(value.models.filter { $0.pricedCount > 0 }) { row in
                HStack {
                    Text(displayModel(row.model))
                    Spacer()
                    Text(dollars(row.total)).monospacedDigit()
                }.foregroundStyle(.secondary)
            }
        }
    }

    private func displayModel(_ model: String) -> String {
        switch model {
        case "gpt-6.1-sol": "GPT-6.1 Sol"
        case "gpt-6-sol": "GPT-6 Sol"
        case "gpt-6-astra": "GPT-6 Astra"
        case "gpt-6-luna": "GPT-6 Luna"
        case "gpt-5.6-sol": "GPT-5.6 Sol"
        case "gpt-5.6-terra": "GPT-5.6 Terra"
        default: model
        }
    }
}
