import Foundation

/// Local log roots for each supported agent. A nil root is not scanned.
public struct UsageSources: Sendable {
    public var codex: URL?
    public var claude: URL?
    public var pi: URL?
    public var openCode: URL?

    public init(codex: URL? = nil, claude: URL? = nil, pi: URL? = nil, openCode: URL? = nil) {
        self.codex = codex
        self.claude = claude
        self.pi = pi
        self.openCode = openCode
    }

    /// Each agent's documented override variable, falling back to its default location.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> UsageSources {
        func directory(_ variable: String, default relative: String) -> URL {
            guard let override = environment[variable], !override.isEmpty else {
                return userHome.appendingPathComponent(relative)
            }
            if override == "~" { return userHome }
            if override.hasPrefix("~/") {
                return userHome.appendingPathComponent(String(override.dropFirst(2)))
            }
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return UsageSources(
            codex: directory("CODEX_HOME", default: ".codex"),
            claude: directory("CLAUDE_CONFIG_DIR", default: ".claude"),
            pi: directory("PI_CODING_AGENT_DIR", default: ".pi/agent"),
            openCode: directory("XDG_DATA_HOME", default: ".local/share")
                .appendingPathComponent("opencode"))
    }
}
