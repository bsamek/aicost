import Foundation

/// One cost-independent order for every period. Raw model IDs remain unchanged.
struct ModelOrder: Comparable {
    private var recognized: Bool
    private var provider: String
    private var family: String
    private var version: [Int]
    private var foldedModel: String
    private var model: String

    init(model: String) {
        self.model = model
        foldedModel = model.lowercased()
        let parts = foldedModel.split(separator: "/", omittingEmptySubsequences: false)
        let namespace = parts.count > 1 ? String(parts[0]) : nil
        let name = String(parts.last ?? "")
        switch namespace {
        case "anthropic", "fireworks", "opencode", "opencode-go", "openrouter": provider = namespace!
        case "openai", "openai-codex": provider = "openai"
        case nil where name.hasPrefix("claude-"): provider = "anthropic"
        case nil where name.hasPrefix("gpt-") || Self.capture("^o[0-9]", in: name) != nil: provider = "openai"
        default: provider = ""
        }
        family = ""
        version = []
        if let match = Self.capture("^gpt-([0-9]+(?:\\.[0-9]+)*)-(astra|luna|sol|terra)(?:-|$)", in: name) {
            family = match[2]; version = Self.numbers(match[1])
        } else if let match = Self.capture("^claude-(fable|haiku|opus|sonnet)-([0-9]+(?:[.-][0-9]{1,3})*)(?:-|$)", in: name) {
            family = match[1]; version = Self.numbers(match[2])
        } else if let match = Self.capture("^claude-([0-9]+(?:[.-][0-9]{1,3})*)-(fable|haiku|opus|sonnet)(?:-|$)", in: name) {
            family = match[2]; version = Self.numbers(match[1])
        } else if let match = Self.capture("^gpt-([0-9]+(?:\\.[0-9]+)*)(?:o)?(?:-(?:pro|mini|nano|codex|max|turbo|instruct|preview|[0-9]+))*$", in: name) {
            family = "gpt"; version = Self.numbers(match[1])
        } else if let match = Self.capture("^o([0-9]+(?:\\.[0-9]+)*)(?:-(?:mini|pro|preview|[0-9]+))*$", in: name) {
            family = "o"; version = Self.numbers(match[1])
        } else if let match = Self.capture("^(deepseek|glm)-v?([0-9]+(?:[p.][0-9]+)*)(?:-|$)", in: name) {
            family = match[1]; version = Self.numbers(match[2])
        }
        recognized = !provider.isEmpty && !family.isEmpty
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.recognized != rhs.recognized { return lhs.recognized }
        if lhs.recognized {
            if lhs.provider != rhs.provider { return lhs.provider < rhs.provider }
            if lhs.family != rhs.family { return lhs.family < rhs.family }
            // Compare integer components, so version 6.10 sorts before 6.9, without treating versions as decimals.
            for index in 0..<max(lhs.version.count, rhs.version.count) {
                let left = index < lhs.version.count ? lhs.version[index] : 0
                let right = index < rhs.version.count ? rhs.version[index] : 0
                if left != right { return left > right }
            }
        }
        // Equal versions and unfamiliar IDs have a total, locale-independent fallback.
        if lhs.foldedModel != rhs.foldedModel { return lhs.foldedModel < rhs.foldedModel }
        return lhs.model < rhs.model
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    private static func capture(_ pattern: String, in name: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: name).map { String(name[$0]) } ?? ""
        }
    }
}
