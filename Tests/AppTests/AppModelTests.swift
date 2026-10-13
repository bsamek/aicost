import Foundation
import Testing
import CostCore
@testable import CodexCost

@MainActor struct AppModelTests {
    @Test func addsOpenCodeToLoaderTotals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let milliseconds = Int64(Date().addingTimeInterval(-10).timeIntervalSince1970 * 1000)
        let data = """
        {"model":{"providerID":"opencode","id":"claude-sonnet-4-6"},"tokens":{"input":1000,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":\(milliseconds),"completed":\(milliseconds + 100)}}
        """
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [root.appendingPathComponent("opencode.db").path,
                             "CREATE TABLE session_message(id TEXT,session_id TEXT,type TEXT,data TEXT); INSERT INTO session_message VALUES ('m','s','assistant','\(data)');"]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let model = AppModel(home: root, openCodeHome: root, pricingStore: try isolatedPricingStore(root))
        await model.refresh()
        #expect(model.summary?.today.total == Decimal(string: "0.003"))
        #expect(model.summary?.month.total == Decimal(string: "0.003"))
        #expect(model.summary?.today.models.first?.model == "opencode/claude-sonnet-4-6")
        #expect(model.fileCount == 1)
        #expect(model.error == nil)
    }
    @Test func openCodeHomeUsesXDGDataHome() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(AppModel.resolveOpenCodeHome(environment: [:], userHome: home).path == "/Users/example/.local/share/opencode")
        #expect(AppModel.resolveOpenCodeHome(environment: ["XDG_DATA_HOME": "~/data"], userHome: home).path == "/Users/example/data/opencode")
    }
    @Test func combinesClaudeAndCodexUsage() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codex = root.appendingPathComponent("codex")
        let claude = root.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: codex.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claude.appendingPathComponent("projects"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10))
        let codexRecords = """
        {"type":"session_meta","payload":{"id":"s"}}
        {"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}
        {"type":"event_msg","timestamp":"\(stamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"output_tokens":0},"last_token_usage":{"input_tokens":1000,"output_tokens":0}}}}
        """
        let claudeRecord = """
        {"type":"assistant","timestamp":"\(stamp)","sessionId":"s","message":{"id":"msg_one","model":"claude-opus-5","usage":{"input_tokens":1000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"output_tokens":0}}}
        """
        try Data(codexRecords.utf8).write(to: codex.appendingPathComponent("sessions/a.jsonl"))
        try Data(claudeRecord.utf8).write(to: claude.appendingPathComponent("projects/a.jsonl"))
        let model = AppModel(home: codex, claudeHome: claude, pricingStore: try isolatedPricingStore(root))
        await model.refresh()
        #expect(model.summary?.today.total == Decimal(string: "0.007"))
        #expect(model.summary?.month.total == Decimal(string: "0.007"))
        #expect(model.summary?.today.models.count == 2)
        #expect(model.fileCount == 2)
        #expect(model.error == nil)
    }
    @Test func piUsageFlowsIntoAppAlongsideExistingIntegrations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let codex = root.appendingPathComponent("codex")
        let pi = root.appendingPathComponent("pi")
        try FileManager.default.createDirectory(at: codex.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pi.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let milliseconds = Int64(Date().addingTimeInterval(-10).timeIntervalSince1970 * 1000)
        let records = """
        {"type":"session","version":3,"id":"session"}
        {"type":"message","id":"entry","message":{"role":"assistant","provider":"openai-codex","model":"gpt-6.1-sol","timestamp":\(milliseconds),"usage":{"input":1000,"cacheRead":0,"cacheWrite":0,"output":0}}}
        """
        try Data(records.utf8).write(to: pi.appendingPathComponent("sessions/a.jsonl"))
        let model = AppModel(home: codex, piHome: pi, pricingStore: try isolatedPricingStore(root))
        await model.refresh()
        #expect(model.summary?.today.total == Decimal(string: "0.002"))
        #expect(model.summary?.month.total == Decimal(string: "0.002"))
        #expect(model.summary?.today.models.first?.model == "openai-codex/gpt-6.1-sol")
        #expect(model.fileCount == 1)
        #expect(model.error == nil)
    }
    @Test func piHomeOverrideResolvesTildeAndEmptyDefaults() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(AppModel.resolvePiHome(environment: [:], userHome: home).path == "/Users/example/.pi/agent")
        #expect(AppModel.resolvePiHome(environment: ["PI_CODING_AGENT_DIR": ""], userHome: home).path == "/Users/example/.pi/agent")
        #expect(AppModel.resolvePiHome(environment: ["PI_CODING_AGENT_DIR": "~/custom"], userHome: home).path == "/Users/example/custom")
    }
    @Test func claudeHomeOverrideResolvesTilde() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(AppModel.resolveClaudeHome(environment: [:], userHome: home).path == "/Users/example/.claude")
        #expect(AppModel.resolveClaudeHome(environment: ["CLAUDE_CONFIG_DIR": "~/custom"], userHome: home).path == "/Users/example/custom")
    }

    @Test func inaccessibleHomePreservesSuccessfulTotals() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10))
        let data = """
        {"type":"session_meta","payload":{"id":"s"}}
        {"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}
        {"type":"event_msg","timestamp":"\(stamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"output_tokens":0},"last_token_usage":{"input_tokens":1000,"output_tokens":0}}}}

        """
        try Data(data.utf8).write(to: home.appendingPathComponent("sessions/a.jsonl"))
        let model = AppModel(home: home, pricingStore: try isolatedPricingStore(home))
        await model.refresh()
        #expect(model.summary?.today.total == Decimal(string: "0.002"))
        let previous = model.lastRefreshed
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: home.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path) }
        await model.refresh()
        #expect(model.error != nil)
        #expect(model.summary?.today.total == Decimal(string: "0.002"))
        #expect(model.lastRefreshed == previous)
    }
    @Test func refreshRetainsSuccessfulTotalsAfterReadFailure() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = home.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = sessions.appendingPathComponent("usage.jsonl")
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10))
        let records = """
        {"type":"session_meta","payload":{"id":"s"}}
        {"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}
        {"type":"event_msg","timestamp":"\(stamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"output_tokens":0},"last_token_usage":{"input_tokens":1000,"output_tokens":0}}}}

        """
        try Data(records.utf8).write(to: file)
        let model = AppModel(home: home, pricingStore: try isolatedPricingStore(home))
        await model.refresh()
        #expect(model.summary?.today.total == Decimal(string: "0.002"))
        let successfulRefresh = try #require(model.lastRefreshed)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        await model.refresh()
        #expect(model.error != nil)
        #expect(model.summary?.today.total == Decimal(string: "0.002"))
        #expect(model.lastRefreshed == successfulRefresh)
        #expect(!model.isRefreshing)
    }
    @Test func firstFailureDoesNotShowZeroCost() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        try Data("not a directory".utf8).write(to: home.appendingPathComponent("sessions"))
        let model = AppModel(home: home, pricingStore: try isolatedPricingStore(home))
        await model.refresh()
        #expect(model.summary == nil)
        #expect(model.lastRefreshed == nil)
        #expect(model.error != nil)
    }
    @Test func codexHomeOverrideResolvesTilde() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(AppModel.resolveHome(environment: [:], userHome: home).path == "/Users/example/.codex")
        #expect(AppModel.resolveHome(environment: ["CODEX_HOME": "~/custom"], userHome: home).path == "/Users/example/custom")
    }

    @Test func appAndReportCatalogUseTheSamePersistedAPIPrices() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let store = PricingStore(cacheDirectory: cache, fetch: { _ in
            (Data("{\"openai\":{\"models\":{\"gpt-6.1-sol\":{\"cost\":{\"input\":3,\"output\":15}}}}}".utf8), 200)
        })
        #expect(await store.refreshIfNeeded())
        let stamp = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-10))
        let records = """
        {"type":"session_meta","payload":{"id":"s"}}
        {"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}
        {"type":"event_msg","timestamp":"\(stamp)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"output_tokens":0},"last_token_usage":{"input_tokens":1000,"output_tokens":0}}}}
        """
        try Data(records.utf8).write(to: root.appendingPathComponent("sessions/a.jsonl"))
        let model = AppModel(home: root, pricingStore: store)
        await model.refresh()
        #expect(model.summary?.today.total == Decimal(string: "0.003"))
        let pricing = try PricingStore.cachedCatalog(cacheDirectory: cache)
        let scan = try UsageScanner().scan(codexHome: root, claudeHome: nil)
        #expect(pricing.cost(for: scan.events[0]).usd == model.summary?.today.total)
        #expect(pricing.fetchedAt != nil)
    }
}

private func isolatedPricingStore(_ root: URL) throws -> PricingStore {
    let cache = root.appendingPathComponent("pricing-cache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try JSONEncoder().encode(Date()).write(to: cache.appendingPathComponent("last-attempt.json"))
    return PricingStore(cacheDirectory: cache, fetch: { _ in throw URLError(.notConnectedToInternet) })
}
