import Darwin
import Foundation

public final class PiSessionScanner {
    private struct Cached {
        let size: UInt64
        let modified: Date
        let inode: UInt64
        let scan: ScanResult
    }
    private var cache: [URL: Cached] = [:]
    public init() {}
    public func scan(home: URL) throws -> ScanResult {
        let manager = FileManager.default
        var files: [URL] = []
        for name in ["sessions"] {
            let root = home.appendingPathComponent(name)
            var metadata = stat()
            if Darwin.fstatat(AT_FDCWD, root.path, &metadata, 0) != 0 {
                let errorCode = errno
                if errorCode == ENOENT { continue }
                throw NSError(
                    domain: NSPOSIXErrorDomain, code: Int(errorCode),
                    userInfo: [NSFilePathErrorKey: root.path])
            }
            guard metadata.st_mode & S_IFMT == S_IFDIR else {
                throw PiScanError.unreadable(root.path)
            }
            var enumerationError: Error?
            guard
                let enumerator = manager.enumerator(
                    at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles],
                    errorHandler: { _, error in
                        enumerationError = error
                        return false
                    })
            else { throw PiScanError.unreadable(root.path) }
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                ])
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if values.isRegularFile == true && url.pathExtension == "jsonl" {
                    files.append(url)
                }
            }
            if let enumerationError { throw enumerationError }
        }
        let existing = Set(files)
        cache = cache.filter { existing.contains($0.key) }
        var scans: [ScanResult] = []
        for url in files.sorted(by: { $0.path < $1.path }) {
            let attributes = try manager.attributesOfItem(atPath: url.path)
            guard manager.isReadableFile(atPath: url.path) else {
                throw PiScanError.unreadable(url.path)
            }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modified = attributes[.modificationDate] as? Date ?? .distantPast
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            if let cached = cache[url], cached.size == size, cached.modified == modified,
                cached.inode == inode
            {
                scans.append(cached.scan)
            } else {
                let scan = try autoreleasepool {
                    PiSessionParser.parse(data: try Data(contentsOf: url))
                }
                cache[url] = Cached(size: size, modified: modified, inode: inode, scan: scan)
                scans.append(scan)
            }
        }
        var unique: [String: UsageEvent] = [:]
        var diagnostics = scans.reduce(0) { $0 + $1.diagnostics }
        for event in scans.flatMap(\.events) {
            guard var original = unique[event.identity] else {
                unique[event.identity] = event
                continue
            }
            let requestConflict =
                original.requestID != nil && event.requestID != nil
                && original.requestID != event.requestID
            if original.usage != event.usage || original.model != event.model || requestConflict {
                original.issue = "Conflicting Pi message usage"
                diagnostics += 1
            }
            // Inherited copies may receive a new transcript timestamp. Retain the original billing date.
            original.timestamp = min(original.timestamp, event.timestamp)
            if original.requestID == nil { original.requestID = event.requestID }
            unique[event.identity] = original
        }
        let events = unique.values.sorted {
            ($0.timestamp, $0.identity) < ($1.timestamp, $1.identity)
        }
        return ScanResult(events: events, diagnostics: diagnostics, fileCount: files.count)
    }
}
public enum PiScanError: LocalizedError {
    case unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .unreadable(let path): "Cannot read Pi log: \(path)"
        }
    }
}
