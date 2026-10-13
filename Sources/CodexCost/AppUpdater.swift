import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var updateAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            guard controller?.updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates
            else { return }
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    var isAvailable: Bool { controller != nil }

    func start() {
        guard controller == nil,
            UpdateConfiguration.isEnabled(
                bundleURL: Bundle.main.bundleURL, info: Bundle.main.infoDictionary ?? [:])
        else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                // Sparkle's updater and its KVO notifications are main-thread confined.
                MainActor.assumeIsolated { self?.canCheckForUpdates = value }
            }
        controller.startUpdater()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        updateAvailable = !handleShowingUpdate
    }

    func standardUserDriverWillFinishUpdateSession() {
        updateAvailable = false
    }

    func checkForUpdates() {
        guard canCheckForUpdates || updateAvailable else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}
