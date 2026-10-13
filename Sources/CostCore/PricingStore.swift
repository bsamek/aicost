import Foundation

/// A daily, best-effort download. Usage records never enter the request.
public actor PricingStore {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)
    public static let refreshInterval: TimeInterval = 24 * 60 * 60
    public static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Harness", isDirectory: true)
    }
    private struct Cache: Codable {
        let data: Data
        let fetchedAt: Date
    }
    private let directory: URL
    private let fetch: Fetch
    private var current: PricingCatalog?
    private var lastAttempt: Date?
    private var isFetching = false

    public init(
        cacheDirectory: URL = PricingStore.defaultCacheDirectory,
        fetch: @escaping Fetch = PricingStore.download
    ) {
        directory = cacheDirectory
        self.fetch = fetch
    }

    public func catalog() throws -> PricingCatalog {
        if let current { return current }
        let value = try Self.cachedCatalog(cacheDirectory: directory)
        current = value
        return value
    }

    /// The diagnostic report reads this same persistent cache without starting a download.
    public nonisolated static func cachedCatalog(
        cacheDirectory: URL = PricingStore.defaultCacheDirectory
    ) throws -> PricingCatalog {
        if let cache = readCache(cacheDirectory),
            let catalog = try? PricingCatalog.load(
                modelsDevData: cache.data, fetchedAt: cache.fetchedAt)
        {
            return catalog
        }
        return try PricingCatalog.load()
    }

    @discardableResult public func refreshIfNeeded(now: Date = Date()) async -> Bool {
        guard !isFetching else { return false }
        if let lastAttempt, now >= lastAttempt,
            now.timeIntervalSince(lastAttempt) < Self.refreshInterval
        {
            return false
        }
        let persistedAttempt = try? JSONDecoder().decode(
            Date.self, from: Data(contentsOf: directory.appendingPathComponent("last-attempt.json"))
        )
        let previous = [lastAttempt, persistedAttempt, Self.readCache(directory)?.fetchedAt]
            .compactMap { $0 }.max()
        if let previous, now >= previous, now.timeIntervalSince(previous) < Self.refreshInterval {
            lastAttempt = previous
            return false
        }
        isFetching = true
        lastAttempt = now
        defer { isFetching = false }
        // Persist failures too, so an offline restart doesn't retry every 30 seconds.
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(now) {
            try? data.write(
                to: directory.appendingPathComponent("last-attempt.json"), options: .atomic)
        }
        do {
            var request = URLRequest(
                url: URL(string: "https://models.dev/api.json")!,
                cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, status) = try await fetch(request)
            try Task.checkCancellation()
            guard status == 200 else { return false }
            let catalog = try PricingCatalog.load(modelsDevData: data, fetchedAt: now)
            let cached = try JSONEncoder().encode(Cache(data: data, fetchedAt: now))
            try cached.write(
                to: directory.appendingPathComponent("models-dev.json"), options: .atomic)
            current = catalog
            return true
        } catch {
            // Keep the last valid cache (or bundle). Failure never clears usage totals.
            return false
        }
    }

    private nonisolated static func readCache(_ directory: URL) -> Cache? {
        let url = directory.appendingPathComponent("models-dev.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= 30_000_000,
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    public nonisolated static func download(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
