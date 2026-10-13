import Foundation

/// A separate helper survives application termination and opens the bundle only
/// after the old process exits. Launch Services then reads its current executable.
enum AppRelauncher {
    static func makeProcess(
        bundleURL: URL, processIdentifier: Int32,
        openExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/open"),
        maximumChecks: Int = 300
    ) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            remaining="$3"
            while /bin/kill -0 "$1" 2>/dev/null; do
                if [ "$remaining" -le 0 ]; then exit 1; fi
                remaining=$((remaining - 1))
                /bin/sleep 0.1
            done
            exec "$4" -n "$2"
            """, "codex-cost-restart", String(processIdentifier), bundleURL.path,
            String(maximumChecks), openExecutableURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
