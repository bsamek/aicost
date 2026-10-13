# AI coding costs in your menu bar

See the API-equivalent cost of your coding agents in the macOS menu bar. Harness reads local **Codex, Claude Code, Pi, and OpenCode** usage and estimates what the recorded tokens would cost at published Standard API rates—even when you use a subscription.

![Expanded Harness panel showing Today and This Month totals with a breakdown across GPT and Claude models](docs/images/usage-panel.png)

*Native app panel captured with synthetic usage data. Models appear alphabetically by provider and family: Claude Haiku, Opus, and Sonnet, then GPT Astra and Sol. Each period shows only models with priced usage.*

## Features

- Today's total at a glance; click for Today and This Month totals and a breakdown by model.
- Automatic refresh every 30 seconds, using your Mac's timezone for days and calendar months.
- Local, read-only usage processing. No API key, account connection, or third-party dependencies. Prices refresh from models.dev with an offline cache.
- Restart and Quit controls in the panel.
- A read-only JSON report for diagnostics and reproducible accounting.

These are **token-cost estimates**, not your subscription bill or an exact historical API invoice. Subscription usage counts when it is recorded locally; your subscription payment is unaffected.

## Requirements

- macOS 13 or later.
- Locally recorded usage from at least one supported agent.
- To build from source: Swift 6 and Apple's Command Line Tools or Xcode.

## Install and run

