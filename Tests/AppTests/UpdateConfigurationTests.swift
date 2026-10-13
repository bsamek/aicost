import Foundation
import Testing

@testable import CodexCost

@Test func updaterRequiresAnAppBundleAndValidSigningConfiguration() {
    let info: [String: Any] = [
        "SUFeedURL": "https://github.com/bsamek/aicost/releases/latest/download/appcast.xml",
        "SUPublicEDKey": Data(repeating: 7, count: 32).base64EncodedString(),
    ]
    #expect(
        UpdateConfiguration.isEnabled(
            bundleURL: URL(fileURLWithPath: "/tmp/Token Meter.app"), info: info))
    #expect(
        !UpdateConfiguration.isEnabled(
            bundleURL: URL(fileURLWithPath: "/tmp/CodexCost"), info: info))
    #expect(
        !UpdateConfiguration.isEnabled(
            bundleURL: URL(fileURLWithPath: "/tmp/Token Meter.app"), info: [:]))
    var insecure = info
    insecure["SUFeedURL"] = "http://example.com/appcast.xml"
    #expect(
        !UpdateConfiguration.isEnabled(
            bundleURL: URL(fileURLWithPath: "/tmp/Token Meter.app"), info: insecure))
    var invalidKey = info
    invalidKey["SUPublicEDKey"] = "placeholder"
    #expect(
        !UpdateConfiguration.isEnabled(
            bundleURL: URL(fileURLWithPath: "/tmp/Token Meter.app"), info: invalidKey))
}
