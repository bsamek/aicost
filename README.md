# Codex Cost

A native macOS menu bar app that shows what your locally recorded Codex and Claude Code token usage would cost at Standard API rates. The menu bar shows today's total; click it for Today and This Month totals and a breakdown by model. It refreshes every 30 seconds. The panel shows both periods in full with a consistent font size.

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

GitHub Actions runs both `CostCoreTests` and `AppTests` on pull requests and pushes to `main` (including merges) using macOS 15 and Xcode 16.4's bundled Swift 6 toolchain. CI uses the standard toolchain directly, without the local Command Line Tools workaround:

```sh
swift test --disable-xctest --enable-swift-testing
```

All tests use synthetic fixtures and temporary directories; no local Codex or Claude Code logs, API credentials, or account access are required. Compilation errors and test failures fail the CI job.

## What the estimate includes

Reads `~/.codex/sessions` and `~/.codex/archived_sessions` without modifying them. Input, cached input, and output are priced separately. Reasoning tokens are included in output. Cumulative counters, repeated snapshots, counter resets, archived copies, and identifiable inherited fork history are handled without summing duplicate usage. Days and calendar months use your Mac's timezone.

Prices are bundled in `Sources/CostCore/Resources/pricing.json`, with their source and verification date. Current Standard rates are applied to all displayed usage; this is not an exact historical bill. Long-context rates use recorded request input counts. There is no pricing link in the app and no network activity.

Models without published rates are excluded from the panel and dollar totals. The diagnostic report retains their details. Nonzero cache-write records are also unpriced until their local count semantics can be verified. Missing cloud sessions and non-token tool charges are outside coverage. Your actual subscription payment is unaffected.

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

## Claude Code coverage

Also reads `~/.claude/projects/**/*.jsonl`, including nested subagent transcripts. `CLAUDE_CONFIG_DIR` overrides the `.claude` directory (with the same Finder environment caveat as `CODEX_HOME`). Subscription usage is included whenever it is recorded locally; the estimate does not represent your subscription bill.

Claude input, cache reads, cache writes, and output are separate categories. Five-minute and one-hour writes use their recorded duration breakdown. The top-level usage counts are used once; nested `iterations` and thinking detail are not added again. Message IDs are deduplicated across all files, including inherited conversation copies, using the earliest recorded timestamp. A new message processing old conversation context is fresh usage and is counted. Conflicting usage/model/request IDs, missing cache-write durations, and invalid duration totals remain unpriced with diagnostics. Records lacking a stable message ID or valid counts/timestamp are skipped and diagnosed.

Bundled Claude rates cover Opus 5 and 5.5, Opus 4.8, Fable 5 and 5.1, Sonnet 5.5, and Haiku 5.5. Rates are Standard global API equivalents, applied to all displayed usage. Haiku 5.5's 100,000-token threshold includes uncached input, cache reads, and cache writes. Other models, including third-party models routed through Claude Code, remain unpriced. Missing/deleted transcripts, unrecorded requests, server-side tool fees, fast-mode premiums, geography premiums, and negotiated discounts are outside coverage. The local transcript schema is not a stable billing API; older logs without duration detail cannot fully price nonzero cache writes.
