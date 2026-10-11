import Foundation
import Testing
@testable import CostCore

struct ScannerTests {
    @Test func testActiveArchiveCopiesAndInheritedForkAreCountedOnce() throws {
        let home = try temporaryHome(); defer { try? FileManager.default.removeItem(at: home) }
        let parent = fixture([meta("parent"), context("gpt-6.1-sol"), usage(100)])
        try write(parent, home, "sessions/parent.jsonl")
        try write(parent, home, "archived_sessions/copy.jsonl")
        let fork = fixture([
            meta("child", fork: "parent", timestamp: "2026-10-10T12:00:02Z"),
            context("gpt-6.1-sol"), usage(100), usage(150, second: 3, lastInput: 50)
        ])
        try write(fork, home, "sessions/child.jsonl")
        let result = try SessionScanner().scan(home: home)
        #expect(result.events.map(\.usage.input).reduce(0, +) == 150)
        #expect(result.events.count == 2)
    }

    @Test func testPaginatedForkAndIndependentSubagentRemainSeparate() throws {
        let home = try temporaryHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write(fixture([meta("parent"), usage(100)]), home, "sessions/a.jsonl")
        try write(fixture([meta("child", fork: "parent", paginated: true), usage(40, second: 3)]), home, "sessions/b.jsonl")
        // Distinct id must win over a shared session_id used by Codex subagents.
        var m = meta("agent", fork: "parent", paginated: true)
        var payload = m["payload"] as! [String: Any]; payload["session_id"] = "parent"; m["payload"] = payload
        try write(fixture([m, usage(20, second: 4)]), home, "sessions/c.jsonl")
        let result = try SessionScanner().scan(home: home)
        #expect(result.events.map(\.usage.input).reduce(0, +) == 160)
        #expect(Set(result.events.map(\.sessionID)).count == 3)
    }

    @Test func testCacheTracksAppendTruncationAndDeletion() throws {
        let home = try temporaryHome(); defer { try? FileManager.default.removeItem(at: home) }
        let scanner = SessionScanner()
        try write(fixture([meta("s"), usage(100)]), home, "sessions/a.jsonl")
        #expect(try scanner.scan(home: home).events.first?.usage.input == 100)
        try write(fixture([meta("s"), usage(100), usage(150, second: 2, lastInput: 50)]), home, "sessions/a.jsonl")
        #expect(try scanner.scan(home: home).events.count == 2)
        try write(fixture([meta("s"), usage(20)]), home, "sessions/a.jsonl")
        #expect(try scanner.scan(home: home).events.first?.usage.input == 20)
        try FileManager.default.removeItem(at: home.appendingPathComponent("sessions/a.jsonl"))
        #expect(try scanner.scan(home: home).events.isEmpty)
    }

    @Test func testEmptyHomeAndUnreadableLog() throws {
        let home = try temporaryHome(); defer { try? FileManager.default.removeItem(at: home) }
        #expect(try SessionScanner().scan(home: home).events.isEmpty)
        try write(fixture([meta("s"), usage(100)]), home, "sessions/a.jsonl")
        let path = home.appendingPathComponent("sessions/a.jsonl").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        #expect(throws: (any Error).self) { try SessionScanner().scan(home: home) }
    }

    @Test func testUnresolvedForkBaselineIsFlagged() throws {
        let home = try temporaryHome(); defer { try? FileManager.default.removeItem(at: home) }
        try write(fixture([meta("child", fork: "missing", paginated: true), usage(200, lastInput: 50)]), home, "sessions/a.jsonl")
        let event = try #require(SessionScanner().scan(home: home).events.first)
        #expect(event.issue != nil)
    }
}
func temporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-cost-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func write(_ data: Data, _ home: URL, _ relative: String) throws {
    let url = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}
