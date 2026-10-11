import SwiftUI
import CostCore

struct CostPanel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Codex Cost").font(.system(size: 14, weight: .semibold))
                Spacer()
                if model.isRefreshing { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 16, height: 16) }
            }.padding(.bottom, 18)
            if let summary = model.summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        period("Today", summary.today)
                        Divider()
                        period("This Month", summary.month)
                    }
                }.frame(maxHeight: 360)
                if model.fileCount == 0 {
                    Text("No local Codex sessions found.").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                }
            } else {
                Text(model.error == nil ? "Reading Codex usage…" : "Usage unavailable")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 24)
            }
            if let error = model.error {
                Text(error + (model.summary == nil ? "" : "\nShowing the last successful totals."))
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
            if model.diagnostics > 0 {
                Text("\(model.diagnostics) unreadable records were skipped; totals may be incomplete.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            }
            Divider().padding(.vertical, 14)
            Text("Estimated API token cost for Codex usage recorded on this Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let date = model.pricingDate {
                Text("Standard rates · \(date)").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 4)
            }
            HStack(spacing: 12) {
                if let date = model.lastRefreshed {
                    Text("Updated \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.isRefreshing)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }.buttonStyle(.borderless).font(.system(size: 11)).padding(.top, 14)
        }.padding(18).frame(width: 340)
    }
    private func period(_ title: String, _ value: PeriodCost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(dollars(value.total)).font(.system(size: 25, weight: .semibold)).monospacedDigit()
                    .accessibilityLabel("\(title) total, \(dollars(value.total))")
            }
            ForEach(value.models) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(displayModel(row.model)).font(.system(size: 12)).lineLimit(1).help(row.model)
                    Spacer()
                    if row.pricedCount == 0 && row.unpricedCount > 0 {
                        Text("Unpriced").foregroundStyle(.secondary)
                    } else {
                        Text(dollars(row.total) + (row.unpricedCount > 0 ? "*" : "")).monospacedDigit()
                    }
                }.font(.system(size: 12))
                .help(row.reasons.sorted().joined(separator: "; "))
            }
            if value.unpricedCount > 0 {
                Text("\(value.unpricedCount) usage \(value.unpricedCount == 1 ? "record" : "records") excluded from the total.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
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
