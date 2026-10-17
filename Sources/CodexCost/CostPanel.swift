import CostCore
import SwiftUI

// Select the property wrapper explicitly on SDKs that also export a State macro.
private typealias PanelState<Value> = SwiftUI.State<Value>

struct CostPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: AppUpdater
    let checkForUpdates: () -> Void
    let restart: () -> Bool
    let quit: () -> Void

    var body: some View {
        CostPanelContent(
            summary: model.summary, error: model.error,
            updates: PanelUpdateState(
                updateAvailable: updates.updateAvailable,
                canCheckForUpdates: updates.canCheckForUpdates, isAvailable: updates.isAvailable),
            automaticallyChecksForUpdates: Binding(
                get: { updates.automaticallyChecksForUpdates },
                set: { updates.automaticallyChecksForUpdates = $0 }),
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
                as? String,
            checkForUpdates: checkForUpdates, restart: restart, quit: quit)
    }
}

struct PanelUpdateState {
    let updateAvailable: Bool
    let canCheckForUpdates: Bool
    let isAvailable: Bool
}

/// Shared native presentation for the live popover and synthetic UI previews.
/// This view never starts scanners or the updater; its caller supplies state and actions.
struct CostPanelContent: View {
    let summary: CostSummary?
    let error: String?
    let updates: PanelUpdateState
    @Binding var automaticallyChecksForUpdates: Bool
    let version: String?
    let checkForUpdates: () -> Void
    let restart: () -> Bool
    let quit: () -> Void
    @PanelState private var isRestarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary {
                period("Today", summary.today)
                Divider()
                period("This Month", summary.month)
            } else {
                Text(error == nil ? "Reading usage…" : "Usage unavailable")
                    .foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button(
                    updates.updateAvailable ? "Update Available…" : "Check for Updates…",
                    action: checkForUpdates
                )
                .fixedSize()
                .disabled(!updates.canCheckForUpdates && !updates.updateAvailable)
                Spacer()
                Toggle(
                    "Auto-check",
                    isOn: $automaticallyChecksForUpdates
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(.gray)
                .fixedSize()
                .accessibilityLabel("Automatically check for updates")
                .help("Automatically check for updates")
                .disabled(!updates.isAvailable)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
            HStack(spacing: 12) {
                if let version {
                    Text("v\(version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Token Meter version \(version)")
                }
                Spacer()
                Button("Restart") {
                    isRestarting = true
                    isRestarting = restart()
                }
                Button("Quit", action: quit)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
            .disabled(isRestarting)
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 280)
    }

    private func period(_ title: String, _ value: PeriodCost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(dollars(value.total)).monospacedDigit()
                    .accessibilityLabel("\(title) total, \(dollars(value.total))")
            }.fontWeight(.semibold)
            ForEach(value.displayedModels.filter { $0.pricedCount > 0 }) { row in
                HStack {
                    Text(ModelNaming.displayName(row.model))
                    Spacer()
                    Text(dollars(row.total)).monospacedDigit()
                }.foregroundStyle(.secondary)
            }
        }
    }
}
