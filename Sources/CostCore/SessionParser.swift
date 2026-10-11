import Foundation
import CryptoKit

public enum SessionParser {
    public static func parse(data: Data, fileID: String) -> ParsedSession {
        var result = ParsedSession(id: fileID, parent: nil, created: nil, events: [], diagnostics: 0)
        var model: String?
        var previous = TokenUsage.zero
        var sawUsage = false
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ raw: Any?) -> Date? {
            guard let string = raw as? String else { return nil }
            return fractional.date(from: string) ?? plain.date(from: string)
        }
        let markers = ["\"session_meta\"", "\"turn_context\"", "\"token_count\""].map { Data($0.utf8) }
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        for (index, bytes) in lines.enumerated() where !bytes.isEmpty {
            let line = Data(bytes)
            let isTrailing = index == lines.count - 1 && data.last != 10
            // Most records are conversation text/tool output. Avoid decoding them.
            if !markers.contains(where: { line.range(of: $0) != nil }) {
                if !isTrailing && line.first != 123 { result.diagnostics += 1 }
                continue
            }
            guard let record = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let payload = record["payload"] as? [String: Any] else {
                if !isTrailing { result.diagnostics += 1 }; continue
            }
            switch record["type"] as? String {
            case "session_meta":
                // Subagents sometimes share session_id; id identifies the actual thread.
                result.id = payload["id"] as? String ?? payload["session_id"] as? String ?? fileID
                result.parent = payload["forked_from_id"] as? String
                if result.parent == nil, let base = payload["history_base"] as? [String: Any] {
                    result.parent = base["thread_id"] as? String
                }
                result.created = date(payload["timestamp"] ?? record["timestamp"])
            case "turn_context":
                model = payload["model"] as? String
            case "event_msg" where payload["type"] as? String == "token_count":
                // Null info records describe rate limits, not additional usage.
                guard let info = payload["info"] as? [String: Any] else { continue }
                guard let counts = info["total_token_usage"] as? [String: Any], let total = TokenUsage(counts),
                      let timestamp = date(record["timestamp"]) else { result.diagnostics += 1; continue }
                let last = (info["last_token_usage"] as? [String: Any]).flatMap(TokenUsage.init)
                let delta = total.delta(from: previous)
                var issue: String?
                if !sawUsage, result.parent != nil, timestamp >= (result.created ?? .distantPast), last != total {
                    issue = "Fork baseline unavailable"
                }
                previous = total; sawUsage = true
                guard delta.isValid else { result.diagnostics += 1; continue }
                guard delta.hasTokens else { continue }
                let identityData = Data("\(timestamp.timeIntervalSince1970)|\(total.fingerprint)".utf8)
                let identity = SHA256.hash(data: identityData).map { String(format: "%02x", $0) }.joined()
                result.events.append(UsageEvent(identity: identity, sessionID: result.id, timestamp: timestamp,
                    model: model, usage: delta, requestInput: last == delta ? last?.input : nil, issue: issue))
            default: break
            }
        }
        return result
    }
}
