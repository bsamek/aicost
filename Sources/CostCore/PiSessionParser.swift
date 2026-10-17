import Foundation

/// Pi normalizes provider usage to disjoint billable categories. Reasoning is a subset of output.
public struct PiTokenUsage: Decodable, Equatable, Sendable {
    public let input: Int64
    public let output: Int64
    public let cacheRead: Int64
    public let cacheWrite: Int64
    public let cacheWrite1h: Int64?
    public let reasoning: Int64?
    var requestInput: Int64? {
        let (first, overflow1) = input.addingReportingOverflow(cacheRead)
        let (total, overflow2) = first.addingReportingOverflow(cacheWrite)
        return overflow1 || overflow2 ? nil : total
    }
    var isValid: Bool {
        input >= 0 && output >= 0 && cacheRead >= 0 && cacheWrite >= 0 && requestInput != nil
            && (cacheWrite1h ?? 0) >= 0 && (cacheWrite1h ?? 0) <= cacheWrite
            && (reasoning ?? 0) >= 0 && (reasoning ?? 0) <= output
    }
}

public enum PiSessionParser {
    private struct Record: Decodable {
        let id: String
        let message: Message
        struct Message: Decodable {
            let provider: String
            let model: String
            let responseModel: String?
            let responseId: String?
            let timestamp: Int64
            let usage: PiTokenUsage
        }
    }
    private struct AuxiliaryRecord: Decodable {
        let id: String
        let timestamp: String
        let responseId: String?
        let provider: String?
        let model: String?
        let usage: PiTokenUsage
    }
    public static func parse(data: Data) -> ScanResult {
        var events: [UsageEvent] = []
        var diagnostics = 0
        var sessionID: String?
        var supported = false
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        for line in data.split(separator: 0x0a)
        where !line.allSatisfy({ $0 == 0x20 || $0 == 0x0d || $0 == 0x09 }) {
            do {
                guard
                    let object = try JSONSerialization.jsonObject(with: Data(line))
                        as? [String: Any]
                else {
                    diagnostics += 1
                    continue
                }
                if object["type"] as? String == "session" {
                    sessionID = object["id"] as? String
                    supported =
                        [2, 3].contains(object["version"] as? Int ?? 0)
                        && sessionID?.isEmpty == false
                    if !supported { diagnostics += 1 }
                    continue
                }
                if let type = object["type"] as? String,
                    ["usage", "compaction", "branch_summary"].contains(type), object["usage"] != nil
                {
                    guard supported, let sessionID else {
                        diagnostics += 1
                        continue
                    }
                    let record = try decoder.decode(AuxiliaryRecord.self, from: Data(line))
                    guard !record.id.isEmpty, record.usage.isValid,
                        let date = fractional.date(from: record.timestamp)
                            ?? plain.date(from: record.timestamp)
                    else {
                        diagnostics += 1
                        continue
                    }
                    // Summary usage can span calls and has no provider/model in the persisted schema.
                    // Do not infer attribution from adjacent model-change or assistant records.
                    let provider =
                        type == "usage" ? record.provider.flatMap { $0.isEmpty ? nil : $0 } : nil
                    let model =
                        type == "usage" ? record.model.flatMap { $0.isEmpty ? nil : $0 } : nil
                    let issue =
                        provider == nil || model == nil
                        ? "Pi \(type) usage provider/model unavailable" : nil
                    let response =
                        type == "usage" && provider != nil
                        ? record.responseId.flatMap { $0.isEmpty ? nil : $0 } : nil
                    let parts =
                        response.map { ["pi", provider!, "response", $0] }
                        ?? [
                            "pi", provider ?? "unattributed", "entry", type, record.id,
                            String(date.timeIntervalSince1970),
                        ]
                    let identity = parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
                    events.append(
                        UsageEvent(
                            identity: identity, sessionID: sessionID, timestamp: date,
                            model: model, usage: .pi(record.usage, provider: provider),
                            requestInput: record.usage.requestInput, issue: issue,
                            requestID: response))
                    if issue != nil { diagnostics += 1 }
                    continue
                }
                guard object["type"] as? String == "message",
                    let message = object["message"] as? [String: Any],
                    message["role"] as? String == "assistant",
                    message["usage"] != nil
                else { continue }
                guard supported, let sessionID else {
                    diagnostics += 1
                    continue
                }
                let record = try decoder.decode(Record.self, from: Data(line))
                let messageRecord = record.message
                guard !record.id.isEmpty, !messageRecord.provider.isEmpty,
                    !messageRecord.model.isEmpty,
                    messageRecord.timestamp >= 0, messageRecord.timestamp <= 253_402_300_799_999,
                    messageRecord.usage.isValid
                else {
                    diagnostics += 1
                    continue
                }
                let model =
                    messageRecord.responseModel.flatMap { $0.isEmpty ? nil : $0 }
                    ?? messageRecord.model
                let response = messageRecord.responseId.flatMap { $0.isEmpty ? nil : $0 }
                // Forks preserve entries and message timestamps. Provider IDs must stay separate.
                let identityParts =
                    response.map { ["pi", messageRecord.provider, "response", $0] }
                    ?? [
                        "pi", messageRecord.provider, "entry", "message", record.id,
                        String(messageRecord.timestamp),
                    ]
                let identity = identityParts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
                events.append(
                    UsageEvent(
                        identity: identity, sessionID: sessionID,
                        timestamp: Date(
                            timeIntervalSince1970: Double(messageRecord.timestamp) / 1000),
                        model: model,
                        usage: .pi(messageRecord.usage, provider: messageRecord.provider),
                        requestInput: messageRecord.usage.requestInput, requestID: response))
            } catch { diagnostics += 1 }
        }
        return ScanResult(events: events, diagnostics: diagnostics, fileCount: 1)
    }
}
