import Foundation
import Testing
@testable import CodexCost

@MainActor struct AppModelTests {
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
        let model = AppModel(home: home)
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
        let model = AppModel(home: home)
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
        let model = AppModel(home: home)
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
}
