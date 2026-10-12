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
    public static func parse(data: Data) -> ScanResult {
        var events: [UsageEvent] = []; var diagnostics = 0
        var sessionID: String?; var supported = false
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0a) where !line.allSatisfy({ $0 == 0x20 || $0 == 0x0d || $0 == 0x09 }) {
            do {
                guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                    diagnostics += 1; continue
                }
                if object["type"] as? String == "session" {
                    sessionID = object["id"] as? String
                    supported = [2, 3].contains(object["version"] as? Int ?? 0) && sessionID?.isEmpty == false
                    if !supported { diagnostics += 1 }
                    continue
                }
                guard object["type"] as? String == "message",
                      let message = object["message"] as? [String: Any], message["role"] as? String == "assistant",
                      message["usage"] != nil else { continue }
                guard supported, let sessionID else { diagnostics += 1; continue }
                let record = try decoder.decode(Record.self, from: Data(line))
                let messageRecord = record.message
                guard !record.id.isEmpty, !messageRecord.provider.isEmpty, !messageRecord.model.isEmpty,
                      messageRecord.timestamp >= 0, messageRecord.timestamp <= 253402300799999,
                      messageRecord.usage.isValid else { diagnostics += 1; continue }
                let model = messageRecord.responseModel.flatMap { $0.isEmpty ? nil : $0 } ?? messageRecord.model
                let response = messageRecord.responseId.flatMap { $0.isEmpty ? nil : $0 }
                // Forks preserve entries and message timestamps. Provider IDs must stay separate.
                let identityParts = response.map { ["pi", messageRecord.provider, "response", $0] }
                    ?? ["pi", messageRecord.provider, "entry", record.id, String(messageRecord.timestamp), model]
                let identity = identityParts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
                var event = UsageEvent(identity: identity, sessionID: sessionID,
                    timestamp: Date(timeIntervalSince1970: Double(messageRecord.timestamp) / 1000), model: model,
                    usage: .zero, requestInput: messageRecord.usage.requestInput)
                event.piUsage = messageRecord.usage; event.piProvider = messageRecord.provider
                event.requestID = response
                events.append(event)
            } catch { diagnostics += 1 }
        }
        return ScanResult(events: events, diagnostics: diagnostics, fileCount: 1)
    }
}
