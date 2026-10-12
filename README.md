# Codex Cost

A native macOS menu bar app that shows what your locally recorded Codex, Claude Code, Pi, and OpenCode token usage would cost at Standard API rates. The menu bar shows today's total; click it for Today and This Month totals and a breakdown by model. It refreshes every 30 seconds. The panel shows both periods in full with a consistent font size. Model rows use the same order in Today and This Month, independent of their costs: serving provider alphabetically, then model family alphabetically, then newer numeric versions first (for example, Sol 6.10 before 6.9, or Opus 5.5 before 5). Recognized families are Claude Fable/Haiku/Opus/Sonnet, OpenAI Astra/GPT/Luna/o-series/Sol/Terra, and DeepSeek/GLM. Provider-prefixed IDs use the serving provider, including Fireworks, OpenCode, OpenCode Go, and OpenRouter; `openai-codex` shares OpenAI's ordering while keeping its row identity. Equal versions use the full model ID alphabetically. Unfamiliar models appear last with the same deterministic ID fallback. Sorting does not change totals or which priced rows are visible.

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

All tests use synthetic fixtures and temporary directories; no local Codex, Claude Code, or Pi logs, API credentials, or account access are required. Compilation errors and test failures fail the CI job.

## What the estimate includes

Reads `~/.codex/sessions` and `~/.codex/archived_sessions` without modifying them. Input, cached input, and output are priced separately. Reasoning tokens are included in output. Cumulative counters, repeated snapshots, counter resets, archived copies, and identifiable inherited fork history are handled without summing duplicate usage. Days and calendar months use your Mac's timezone.

Prices are bundled in `Sources/CostCore/Resources/pricing.json`, with their source and verification date. Current Standard rates are applied to all displayed usage; this is not an exact historical bill. Long-context rates use recorded request input counts. There is no pricing link in the app and no network activity.

Models without published rates are excluded from the panel and dollar totals. The diagnostic report retains their details. Nonzero Codex cache-write records are also unpriced until their local count semantics can be verified. Missing cloud sessions and non-token tool charges are outside coverage. Your actual subscription payment is unaffected.

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

## Pi coverage

Also reads `~/.pi/agent/sessions/**/*.jsonl` without changing the files or accessing `auth.json` or `models.json`. `PI_CODING_AGENT_DIR` overrides the `.pi/agent` directory (with the same Finder environment caveat). Default persisted v2/v3 sessions are supported; custom `--session`/`--session-dir` paths outside this tree, in-memory sessions, v1 logs, and future schema versions are outside coverage. Missing directories are empty; unreadable directories/files fail the refresh and preserve the last successful totals. Partial or malformed active lines are diagnosed, and completed lines are picked up on the next refresh.

Pi's [session manager](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/core/session-manager.ts) persists assistant request records; its [usage types](https://github.com/earendil-works/pi/blob/main/packages/ai/src/types.ts) and [provider adapters](https://github.com/earendil-works/pi/tree/main/packages/ai/src/api) normalize uncached input, cache reads, cache writes, and output into separate categories. Reasoning is already included in output, and `totalTokens` and the recorded `usage.cost` are not added or used as billing authority. The original request's millisecond timestamp controls its day/month. All recorded branches are scanned, since requests on abandoned branches still consumed tokens. Model/provider identities are taken from each assistant message, with `responseModel` preferred when present.

Provider response IDs are deduplicated globally within each provider; older records use the stable entry ID, original message timestamp, model, and provider. Forked sessions preserve those entries. Fresh requests reading old conversation context count separately. Conflicting copies remain unpriced with diagnostics. Older logs lacking stable entry identity, valid counts, or a request timestamp are skipped and diagnosed; copies rewritten with new IDs and no provider response ID cannot be identified reliably.

Supported pricing uses exact identifiers, with provider/model rows kept separate:

