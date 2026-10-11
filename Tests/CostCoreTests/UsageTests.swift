import Foundation
import Testing
@testable import CostCore

// Removing cumulative deduplication, reset handling, or validation breaks these fixtures.
struct UsageTests {
    @Test func testReplayedOlderSnapshotDoesNotResetBaseline() {
        let result = SessionParser.parse(data: fixture([
            meta("s"), usage(100), usage(150, second: 2, lastInput: 50),
            usage(100), usage(200, second: 3, lastInput: 50)
        ]), fileID: "f")
        #expect(result.events.map(\.usage.input) == [100, 50, 50])
    }
    @Test func testRepeatedSnapshotsAndModelChanges() {
        let data = fixture([
            meta("s"), context("gpt-6.1-sol"), usage(100, cached: 20, output: 10),
            usage(100, cached: 20, output: 10), context("gpt-6-astra"),
            usage(150, cached: 30, output: 15, second: 2, lastInput: 50, lastCached: 10, lastOutput: 5)
        ])
        let result = SessionParser.parse(data: data, fileID: "file")
        #expect(result.events.count == 2)
        #expect(result.events.map(\.usage.input) == [100, 50])
        #expect(result.events.map(\.model) == ["gpt-6.1-sol", "gpt-6-astra"])
        #expect(result.events.last?.requestInput == 50)
    }

    @Test func testCounterReset() {
        let result = SessionParser.parse(data: fixture([meta("s"), usage(100), usage(20, second: 2)]), fileID: "f")
        #expect(result.events.map(\.usage.input) == [100, 20])
        #expect(result.events.first?.model == nil)
    }

    @Test func testMalformedAndNegativeRecordsDoNotEraseValidUsage() {
        let data = fixture([meta("s"), usage(100), usage(-1, second: 2)]) + Data("bad json\n{\"unfinished\":".utf8)
        let result = SessionParser.parse(data: data, fileID: "f")
        #expect(result.events.count == 1)
        #expect(result.events.first?.usage.input == 100)
        #expect(result.diagnostics == 2)
    }

    @Test func testMissingTimestampAndInvalidCachedCountAreRejected() {
        var noTimestamp = usage(100); noTimestamp.removeValue(forKey: "timestamp")
        let result = SessionParser.parse(data: fixture([meta("s"), noTimestamp, usage(100, cached: 101)]), fileID: "f")
        #expect(result.events.isEmpty)
        #expect(result.diagnostics == 2)
    }

    @Test func testAccumulatedDeltaHasNoInventedRequestContext() {
        let result = SessionParser.parse(data: fixture([meta("s"), usage(300_000, lastInput: 150_000)]), fileID: "f")
        #expect(result.events.first?.usage.input == 300_000)
        #expect(result.events.first?.requestInput == nil)
    }
}

func fixture(_ records: [[String: Any]]) -> Data {
    records.reduce(into: Data()) { data, record in
        data.append(try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
        data.append(10)
    }
}
func meta(_ id: String, fork: String? = nil, timestamp: String = "2026-10-10T12:00:00Z", paginated: Bool = false) -> [String: Any] {
    var payload: [String: Any] = ["id": id, "timestamp": timestamp]
    if let fork { payload["forked_from_id"] = fork }
    if paginated { payload["history_mode"] = "paginated"; payload["history_base"] = ["thread_id": fork ?? "", "end_ordinal_exclusive": 100] }
    return ["type": "session_meta", "payload": payload, "timestamp": timestamp]
}
func context(_ model: String) -> [String: Any] {
    ["type": "turn_context", "payload": ["model": model]]
}
func usage(_ input: Int64, cached: Int64 = 0, output: Int64 = 0, second: Int = 1, lastInput: Int64? = nil, lastCached: Int64? = nil, lastOutput: Int64? = nil) -> [String: Any] {
    let total: [String: Any] = ["input_tokens": input, "cached_input_tokens": cached, "output_tokens": output, "reasoning_output_tokens": 0, "cache_write_input_tokens": 0]
    var last = total; last["input_tokens"] = lastInput ?? input
    last["cached_input_tokens"] = lastCached ?? cached; last["output_tokens"] = lastOutput ?? output
    return ["type": "event_msg", "timestamp": String(format: "2026-10-10T12:00:%02dZ", second), "payload": ["type": "token_count", "info": ["total_token_usage": total, "last_token_usage": last]]]
}
