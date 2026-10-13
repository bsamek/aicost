import AppKit
import Foundation
import SwiftUI
import Testing

@testable import CodexCost
@testable import CostCore

/// Opt-in native rendering. Ordinary test runs never create windows or capture images.
@MainActor struct PanelPreviewTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TOKEN_METER_PREVIEW_DIR"] != nil))
    func captureNativePanelStates() async throws {
        let directory = URL(
            fileURLWithPath: try #require(
                ProcessInfo.processInfo.environment["TOKEN_METER_PREVIEW_DIR"]),
            isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let states: [(String, Bool, PanelUpdateState, CostSummary?, String?)] = [
            (
                "auto-on", true,
                .init(updateAvailable: false, canCheckForUpdates: true, isAvailable: true),
                Self.summary, nil
            ),
            (
                "auto-off", false,
                .init(updateAvailable: false, canCheckForUpdates: true, isAvailable: true),
                Self.summary, nil
            ),
            (
                "update-available", true,
                .init(updateAvailable: true, canCheckForUpdates: false, isAvailable: true),
                Self.summary, nil
            ),
            (
                "disabled", false,
                .init(updateAvailable: false, canCheckForUpdates: false, isAvailable: false),
                Self.summary, nil
            ),
            (
                "loading", true,
                .init(updateAvailable: false, canCheckForUpdates: true, isAvailable: true), nil, nil
            ),
            (
                "error", true,
                .init(updateAvailable: false, canCheckForUpdates: true, isAvailable: true), nil,
                "Synthetic read failure"
            ),
        ]
        for (appearanceName, appearance) in [
            ("light", NSAppearance.Name.aqua), ("dark", .darkAqua),
        ] {
            for (name, automatic, updates, summary, error) in states {
                let view = CostPanelContent(
                    summary: summary, error: error, updates: updates,
                    automaticallyChecksForUpdates: .constant(automatic), version: "0.0.0",
                    checkForUpdates: {}, restart: { false }, quit: {}
                )
                .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 280, height: 600),
                    styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: appearance)
                window.backgroundColor = .windowBackgroundColor
                window.contentView = host
                let height = host.fittingSize.height
                #expect(height > 0)
                window.setContentSize(NSSize(width: 280, height: height))
                window.center()
                window.makeKeyAndOrderFront(nil)
                app.activate(ignoringOtherApps: true)
                defer { window.close() }
                // SwiftUI's native controls finish updating after the first run-loop pass.
                try await Task.sleep(for: .milliseconds(150))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                #expect(host.bounds.width == 280)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                #expect(
                    try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 1,
                    "Native captures must include the window background, not transparent pixels")
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                #expect(png.count > 1000, "Native panel capture must contain rendered content")
                try png.write(to: directory.appendingPathComponent("\(appearanceName)-\(name).png"))
            }
        }
    }

    private static var summary: CostSummary {
        let rows: [(String, String)] = [
            ("claude-haiku-5-5", "0.09"), ("claude-opus-5-5", "0.22"),
            ("claude-sonnet-5-5", "0.24"),
            ("fireworks/accounts/fireworks/models/deepseek-v4p1-flash", "0.22"),
            ("gpt-6-astra", "31.39"), ("gpt-6.1-sol", "23.93"), ("gpt-5.6-sol", "0.15"),
        ]
        return CostSummary(
            today: PeriodCost(
                total: Decimal(string: "2.46")!,
                models: [
                    ModelCost(model: "gpt-6.1-sol", total: Decimal(string: "2.46")!, pricedCount: 1)
                ]),
            month: PeriodCost(
                total: Decimal(string: "56.24")!,
                models: rows.map {
                    ModelCost(model: $0.0, total: Decimal(string: $0.1)!, pricedCount: 1)
                }))
    }
}
