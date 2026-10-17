import Foundation
import TestSupport
import Testing

@testable import CodexCost

struct AppRelauncherTests {
    @Test func waitsForOldProcessAndPreservesBundlePath() throws {
        try withTemporaryDirectory { root throws in
            let marker = root.appendingPathComponent("launched")
            let opener = root.appendingPathComponent("test-open")
            try Data("#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$0.result\"\n".utf8).write(to: opener)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700], ofItemAtPath: opener.path)
            let old = Process()
            old.executableURL = URL(fileURLWithPath: "/bin/sleep")
            old.arguments = ["30"]
            try old.run()
            defer {
                if old.isRunning {
                    old.terminate()
                    old.waitUntilExit()
                }
            }
            let bundle = URL(
                fileURLWithPath: root.path + "/Cost ' $(touch " + marker.path + ").app")
            let helper = AppRelauncher.makeProcess(
                bundleURL: bundle, processIdentifier: old.processIdentifier,
                openExecutableURL: opener)
            try helper.run()
            Thread.sleep(forTimeInterval: 0.25)
            #expect(!FileManager.default.fileExists(atPath: opener.path + ".result"))
            #expect(helper.isRunning)
            old.terminate()
            old.waitUntilExit()
            helper.waitUntilExit()
            #expect(helper.terminationStatus == 0)
            #expect(
                try String(contentsOfFile: opener.path + ".result", encoding: .utf8)
                    == "-n\n\(bundle.path)\n")
            #expect(!FileManager.default.fileExists(atPath: marker.path))
        }
    }

    @Test func givesUpIfOldProcessDoesNotExit() throws {
        let helper = AppRelauncher.makeProcess(
            bundleURL: URL(fileURLWithPath: "/missing.app"),
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            maximumChecks: 2)
        try helper.run()
        helper.waitUntilExit()
        #expect(helper.terminationStatus == 1)
    }
}
