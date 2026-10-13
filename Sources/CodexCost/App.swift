import AppKit
import Combine
import CostCore
import SwiftUI

@main
@MainActor struct CodexCostApp {
    static func main() {
        if CommandLine.arguments.contains("--report") {
            do { try CostReport.printReport() } catch {
                FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private let updates = AppUpdater()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var timer: Timer?
    private var observation: AnyCancellable?
    private var updateObservation: AnyCancellable?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        updates.start()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(togglePanel)
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: CostPanel(
                model: model,
                updates: updates,
                checkForUpdates: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.updates.checkForUpdates()
                },
                restart: { [weak self] in self?.restart() ?? false },
                quit: { [weak self] in self?.quit() }
            ))
        observation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        updateObservation = updates.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        updateTitle()
        Task { await model.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
    }
    private func updateTitle() {
        let total =
            model.summary.map { dollars($0.today.total) } ?? (model.error == nil ? "…" : "!")
        let incomplete =
            model.error != nil || model.diagnostics > 0
            || (model.summary?.today.unpricedCount ?? 0) > 0
        item.button?.title = total + (updates.updateAvailable ? " ↑" : "")
        item.button?.toolTip =
            "Token Meter — today's estimated API token cost" + (incomplete ? " (incomplete)" : "")
            + (updates.updateAvailable ? " — update available" : "")
    }
    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = item.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    private func quit() {
        guard !isTerminating else { return }
        isTerminating = true
        NSApplication.shared.terminate(nil)
    }

    private func restart() -> Bool {
        guard !isTerminating else { return true }
        do {
            guard Bundle.main.bundleURL.pathExtension == "app",
                let executable = Bundle.main.executableURL,
                FileManager.default.isExecutableFile(atPath: executable.path)
            else {
                throw CocoaError(.fileNoSuchFile)
            }
            let helper = AppRelauncher.makeProcess(
                bundleURL: Bundle.main.bundleURL,
                processIdentifier: ProcessInfo.processInfo.processIdentifier)
            try helper.run()
            quit()
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t restart Token Meter"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
        observation?.cancel()
        observation = nil
        updateObservation?.cancel()
        updateObservation = nil
        popover.close()
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }
}
