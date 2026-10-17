import Foundation

/// Runs `body` with a fresh directory (and optional subdirectories), removed afterwards.
public func withTemporaryDirectory<T>(
    creating subdirectories: [String] = [], _ body: (URL) throws -> T
) throws -> T {
    let root = try makeTemporaryDirectory(creating: subdirectories)
    defer { try? FileManager.default.removeItem(at: root) }
    return try body(root)
}

public func withTemporaryDirectory<T>(
    creating subdirectories: [String] = [], isolation: isolated (any Actor)? = #isolation,
    _ body: (URL) async throws -> T
) async throws -> T {
    let root = try makeTemporaryDirectory(creating: subdirectories)
    defer { try? FileManager.default.removeItem(at: root) }
    return try await body(root)
}

/// Writes `data` at `relative` below `root`, creating intermediate directories.
public func write(_ data: Data, _ root: URL, _ relative: String) throws {
    let url = root.appendingPathComponent(relative)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

private func makeTemporaryDirectory(creating subdirectories: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "token-meter-tests-" + UUID().uuidString)
    for path in [""] + subdirectories {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    return root
}
