# Codex Cost

A native macOS menu bar app that shows what your locally recorded Codex token usage would cost at Standard API rates. The menu bar shows today's total; click it for Today and This Month totals and a breakdown by model. It refreshes every 30 seconds and has Refresh and Quit controls.

## Build and run

Requires macOS 13 or later and Apple's Swift Command Line Tools. No third-party dependencies or API key.

```sh
bash scripts/build-app.sh
open 'build/Codex Cost.app'
```

The build uses the Mac's architecture and signs the bundle locally. You can keep it in this folder or copy it into Applications. To start it after restarting your Mac, open the app again.

Tests:

```sh
scripts/swift-tool.sh test --disable-xctest
```

`scripts/swift-tool.sh` uses native SwiftPM and a local copy of public package interfaces to accommodate this Mac's inconsistent Command Line Tools installation. System files remain untouched. A normal Swift 6 installation can also use `swift test --disable-xctest` and `swift build -c release`.

## What the estimate includes

Reads `~/.codex/sessions` and `~/.codex/archived_sessions` without modifying them. Input, cached input, and output are priced separately. Reasoning tokens are included in output. Cumulative counters, repeated snapshots, counter resets, archived copies, and identifiable inherited fork history are handled without summing duplicate usage. Days and calendar months use your Mac's timezone.

Prices are bundled in `Sources/CostCore/Resources/pricing.json`, with their source and verification date. Current Standard rates are applied to all displayed usage; this is not an exact historical bill. Long-context rates use recorded request input counts. There is no pricing link in the app and no network activity.

Models without published rates appear as Unpriced and are excluded from dollar totals. An asterisk in the menu bar indicates incomplete coverage or a refresh failure; open the panel for details. Nonzero cache-write records are also unpriced until their local count semantics can be verified. Missing cloud sessions and non-token tool charges are outside coverage. Your actual subscription payment is unaffected.

## Alternate log location

The app honors `CODEX_HOME` when launched with that environment variable. Finder launches usually do not inherit shell environment variables. For a custom location:

```sh
CODEX_HOME=/absolute/path/to/codex 'build/Codex Cost.app/Contents/MacOS/CodexCost'
```

## Read-only diagnostic report

```sh
'build/Codex Cost.app/Contents/MacOS/CodexCost' --report
```

For a reproducible timestamp, add `--at 2026-10-11T02:00:00Z`. This emits the same accounting totals as the app without opening the UI. It reads only session metadata and usage; it does not print conversation text or access authentication files.