Download the universal Apple Silicon + Intel ZIP from [the latest release](https://github.com/bsamek/aicost/releases/latest), or build from source using the steps below. The existing v0.1.0 release is named **Codex Cost** (`Codex-Cost-0.1.0-universal.zip`, containing `Codex Cost.app`); subsequent releases and source builds use **Harness**.

Download `Harness-VERSION-universal.zip`, unzip it, and drag `Harness.app` to `/Applications`. Downloads are ad-hoc signed; they are **not Developer ID signed or notarized**. If macOS blocks a download you trust, try opening it once, then use **System Settings → Privacy & Security → Open Anyway** and confirm Open ([Apple's instructions](https://support.apple.com/102445)). The adjacent `.zip.sha256` file checks integrity with `shasum -a 256 -c Harness-VERSION-universal.zip.sha256`; it does not establish publisher identity.

Build from a checkout:

```sh
git clone https://github.com/bsamek/aicost.git
cd aicost
bash scripts/build-app.sh
open 'build/Harness.app'
```

The build uses your Mac's architecture and ad-hoc signs the bundle locally. Keep the app in the build folder or copy it to `/Applications`. Open it again after restarting your Mac. To update, use **Quit** in the panel, replace the app, and open the new copy; local usage logs live outside the app.

## Usage and log locations

Open the app, then click its dollar total in the menu bar. Both periods sort models alphabetically by provider and then by model family, with newer numeric versions first within each family. The order does not depend on cost. Unknown providers and families appear last by model ID. Only models with priced usage appear in the panel; use the diagnostic report to inspect skipped or unpriced records.

| Agent | Default local source | Override |
| --- | --- | --- |
| Codex | `~/.codex/sessions` and `~/.codex/archived_sessions` | `CODEX_HOME` |
| Claude Code | `~/.claude/projects/**/*.jsonl`, including nested subagents | `CLAUDE_CONFIG_DIR` |
| Pi | `~/.pi/agent/sessions/**/*.jsonl` (v2/v3 sessions) | `PI_CODING_AGENT_DIR` |
| OpenCode | `~/.local/share/opencode/opencode.db` | `XDG_DATA_HOME` (the app appends `/opencode`) |

Finder launches usually do not inherit shell environment variables. For custom roots, launch the executable from a shell:

```sh
CODEX_HOME=/absolute/path/to/codex \
CLAUDE_CONFIG_DIR=/absolute/path/to/claude \
'build/Harness.app/Contents/MacOS/CodexCost'
```

The app reads usage and session metadata without changing logs. OpenCode is scanned through a private temporary copy of its database and committed WAL, removed after each scan. It does not access authentication files, upload usage or conversation data, or print conversation text in reports. Its only network activity is downloading the public price catalog described below.

## Pricing and coverage

Harness downloads provider-specific prices from [models.dev's public API](https://models.dev/api.json) in the background, at most once every 24 hours. It immediately shows cached prices at startup, or bundled prices if no valid cache exists. Valid responses are saved atomically in `~/Library/Caches/Harness/models-dev.json`; failed requests and invalid responses retain the last good cache. Attempts, including failures, are throttled across app restarts. Newly downloaded prices appear on the next normal usage refresh (every 30 seconds).

Bundled catalogs remain fallbacks for exact provider/model entries absent from the API and for offline startup: [`pricing.json`](Sources/CostCore/Resources/pricing.json), [`pi-pricing.json`](Sources/CostCore/Resources/pi-pricing.json), and [`opencode-pricing.json`](Sources/CostCore/Resources/opencode-pricing.json). They record verification dates and sources including [OpenAI](https://developers.openai.com/api/docs/pricing), [Claude](https://platform.claude.com/docs/en/about-claude/pricing), [Fireworks](https://docs.fireworks.ai/serverless/pricing), and [OpenCode Console](https://dev.opencode.ai/v2/docs/console/models). Claude's one-hour cache-write rates use verified bundled overrides while the base input price still matches; models.dev supplies only one cache-write price. Unavailable duration rates remain unpriced.

The active catalog's Standard rates apply to all displayed history, so a price refresh can change historical estimates. Input, cache usage, and output are priced separately; context tiers use recorded request input, including multiple API tiers. Repeated counters, identifiable inherited history, and duplicate messages are handled within each agent's accounting format. Provider/model rows stay separate where provider-specific pricing matters. OpenRouter serving routes and separate reasoning-token rates remain unsupported. The panel combines Pi's `fireworks` and OpenCode's `fireworks-ai` rows for the verified DeepSeek V4.1 Flash and GLM 5.3 Flash models, with a readable Fireworks label; the diagnostic report retains the original source rows. Positive costs below one cent display as `<$0.01`; exact zero displays as `$0.00`.

Unknown models and ambiguous usage are excluded from dollar totals. Missing/deleted logs, cloud-only or unrecorded requests, non-token tool charges, fast/priority modes, regional premiums, custom prices, and negotiated discounts are outside coverage. Local formats are not stable billing APIs, so estimates can differ from invoices and historical rates. See [accounting and pricing coverage](docs/accounting.md) for supported provider/model IDs, cache-write rules, deduplication, schema support, and other limits.

## Diagnostic report

```sh
'build/Harness.app/Contents/MacOS/CodexCost' --report
```

This prints JSON using the same persisted price cache and accounting rules as the app without opening the UI or downloading prices. The `pricing` object records the source, API fetch time when available, and the bundled verification date; a fetch time is not a verification date. Add an ISO 8601 timestamp for a reproducible cutoff (prices still come from the active cache):

```sh
'build/Harness.app/Contents/MacOS/CodexCost' --report --at 2026-10-12T16:00:00Z
```

The report includes file/diagnostic counts, per-model totals, and reasons for unpriced usage. It reads only session metadata and usage.

## Development and tests

Start with [CONTRIBUTING.md](CONTRIBUTING.md) for setup, debugging, and PR guidance, and the [architecture guide](docs/architecture.md) for a map of the code. Coding agents should also read [AGENTS.md](AGENTS.md).

With a standard Swift 6 installation, check formatting and run all tests:

```sh
scripts/check.sh
```

For a Command Line Tools installation with inconsistent package interfaces, the repository includes a local workaround:

```sh
SWIFT_TOOL=scripts/swift-tool.sh scripts/check.sh --disable-sandbox
```

[`swift-tool.sh`](scripts/swift-tool.sh) uses SwiftPM and local copies of public package interfaces; it leaves system files untouched. The bundle builder uses this wrapper too.

Run `scripts/format.sh` to apply the checked-in Swift formatting style. GitHub Actions uses the same `scripts/check.sh` command on pull requests and pushes to `main` with macOS 15 and Xcode 16.4's Swift 6 toolchain. Tests use synthetic fixtures and temporary directories, so they require no personal logs, API credentials, or account access. Formatting violations, compilation errors, and test failures fail CI.

After the tests pass, CI packages and validates a universal app ZIP, including metadata, resources, signature integrity, relocated reports, and startup after extraction. PR artifacts use version `0.0.0`; they are previews, not public releases. See [release maintenance](docs/releases.md) for local packaging, publication gates, and signing limits.
