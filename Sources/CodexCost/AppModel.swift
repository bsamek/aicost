import Foundation
import SwiftUI
import CostCore

struct LoadedUsage: Sendable {
    let summary: CostSummary
    let diagnostics: Int
    let fileCount: Int
    let verifiedAt: String
}
actor UsageLoader {
    private let scanner = SessionScanner()
    private let home: URL
    init(home: URL) { self.home = home }
    func load(now: Date, calendar: Calendar) throws -> LoadedUsage {
        let pricing = try PricingCatalog.load()
        let scan = try scanner.scan(home: home)
        return LoadedUsage(summary: SummaryBuilder.build(events: scan.events, now: now, calendar: calendar, pricing: pricing),
                           diagnostics: scan.diagnostics, fileCount: scan.fileCount, verifiedAt: pricing.verifiedAt)
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var summary: CostSummary?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var error: String?
    @Published private(set) var diagnostics = 0
    @Published private(set) var fileCount = 0
    @Published private(set) var pricingDate: String?
    private let loader: UsageLoader

    init(home: URL = AppModel.resolveHome()) { loader = UsageLoader(home: home) }

    nonisolated static func resolveHome(environment: [String: String] = ProcessInfo.processInfo.environment,
                                        userHome: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        guard let override = environment["CODEX_HOME"], !override.isEmpty else { return userHome.appendingPathComponent(".codex") }
        if override == "~" { return userHome }
        if override.hasPrefix("~/") { return userHome.appendingPathComponent(String(override.dropFirst(2))) }
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let now = Date()
        do {
            let loaded = try await loader.load(now: now, calendar: .current)
            summary = loaded.summary; diagnostics = loaded.diagnostics; fileCount = loaded.fileCount
            pricingDate = loaded.verifiedAt; lastRefreshed = now; error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

func dollars(_ value: Decimal) -> String {
    value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
}
