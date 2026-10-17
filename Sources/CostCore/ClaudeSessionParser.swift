import Foundation

/// Claude input excludes cache reads and writes; these are disjoint billable categories.
public struct ClaudeTokenUsage: Decodable, Equatable, Sendable {
    public let input: Int64
    public let cacheRead: Int64
    public let cacheWrites: Int64
    public let output: Int64
    private let cacheCreation: CacheCreation?
    public var cacheWrite5m: Int64? { cacheCreation?.fiveMinutes }
    public var cacheWrite1h: Int64? { cacheCreation?.oneHour }
    private struct CacheCreation: Decodable, Equatable, Sendable {
        let fiveMinutes: Int64
        let oneHour: Int64
        enum CodingKeys: String, CodingKey {
            case fiveMinutes = "ephemeral_5m_input_tokens"
            case oneHour = "ephemeral_1h_input_tokens"
        }
    }
    enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case cacheRead = "cache_read_input_tokens"
        case cacheWrites = "cache_creation_input_tokens"
        case output = "output_tokens"
        case cacheCreation = "cache_creation"
    }
    var requestInput: Int64? {
        let (first, overflow1) = input.addingReportingOverflow(cacheRead)
        let (total, overflow2) = first.addingReportingOverflow(cacheWrites)
        return overflow1 || overflow2 ? nil : total
    }
    var isValid: Bool {
        input >= 0 && cacheRead >= 0 && cacheWrites >= 0 && output >= 0 && requestInput != nil
    }
    var cacheIssue: String? {
        guard let cacheCreation else {
            return cacheWrites == 0 ? nil : "Claude cache-write duration unavailable"
        }
        let (total, overflow) = cacheCreation.fiveMinutes.addingReportingOverflow(
            cacheCreation.oneHour)
        guard cacheCreation.fiveMinutes >= 0, cacheCreation.oneHour >= 0, !overflow,
            total == cacheWrites
        else {
            return "Claude cache-write breakdown invalid"
        }
        return nil
    }
}

public enum ClaudeSessionParser {
    private struct Record: Decodable {
        let timestamp: String
        let sessionId: String?
        let requestId: String?
        let message: Message
        struct Message: Decodable {
            let id: String
            let model: String
            let usage: ClaudeTokenUsage
        }
    }
    public static func parse(data: Data) -> ScanResult {
        var events: [UsageEvent] = []
        var diagnostics = 0
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        for line in data.split(separator: 0x0a)
        where !line.allSatisfy({ $0 == 0x20 || $0 == 0x0d || $0 == 0x09 }) {
            do {
                let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                guard object?["type"] as? String == "assistant",
                    let message = object?["message"] as? [String: Any], message["usage"] != nil
                else { continue }
                let record = try decoder.decode(Record.self, from: Data(line))
                guard !record.message.id.isEmpty, !record.message.model.isEmpty,
                    record.message.usage.isValid,
                    let date = fractional.date(from: record.timestamp)
                        ?? plain.date(from: record.timestamp)
                else {
                    diagnostics += 1
                    continue
                }
                let usage = record.message.usage
                let event = UsageEvent(
                    identity: "claude|" + record.message.id,
                    sessionID: record.sessionId ?? "unknown",
                    timestamp: date, model: record.message.model, usage: .claude(usage),
                    requestInput: usage.requestInput, issue: usage.cacheIssue,
                    requestID: record.requestId)
                events.append(event)
                if event.issue != nil { diagnostics += 1 }
            } catch { diagnostics += 1 }
        }
        return ScanResult(events: events, diagnostics: diagnostics, fileCount: 1)
    }
}
