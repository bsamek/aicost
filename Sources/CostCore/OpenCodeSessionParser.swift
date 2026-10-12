import Foundation
import CoreFoundation

/// OpenCode normalizes input, cache reads/writes, visible output, and reasoning separately.
public struct OpenCodeTokenUsage: Equatable, Sendable {
    public var input: Int64
    public var cacheRead: Int64
    public var cacheWrite: Int64
    public var output: Int64
    public var reasoning: Int64
    var requestInput: Int64 { input + cacheRead + cacheWrite }
    var billableOutput: Int64 { output + reasoning }
    var fingerprint: String { "\(input),\(cacheRead),\(cacheWrite),\(output),\(reasoning)" }
}

struct OpenCodeRecord {
    var event: UsageEvent
    let created: Int64
    let completed: Int64
    var copyKey: String { "\(created)/\(completed)/\(event.openCodeProvider ?? "")/\(event.model ?? "")/\(event.openCodeUsage!.fingerprint)" }
}

public enum OpenCodeSessionParser {
    public static func parse(data: Data, id: String, sessionID: String, modern: Bool) -> ScanResult {
        let result = record(data: data, id: id, sessionID: sessionID, modern: modern)
        return ScanResult(events: result.record.map { [$0.event] } ?? [], diagnostics: result.diagnostics, fileCount: 1)
    }
    static func record(data: Data, id: String, sessionID: String, modern: Bool) -> (record: OpenCodeRecord?, diagnostics: Int) {
        func invalid() -> (OpenCodeRecord?, Int) { (nil, 1) }
        guard !id.isEmpty, !sessionID.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return invalid() }
        if !modern, object["role"] as? String != "assistant" { return object.isEmpty ? invalid() : (nil, 0) }
        func integer(_ value: Any?) -> Int64? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let count = Int64(number.stringValue), count >= 0 else { return nil }
            return count
        }
        guard let time = object["time"] as? [String: Any],
              let created = integer(time["created"]) else { return invalid() }
        let completedValue = integer(time["completed"]) ?? (modern && object["type"] as? String == "compaction" && object["status"] as? String == "completed" ? created : nil)
        guard let completed = completedValue,
              completed >= created, completed <= 253_402_300_799_000,
              let tokens = object["tokens"] as? [String: Any], let cache = tokens["cache"] as? [String: Any],
              let input = integer(tokens["input"]), let output = integer(tokens["output"]),
              let reasoning = integer(tokens["reasoning"]), let read = integer(cache["read"]),
              let write = integer(cache["write"]) else { return invalid() }
        var total: Int64 = 0
        for count in [input, output, reasoning, read, write] {
            let sum = total.addingReportingOverflow(count)
            guard !sum.overflow else { return invalid() }
            total = sum.partialValue
        }
        guard total > 0 else { return (nil, 0) }
        let model = object["model"] as? [String: Any]
        let provider = (modern ? model?["providerID"] : object["providerID"]) as? String
        let modelID = (modern ? model?["id"] : object["modelID"]) as? String
        var usage = OpenCodeTokenUsage(input: input, cacheRead: read, cacheWrite: write, output: output, reasoning: reasoning)
        var issue: String?
        // Older AI SDK records may include reasoning in output. A recorded total
        // resolves the two shapes; without evidence, leave nonzero reasoning unpriced.
        if !modern && reasoning > 0 {
            if let recordedTotal = integer(tokens["total"]), recordedTotal == total - reasoning, output >= reasoning {
                usage.output -= reasoning
            } else if integer(tokens["total"]) != total {
                issue = "Legacy OpenCode reasoning accounting unavailable"
            }
        }
        if provider?.isEmpty != false || modelID?.isEmpty != false { issue = "OpenCode provider/model unavailable" }
        var event = UsageEvent(identity: "opencode:\(id)", sessionID: sessionID,
                               timestamp: Date(timeIntervalSince1970: Double(created) / 1000), model: modelID,
                               usage: TokenUsage(input: usage.requestInput, cached: read, writes: write,
                                                 output: usage.billableOutput, reasoning: reasoning),
                               requestInput: usage.requestInput, issue: issue)
        event.openCodeUsage = usage; event.openCodeProvider = provider
        return (OpenCodeRecord(event: event, created: created, completed: completed), issue == nil ? 0 : 1)
    }
}
