import Foundation
import CostCore

// Read-only diagnostic report also makes packaged resource/accounting checks reproducible.
enum CostReport {
    static func printReport() throws {
        let args = CommandLine.arguments
        let now: Date
        if let index = args.firstIndex(of: "--at"), index + 1 < args.count {
            guard let date = ISO8601DateFormatter().date(from: args[index + 1]) else { throw ReportError.invalidDate }
            now = date
        } else { now = Date() }
        let pricing = try PricingCatalog.load()
        let scan = try UsageScanner().scan(codexHome: AppModel.resolveHome(), claudeHome: AppModel.resolveClaudeHome())
        let summary = SummaryBuilder.build(events: scan.events, now: now, calendar: .current, pricing: pricing)
        func period(_ cost: PeriodCost) -> [String: Any] {
            ["total": NSDecimalNumber(decimal: cost.total).stringValue,
             "unpriced": cost.unpricedCount,
             "models": cost.models.map { ["model": $0.model, "total": NSDecimalNumber(decimal: $0.total).stringValue, "unpriced": $0.unpricedCount] as [String: Any] }]
        }
        let report: [String: Any] = ["today": period(summary.today), "month": period(summary.month),
                                    "diagnostics": scan.diagnostics, "files": scan.fileCount, "asOf": ISO8601DateFormatter().string(from: now)]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
enum ReportError: LocalizedError {
    case invalidDate
    var errorDescription: String? { "Use an ISO 8601 timestamp after --at." }
}
