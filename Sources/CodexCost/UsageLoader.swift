import CostCore
import Foundation

struct LoadedUsage: Sendable {
    let summary: CostSummary
    let diagnostics: Int
    let fileCount: Int
    let verifiedAt: String
}

/// Owns the scanners so accounting runs away from the main actor.
actor UsageLoader {
    private let scanner = UsageScanner()
    private let pricingStore: PricingStore
    private let sources: UsageSources
    init(sources: UsageSources, pricingStore: PricingStore) {
        self.sources = sources
        self.pricingStore = pricingStore
    }
    func load(now: Date, calendar: Calendar) async throws -> LoadedUsage {
        let pricing = try await pricingStore.catalog()
        // First show cached/bundled totals. The regular usage refresh picks up new rates.
        Task { await pricingStore.refreshIfNeeded(now: now) }
        let scan = try scanner.scan(sources)
        return LoadedUsage(
            summary: SummaryBuilder.build(
                events: scan.events, now: now, calendar: calendar, pricing: pricing),
            diagnostics: scan.diagnostics, fileCount: scan.fileCount, verifiedAt: pricing.verifiedAt
        )
    }
}
