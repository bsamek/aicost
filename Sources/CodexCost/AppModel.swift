import CostCore
import Foundation
import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var summary: CostSummary?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var error: String?
    @Published private(set) var diagnostics = 0
    @Published private(set) var fileCount = 0
    @Published private(set) var pricingDate: String?
    private let loader: UsageLoader

    init(sources: UsageSources = .resolve(), pricingStore: PricingStore = PricingStore()) {
        loader = UsageLoader(sources: sources, pricingStore: pricingStore)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let now = Date()
        do {
            let loaded = try await loader.load(now: now, calendar: .current)
            summary = loaded.summary
            diagnostics = loaded.diagnostics
            fileCount = loaded.fileCount
            pricingDate = loaded.verifiedAt
            lastRefreshed = now
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
