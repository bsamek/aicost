import Foundation

// Builders for synthetic Codex session logs.
func codexLog(_ records: [[String: Any]]) -> Data {
    records.reduce(into: Data()) { data, record in
        data.append(try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
        data.append(10)
    }
}
func codexMeta(
    _ id: String, fork: String? = nil, timestamp: String = "2026-10-10T12:00:00Z",
    paginated: Bool = false
) -> [String: Any] {
    var payload: [String: Any] = ["id": id, "timestamp": timestamp]
    if let fork { payload["forked_from_id"] = fork }
    if paginated {
        payload["history_mode"] = "paginated"
        payload["history_base"] = ["thread_id": fork ?? "", "end_ordinal_exclusive": 100]
    }
    return ["type": "session_meta", "payload": payload, "timestamp": timestamp]
}
func codexContext(_ model: String) -> [String: Any] {
    ["type": "turn_context", "payload": ["model": model]]
}
func codexTokenCount(
    _ input: Int64, cached: Int64 = 0, output: Int64 = 0, second: Int = 1, lastInput: Int64? = nil,
    lastCached: Int64? = nil, lastOutput: Int64? = nil
) -> [String: Any] {
    let total: [String: Any] = [
        "input_tokens": input, "cached_input_tokens": cached, "output_tokens": output,
        "reasoning_output_tokens": 0, "cache_write_input_tokens": 0,
    ]
    var last = total
    last["input_tokens"] = lastInput ?? input
    last["cached_input_tokens"] = lastCached ?? cached
    last["output_tokens"] = lastOutput ?? output
    return [
        "type": "event_msg", "timestamp": String(format: "2026-10-10T12:00:%02dZ", second),
        "payload": [
            "type": "token_count", "info": ["total_token_usage": total, "last_token_usage": last],
        ],
    ]
}
