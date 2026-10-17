import Foundation
import Testing

@testable import CostCore

// Removing cumulative deduplication, reset handling, or validation breaks these fixtures.
struct CodexParserTests {
    @Test func inheritedMetadataDoesNotReplaceOwningThread() {
        let result = parseCodex(
            codexLog([
                codexMeta("child", fork: "parent"), codexMeta("parent"),
                codexContext("gpt-6.1-sol"), codexTokenCount(100),
            ]))
        #expect(result.session.id == "child")
        #expect(result.session.parent == "parent")
        #expect(result.events.first?.sessionID == "child")
    }

    @Test func replayedOlderSnapshotDoesNotResetBaseline() {
        let result = parseCodex(
            codexLog([
                codexMeta("s"), codexTokenCount(100),
                codexTokenCount(150, second: 2, lastInput: 50),
                codexTokenCount(100), codexTokenCount(200, second: 3, lastInput: 50),
            ]))
        #expect(result.events.map(\.codexUsage?.input) == [100, 50, 50])
    }
    @Test func repeatedSnapshotsAndModelChanges() {
        let data = codexLog([
            codexMeta("s"), codexContext("gpt-6.1-sol"),
            codexTokenCount(100, cached: 20, output: 10),
            codexTokenCount(100, cached: 20, output: 10), codexContext("gpt-6-astra"),
            codexTokenCount(
                150, cached: 30, output: 15, second: 2, lastInput: 50, lastCached: 10, lastOutput: 5
            ),
        ])
        let result = parseCodex(data)
        #expect(result.events.count == 2)
        #expect(result.events.map(\.codexUsage?.input) == [100, 50])
        #expect(result.events.map(\.model) == ["gpt-6.1-sol", "gpt-6-astra"])
        #expect(result.events.last?.requestInput == 50)
    }

    @Test func counterReset() {
        let result = parseCodex(
            codexLog([codexMeta("s"), codexTokenCount(100), codexTokenCount(20, second: 2)]))
        #expect(result.events.map(\.codexUsage?.input) == [100, 20])
        #expect(result.events.first?.model == nil)
    }

    @Test func malformedAndNegativeRecordsDoNotEraseValidUsage() {
        let data =
            codexLog([codexMeta("s"), codexTokenCount(100), codexTokenCount(-1, second: 2)])
            + Data("bad json\n{\"unfinished\":".utf8)
        let result = parseCodex(data)
        #expect(result.events.count == 1)
        #expect(result.events.first?.codexUsage?.input == 100)
        #expect(result.diagnostics == 2)
    }

    @Test func missingTimestampAndInvalidCachedCountAreRejected() {
        var noTimestamp = codexTokenCount(100)
        noTimestamp.removeValue(forKey: "timestamp")
        let result = parseCodex(
            codexLog([codexMeta("s"), noTimestamp, codexTokenCount(100, cached: 101)]))
        #expect(result.events.isEmpty)
        #expect(result.diagnostics == 2)
    }

    @Test func accumulatedDeltaHasNoInventedRequestContext() {
        let result = parseCodex(
            codexLog([codexMeta("s"), codexTokenCount(300_000, lastInput: 150_000)]))
        #expect(result.events.first?.codexUsage?.input == 300_000)
        #expect(result.events.first?.requestInput == nil)
    }
}

/// Parses and normalizes one file alone, as the scanner does for an unmerged session.
private func parseCodex(_ data: Data) -> (
    session: CodexSession, events: [UsageEvent], diagnostics: Int
) {
    let session = CodexSessionParser.parse(data: data, fileID: "f")
    var diagnostics = session.diagnostics
    let events = CodexSessionParser.normalize(session, diagnostics: &diagnostics)
    return (session, events, diagnostics)
}
