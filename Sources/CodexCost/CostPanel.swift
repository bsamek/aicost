import SwiftUI
import CostCore

// Select the property wrapper explicitly on SDKs that also export a State macro.
private typealias PanelState<Value> = SwiftUI.State<Value>

struct CostPanel: View {
    @ObservedObject var model: AppModel
    let restart: () -> Bool
    let quit: () -> Void
    @PanelState private var isRestarting = false

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
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button("Restart") {
                    isRestarting = true
                    isRestarting = restart()
                }
                Button("Quit", action: quit)
            }
            .disabled(isRestarting)
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
        case "claude-opus-5": "Claude Opus 5"
        case "claude-opus-4-8": "Claude Opus 4.8"
        case "claude-fable-5": "Claude Fable 5"
        case "claude-fable-5-1": "Claude Fable 5.1"
        case "claude-sonnet-5-5": "Claude Sonnet 5.5"
        case "claude-opus-5-5": "Claude Opus 5.5"
        case "claude-haiku-5-5": "Claude Haiku 5.5"
        default: model
        }
    }
}
