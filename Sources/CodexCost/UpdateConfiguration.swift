import Foundation

// Keep the updater out of bare SwiftPM executables and incomplete app bundles.
enum UpdateConfiguration {
    static func isEnabled(bundleURL: URL, info: [String: Any]) -> Bool {
        guard bundleURL.pathExtension == "app",
            let feed = info["SUFeedURL"] as? String,
            let url = URL(string: feed), url.scheme == "https", url.host != nil,
            let key = info["SUPublicEDKey"] as? String,
            let decoded = Data(base64Encoded: key), decoded.count == 32
        else { return false }
        return true
    }
}
