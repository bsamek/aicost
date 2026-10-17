import Foundation
import Testing

@testable import CostCore

struct CodexScannerTests {
    @Test func differentActiveArchiveSnapshotsMergeBeforeComputingDeltas() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            fixture([meta("s"), usage(100), usage(200, second: 3, lastInput: 50)]), home,
            "archived_sessions/a.jsonl")
        try write(
            fixture([
                meta("s"), usage(100), usage(150, second: 2, lastInput: 50),
                usage(200, second: 3, lastInput: 50),
            ]), home, "sessions/a.jsonl")
        let result = try CodexSessionScanner().scan(home: home)
        #expect(result.events.compactMap(\.codexUsage?.input).reduce(0, +) == 200)
    }

    @Test func inheritedForkFillsParentSnapshotGapWithoutDoubleCounting() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            fixture([meta("parent"), usage(100), usage(200, second: 3, lastInput: 50)]), home,
            "sessions/a.jsonl")
        try write(
            fixture([
                meta("child", fork: "parent", timestamp: "2026-10-10T12:00:04Z"),
                usage(100), usage(150, second: 2, lastInput: 50),
                usage(200, second: 3, lastInput: 50),
                usage(250, second: 5, lastInput: 50),
            ]), home, "sessions/b.jsonl")
        #expect(
            try CodexSessionScanner().scan(home: home).events.compactMap(\.codexUsage?.input)
                .reduce(0, +) == 250
        )
    }
    @Test func activeArchiveCopiesAndInheritedForkAreCountedOnce() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let parent = fixture([meta("parent"), context("gpt-6.1-sol"), usage(100)])
        try write(parent, home, "sessions/parent.jsonl")
        try write(parent, home, "archived_sessions/copy.jsonl")
        let fork = fixture([
            meta("child", fork: "parent", timestamp: "2026-10-10T12:00:02Z"),
            context("gpt-6.1-sol"), usage(100), usage(150, second: 3, lastInput: 50),
        ])
        try write(fork, home, "sessions/child.jsonl")
        let result = try CodexSessionScanner().scan(home: home)
        #expect(result.events.compactMap(\.codexUsage?.input).reduce(0, +) == 150)
        #expect(result.events.count == 2)
    }

    @Test func paginatedForkAndIndependentSubagentRemainSeparate() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(fixture([meta("parent"), usage(100)]), home, "sessions/a.jsonl")
        try write(
            fixture([meta("child", fork: "parent", paginated: true), usage(40, second: 3)]), home,
            "sessions/b.jsonl")
        // Distinct id must win over a shared session_id used by Codex subagents.
        var m = meta("agent", fork: "parent", paginated: true)
        var payload = m["payload"] as! [String: Any]
        payload["session_id"] = "parent"
        m["payload"] = payload
        try write(fixture([m, usage(20, second: 4)]), home, "sessions/c.jsonl")
        let result = try CodexSessionScanner().scan(home: home)
        #expect(result.events.compactMap(\.codexUsage?.input).reduce(0, +) == 160)
        #expect(Set(result.events.map(\.sessionID)).count == 3)
    }

    @Test func cacheTracksAppendTruncationAndDeletion() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let scanner = CodexSessionScanner()
        try write(fixture([meta("s"), usage(100)]), home, "sessions/a.jsonl")
        #expect(try scanner.scan(home: home).events.first?.codexUsage?.input == 100)
        try write(
            fixture([meta("s"), usage(100), usage(150, second: 2, lastInput: 50)]), home,
            "sessions/a.jsonl")
        #expect(try scanner.scan(home: home).events.count == 2)
        try write(fixture([meta("s"), usage(20)]), home, "sessions/a.jsonl")
        #expect(try scanner.scan(home: home).events.first?.codexUsage?.input == 20)
        try FileManager.default.removeItem(at: home.appendingPathComponent("sessions/a.jsonl"))
        #expect(try scanner.scan(home: home).events.isEmpty)
    }

    @Test func emptyHomeAndUnreadableLog() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(try CodexSessionScanner().scan(home: home).events.isEmpty)
        try write(fixture([meta("s"), usage(100)]), home, "sessions/a.jsonl")
        let path = home.appendingPathComponent("sessions/a.jsonl").path
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
        #expect(throws: (any Error).self) { try CodexSessionScanner().scan(home: home) }
    }

    @Test func invalidDeltaInCopiedFilesIsDiagnosedOnce() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        // Cached input decreases while input grows, so the second delta is invalid.
        let data = fixture([meta("s"), usage(100, cached: 50), usage(150, cached: 20, second: 2)])
        try write(data, home, "sessions/a.jsonl")
        try write(data, home, "archived_sessions/a.jsonl")
        let result = try CodexSessionScanner().scan(home: home)
        #expect(result.events.compactMap(\.codexUsage?.input) == [100])
        #expect(result.diagnostics == 1)
    }

    @Test func unresolvedForkBaselineIsFlagged() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(
            fixture([meta("child", fork: "missing", paginated: true), usage(200, lastInput: 50)]),
            home, "sessions/a.jsonl")
        let event = try #require(CodexSessionScanner().scan(home: home).events.first)
        #expect(event.issue != nil)
    }
}
func temporaryHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "codex-cost-tests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
func write(_ data: Data, _ home: URL, _ relative: String) throws {
    let url = home.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}
