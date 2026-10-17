import Foundation
import TestSupport
import Testing

@testable import CostCore

struct CodexScannerTests {
    @Test func differentActiveArchiveSnapshotsMergeBeforeComputingDeltas() throws {
        try withTemporaryDirectory { home in
            try write(
                codexLog([
                    codexMeta("s"), codexTokenCount(100),
                    codexTokenCount(200, second: 3, lastInput: 50),
                ]), home,
                "archived_sessions/a.jsonl")
            try write(
                codexLog([
                    codexMeta("s"), codexTokenCount(100),
                    codexTokenCount(150, second: 2, lastInput: 50),
                    codexTokenCount(200, second: 3, lastInput: 50),
                ]), home, "sessions/a.jsonl")
            let result = try CodexSessionScanner().scan(home: home)
            #expect(result.events.compactMap(\.codexUsage?.input).reduce(0, +) == 200)
        }
    }

    @Test func inheritedForkFillsParentSnapshotGapWithoutDoubleCounting() throws {
        try withTemporaryDirectory { home in
            try write(
                codexLog([
                    codexMeta("parent"), codexTokenCount(100),
                    codexTokenCount(200, second: 3, lastInput: 50),
                ]), home,
                "sessions/a.jsonl")
            try write(
                codexLog([
                    codexMeta("child", fork: "parent", timestamp: "2026-10-10T12:00:04Z"),
                    codexTokenCount(100), codexTokenCount(150, second: 2, lastInput: 50),
                    codexTokenCount(200, second: 3, lastInput: 50),
                    codexTokenCount(250, second: 5, lastInput: 50),
                ]), home, "sessions/b.jsonl")
            #expect(
                try CodexSessionScanner().scan(home: home).events.compactMap(\.codexUsage?.input)
                    .reduce(0, +) == 250
            )
        }
    }
    @Test func activeArchiveCopiesAndInheritedForkAreCountedOnce() throws {
        try withTemporaryDirectory { home in
            let parent = codexLog([
                codexMeta("parent"), codexContext("gpt-6.1-sol"), codexTokenCount(100),
            ])
            try write(parent, home, "sessions/parent.jsonl")
            try write(parent, home, "archived_sessions/copy.jsonl")
            let fork = codexLog([
                codexMeta("child", fork: "parent", timestamp: "2026-10-10T12:00:02Z"),
                codexContext("gpt-6.1-sol"), codexTokenCount(100),
                codexTokenCount(150, second: 3, lastInput: 50),
            ])
            try write(fork, home, "sessions/child.jsonl")
            let result = try CodexSessionScanner().scan(home: home)
            #expect(result.events.compactMap(\.codexUsage?.input).reduce(0, +) == 150)
            #expect(result.events.count == 2)
        }
    }

    @Test func paginatedForkAndIndependentSubagentRemainSeparate() throws {
        try withTemporaryDirectory { home in
            try write(
                codexLog([codexMeta("parent"), codexTokenCount(100)]), home, "sessions/a.jsonl")
            try write(
                codexLog([
                    codexMeta("child", fork: "parent", paginated: true),
                    codexTokenCount(40, second: 3),
                ]), home,
                "sessions/b.jsonl")
            // Distinct id must win over a shared session_id used by Codex subagents.
            var m = codexMeta("agent", fork: "parent", paginated: true)
            var payload = m["payload"] as! [String: Any]
            payload["session_id"] = "parent"
            m["payload"] = payload
            try write(codexLog([m, codexTokenCount(20, second: 4)]), home, "sessions/c.jsonl")
            let result = try CodexSessionScanner().scan(home: home)
            #expect(result.events.compactMap(\.codexUsage?.input).reduce(0, +) == 160)
            #expect(Set(result.events.map(\.sessionID)).count == 3)
        }
    }

    @Test func cacheTracksAppendTruncationAndDeletion() throws {
        try withTemporaryDirectory { home in
            let scanner = CodexSessionScanner()
            try write(codexLog([codexMeta("s"), codexTokenCount(100)]), home, "sessions/a.jsonl")
            #expect(try scanner.scan(home: home).events.first?.codexUsage?.input == 100)
            try write(
                codexLog([
                    codexMeta("s"), codexTokenCount(100),
                    codexTokenCount(150, second: 2, lastInput: 50),
                ]), home,
                "sessions/a.jsonl")
            #expect(try scanner.scan(home: home).events.count == 2)
            try write(codexLog([codexMeta("s"), codexTokenCount(20)]), home, "sessions/a.jsonl")
            #expect(try scanner.scan(home: home).events.first?.codexUsage?.input == 20)
            try FileManager.default.removeItem(at: home.appendingPathComponent("sessions/a.jsonl"))
            #expect(try scanner.scan(home: home).events.isEmpty)
        }
    }

    @Test func emptyHomeAndUnreadableLog() throws {
        try withTemporaryDirectory { home in
            #expect(try CodexSessionScanner().scan(home: home).events.isEmpty)
            try write(codexLog([codexMeta("s"), codexTokenCount(100)]), home, "sessions/a.jsonl")
            let path = home.appendingPathComponent("sessions/a.jsonl").path
            try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
            defer {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: path)
            }
            #expect(throws: (any Error).self) { try CodexSessionScanner().scan(home: home) }
        }
    }

    @Test func invalidDeltaInCopiedFilesIsDiagnosedOnce() throws {
        try withTemporaryDirectory { home in
            // Cached input decreases while input grows, so the second delta is invalid.
            let data = codexLog([
                codexMeta("s"), codexTokenCount(100, cached: 50),
                codexTokenCount(150, cached: 20, second: 2),
            ])
            try write(data, home, "sessions/a.jsonl")
            try write(data, home, "archived_sessions/a.jsonl")
            let result = try CodexSessionScanner().scan(home: home)
            #expect(result.events.compactMap(\.codexUsage?.input) == [100])
            #expect(result.diagnostics == 1)
        }
    }

    @Test func unresolvedForkBaselineIsFlagged() throws {
        try withTemporaryDirectory { home in
            try write(
                codexLog([
                    codexMeta("child", fork: "missing", paginated: true),
                    codexTokenCount(200, lastInput: 50),
                ]),
                home, "sessions/a.jsonl")
            let event = try #require(CodexSessionScanner().scan(home: home).events.first)
            #expect(event.issue != nil)
        }
    }
}