- `openai` and `openai-codex`: the exact OpenAI model IDs already present in the bundled catalog, at Standard API equivalent rates, including verified cache-write rates where available. The full uncached + cached + write input determines the long-context tier. Subscription payment is unaffected.
- `anthropic`: exact Claude model IDs already present in the bundled catalog. Nonzero cache writes require Pi's recorded `cacheWrite1h` split; the remainder is five-minute writes. Older logs missing that split remain unpriced.
- `fireworks`: `accounts/fireworks/models/deepseek-v4p1-flash` and `accounts/fireworks/models/glm-5p3-flash`, using the [current Standard serverless pricing table](https://docs.fireworks.ai/serverless/pricing), verified October 12, 2026 and stored in `pi-pricing.json`. DeepSeek V4.1 Flash is $0.30/$0.006/$1.20 and GLM 5.3 Flash is $0.15/$0.03/$0.50 per million uncached input/cache-read/output tokens. The current pricing table takes precedence over older Fireworks FAQs and Pi's historical recorded cost. Nonzero cache writes are unpriced because Fireworks publishes no separate write rate for these models.

OpenRouter records remain unpriced: Pi does not persist the serving route and OpenRouter's public model prices can vary by endpoint and time. Deprecated Fireworks `deepseek-v4-flash-0731`, other providers/models, custom price overrides, nonstandard tiers, geography premiums, dedicated deployments, negotiated rates, tools, and unrecorded requests are outside pricing coverage. Current supported rates are applied to all displayed usage, rather than reconstructing historical invoices. Unknown rates and accounting conflicts stay visible in `--report` as unpriced counts and per-model reasons; they are excluded from dollar totals and the panel's priced rows.

## OpenCode coverage

Reads `~/.local/share/opencode/opencode.db`; `XDG_DATA_HOME` overrides the `.local/share` root. Finder has the same environment caveat described above. The app copies a stable database and any WAL into a private temporary directory, then opens only that snapshot. It never opens the source with SQLite, creates its sidecars, checkpoints it, or reads credentials. Temporary copies are removed after each scan, including failures. A database that keeps changing during three copy attempts produces a refresh error while retaining the previous successful totals.

Supports the current `session_message` assistant projection and legacy SQLite `message` rows. Modern IDs take precedence over their migration sources. It counts each completed assistant message once, including tool-call continuations, subagents, and completed compaction requests, using the original creation date. It does not sum message parts, session totals, or event history. Input, cache reads, cache writes, visible output, and reasoning are independent categories; reasoning is priced as output once. Older legacy reasoning requires a recorded total that resolves whether output already includes it; ambiguous records stay unpriced. Malformed counts, incomplete messages, failed compaction without model attribution, and missing identities are skipped and diagnosed.

OpenCode forks can copy messages under new IDs. A record predating its owning session is recognized as inherited only when its exact original creation/completion milliseconds, provider, model, and every token category match a record in another session. Independent calls with identical usage remain separate. Deleted originals can be represented by one matching inherited copy. The scanner cannot identify inherited history after timestamps or usage metadata have been rewritten.

Rows retain `provider/model` names. Direct `openai` requests use the bundled Standard OpenAI catalog, including verified cache-write rates. The separate `opencode-pricing.json` catalog uses [OpenCode Console's published gateway rates](https://dev.opencode.ai/v2/docs/console/models), verified October 12, 2026: GPT 6/6.1 and 5.6 families, GPT 5.5/5.4, GPT 5.4 Mini/Nano, GPT 5.3 Codex, GPT 5.2/5.1/5; Claude Fable 5/5.1, Opus 5/5.5 and 4.5–4.8, Sonnet 5/5.5 and 4.5/4.6, Haiku 4.5/5.5; Gemini 3 Flash, Kimi K2.6, and currently free Big Pickle. Context tiers include all input categories. Missing cache rates remain unpriced; zero published prices count as priced.

Fireworks (`fireworks-ai`) Standard rates also cover the exact `accounts/fireworks/models/deepseek-v4p1-flash` and `accounts/fireworks/models/glm-5p3-flash` IDs, verified against the [current pricing table](https://docs.fireworks.ai/serverless/pricing) and linked model pages on October 12, 2026. DeepSeek V4.1 Flash is $0.30/$0.006/$1.20 and GLM 5.3 Flash is $0.15/$0.03/$0.50 per million uncached input/cached input/output tokens. Nonzero writes without a published rate stay unpriced. Other provider/model combinations, including older Fireworks models, OpenRouter, custom endpoints, and OpenCode Go (`opencode-go`), remain unpriced rather than borrowing a similarly named model's rate or trusting recorded cost. The diagnostic report includes the provider/model and explicit reasons. Current rates are applied to all displayed history; subscription charges, Priority/Fast mode and regional premiums, negotiated rates, payment fees, unrecorded title-generation calls, non-token tools, deleted data, pre-SQLite JSON storage, and future schema changes are outside coverage. Primary schema/accounting references: [token categories](https://github.com/anomalyco/opencode/blob/dev/packages/schema/src/token-usage.ts), [usage pricing](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session/usage.ts), and [fork projection](https://github.com/anomalyco/opencode/blob/dev/packages/core/src/session/projector.ts), and [legacy fork copying](https://github.com/anomalyco/opencode/blob/v1.2.27/packages/opencode/src/session/index.ts).
