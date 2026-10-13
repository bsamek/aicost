# Native UI validation

For changes to the panel's layout, typography, colors, or controls, run the native preview harness and **inspect the resulting PNGs** in addition to formatting and tests. Do not ask the user to inspect routine changes unless a design decision remains unresolved. HTML mockups and passing tests alone do not establish the appearance of native SwiftUI controls.

```sh
scripts/preview-ui.sh
# Command Line Tools workaround:
SWIFT_TOOL=scripts/swift-tool.sh scripts/preview-ui.sh
# Optional explicit output directory:
SWIFT_TOOL=scripts/swift-tool.sh scripts/preview-ui.sh /tmp/token-meter-ui-review
```

This performs an incremental debug build of the existing test target, then captures the real `CostPanelContent` in a native AppKit window at the production 280-point width. It uses synthetic in-memory summaries and supplied update state. It does not construct `AppModel` or `AppUpdater`, read personal logs or preferences, start Sparkle, access the network at runtime, install an app, or replace the running app. SwiftPM may download the existing dependency on the first build. It requires a logged-in macOS graphical session and briefly shows preview windows; do not run it concurrently with another native UI capture.

The twelve PNGs cover these states in both light and dark appearance:

- `auto-on` and `auto-off`: populated usage and enabled update controls.
- `update-available`: the longer action label, with an available update even when ordinary checks are disabled.
- `disabled`: the updater is unavailable.
- `loading` and `error`: compact panels without usage totals.

The default output is a new timestamped directory under ignored `build/ui-previews/`. Preview version `0.0.0` and all totals are synthetic. Filenames identify the state; the images deliberately contain no presentation-only labels. If using an explicit directory, use a fresh one so a failed run cannot be confused with earlier captures.

## Review and report

Open all relevant PNGs with the agent's image viewer. Check for clipping, single-line alignment, spacing, native control color, legibility in both appearances, and clear enabled/disabled and on/off states. Capture success is only a rendering check; the visual review is a separate required step. Retain the images and provide a representative capture plus the output path when useful. Report what was inspected and any limitation; do not describe uninspected captures as validated.

There are no pixel-perfect golden images: OS rendering can vary, and the agent reviews intentional appearance changes directly. Extend `Tests/AppTests/PanelPreviewTests.swift` with synthetic states relevant to future UI changes. Both the live `CostPanel` adapter and harness must use `CostPanelContent`; never maintain a separate reproduction of the UI for screenshots. Keep preview fixtures and capture code in the test target, not production models.

Ordinary `scripts/check.sh` runs compile this harness but skip its capture test unless `TOKEN_METER_PREVIEW_DIR` is set. They do not show preview windows. The preview command only runs the rendering test, so run the ordinary full checks separately.

## Limits

The harness validates content rendering, not the menu-bar anchor, popover arrow/material, focus dismissal, Sparkle dialogs, update networking, signatures, or installed bundle behavior. For changes to those integration boundaries, validate the actual app or preview package as described in [CONTRIBUTING](../CONTRIBUTING.md) and [release maintenance](releases.md). Building or installing a replacement app is not a routine prerequisite for panel styling validation.
