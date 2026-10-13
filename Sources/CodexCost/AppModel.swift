import CostCore
import Foundation
import SwiftUI

struct LoadedUsage: Sendable {
    let summary: CostSummary
    let diagnostics: Int
    let fileCount: Int
    let verifiedAt: String
}
actor UsageLoader {
    private let scanner = UsageScanner()
    private let home: URL
    private let claudeHome: URL?
    private let piHome: URL?
    private let openCodeHome: URL?
    init(home: URL, claudeHome: URL?, piHome: URL? = nil, openCodeHome: URL? = nil) {
        self.home = home
        self.claudeHome = claudeHome
        self.piHome = piHome
        self.openCodeHome = openCodeHome
    }
    func load(now: Date, calendar: Calendar) throws -> LoadedUsage {
        let pricing = try PricingCatalog.load()
        let scan = try scanner.scan(
            codexHome: home, claudeHome: claudeHome, piHome: piHome, openCodeHome: openCodeHome)
        return LoadedUsage(
            summary: SummaryBuilder.build(
                events: scan.events, now: now, calendar: calendar, pricing: pricing),
            diagnostics: scan.diagnostics, fileCount: scan.fileCount, verifiedAt: pricing.verifiedAt
        )
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

    init(home: URL, claudeHome: URL? = nil, piHome: URL? = nil, openCodeHome: URL? = nil) {
        loader = UsageLoader(
            home: home, claudeHome: claudeHome, piHome: piHome, openCodeHome: openCodeHome)
    }
    convenience init() {
        self.init(
            home: AppModel.resolveHome(), claudeHome: AppModel.resolveClaudeHome(),
            piHome: AppModel.resolvePiHome(), openCodeHome: AppModel.resolveOpenCodeHome())
    }

    nonisolated static func resolveHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let override = environment["CODEX_HOME"], !override.isEmpty else {
            return userHome.appendingPathComponent(".codex")
        }
        if override == "~" { return userHome }
        if override.hasPrefix("~/") {
            return userHome.appendingPathComponent(String(override.dropFirst(2)))
        }
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    nonisolated static func resolveClaudeHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let override = environment["CLAUDE_CONFIG_DIR"], !override.isEmpty else {
            return userHome.appendingPathComponent(".claude")
        }
        if override == "~" { return userHome }
        if override.hasPrefix("~/") {
            return userHome.appendingPathComponent(String(override.dropFirst(2)))
        }
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    nonisolated static func resolvePiHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let override = environment["PI_CODING_AGENT_DIR"], !override.isEmpty else {
            return userHome.appendingPathComponent(".pi/agent")
        }
        if override == "~" { return userHome }
        if override.hasPrefix("~/") {
            return userHome.appendingPathComponent(String(override.dropFirst(2)))
        }
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    nonisolated static func resolveOpenCodeHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let dataHome = environment["XDG_DATA_HOME"], !dataHome.isEmpty else {
            return userHome.appendingPathComponent(".local/share/opencode")
        }
        let root: URL
        if dataHome == "~" {
            root = userHome
        } else if dataHome.hasPrefix("~/") {
            root = userHome.appendingPathComponent(String(dataHome.dropFirst(2)))
        } else {
            root = URL(fileURLWithPath: dataHome, isDirectory: true)
        }
        return root.appendingPathComponent("opencode")
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

func dollars(_ value: Decimal) -> String {
    if value > 0 && value < Decimal(string: "0.01")! { return "<$0.01" }
    return value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
}
