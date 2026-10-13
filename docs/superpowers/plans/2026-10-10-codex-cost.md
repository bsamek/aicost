# Codex Cost Implementation Plan

> **Historical plan, October 10, 2026.** Unchecked boxes preserve the original planning record; they are not the current backlog. The app now uses Swift Testing and supports additional agents. Use the current [architecture](../../architecture.md), [accounting](../../accounting.md), and [contributor guide](../../../CONTRIBUTING.md). The workflow instruction below belongs to the historical plan and should not be executed for routine maintenance.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans for native execution or superpowers:subagent-driven-development if selected by the user. Steps use checkbox syntax for tracking.

**Goal:** Deliver a local macOS menu bar app showing hypothetical API token costs for today and this calendar month, with model breakdowns and totals.

**Architecture:** A Swift package provides a testable accounting library and a native menu bar executable. A background scanner caches parsed files; the UI presents an immutable summary and refresh status. A build script bundles the executable and pricing data into a standalone app.

**Tech Stack:** Swift, Foundation, AppKit, SwiftUI, XCTest; no third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-10-codex-cost-design.md`

## Global Constraints

- Menu bar displays today's estimated total in USD.
- Today and This Month use the Mac's local timezone and current calendar month.
- Read ~/.codex/sessions and ~/.codex/archived_sessions; support CODEX_HOME.
- Refresh on launch, every 30 seconds, and manually; parsing stays off the UI thread.
- Use current published Standard API token rates, with applicable long-context pricing.
- Exact note: "Estimated API token cost for Codex usage recorded on this Mac."
- Do not include a pricing link in the app. Keep pricing source and verification date in bundled data.
- No Dock icon, API key, network requirement, charts, notifications, subscription comparison, or launch-at-login setting.
- Never modify source logs, read authentication files, or retain conversation text.

## Review Focus

- Archived and active copies of one session must not duplicate costs.
- A fork containing inherited usage must not charge parent history again.
- Missing model/rate/usable request counts must produce visible incomplete coverage.
- File truncation or deletion must invalidate cached results without retaining stale totals.
- Permission errors must appear in refresh status without replacing a successful total with a misleading zero.

## Task 1: Parse and normalize usage

**Files:** `Package.swift`, `Sources/CostCore/Usage.swift`, `Sources/CostCore/SessionParser.swift`, `Sources/CostCore/SessionScanner.swift`, `Tests/CostCoreTests/UsageTests.swift`, `.gitignore`.

**Interfaces:** `TokenUsage` stores input, cached input, cache writes, output, and reasoning counts as Int64. `UsageEvent` stores a stable identity, session ID, timestamp, optional model, usage, and optional request input count. `SessionParser.parse(data: Data, fileID: String) -> ParsedSession` returns events, fork metadata, and diagnostic counts. `SessionScanner.scan(home: URL) throws -> ScanResult` merges sessions and returns deduplicated events plus diagnostics.

- [ ] Add the Swift package and failing fixture tests. Assert cumulative input snapshots [100, 100, 150] produce 150 input tokens; a reset [100, 20] produces 120. Assert a model change attributes the subsequent delta to the new model. Assert negative counts are rejected, missing model remains explicit, and a partial trailing line leaves earlier events usable.
- [ ] Run `swift test`; verify the accounting types are missing before implementation.
- [ ] Implement the parser. Process model context and usage in file order; use cumulative differences to detect repeated snapshots and resets. Use last_token_usage for request context only when consistent with the delta; never sum it blindly. Parse metadata without preserving text. Reasoning counts are informational and are not additional output.
- [ ] Add scanner tests for active/archive duplicates, a fork copying identical parent events, and a fork recording history-base metadata. Assert inherited usage is counted once; when the inheritance boundary cannot be established, report incomplete coverage rather than inventing a dollar amount. Read exact fork metadata shapes from local logs before implementing those cases.
- [ ] Implement the scanner with per-file size/mtime caching and invalidation on truncation/deletion. Deduplicate event identities across copies and inherited history; retain independent child/subagent usage. Test changed, deleted, unreadable, and empty directories using temporary fixtures.
- [ ] Run `swift test` and commit the parser/scanner with passing tests.

## Task 2: Price and aggregate

**Files:** `Sources/CostCore/Pricing.swift`, `Sources/CostCore/Summary.swift`, `Sources/CostCore/Resources/pricing.json`, `Tests/CostCoreTests/PricingTests.swift`, `Tests/CostCoreTests/SummaryTests.swift`.

**Interfaces:** `PricingCatalog.load() throws -> PricingCatalog`; `PricingCatalog.cost(for: UsageEvent) -> CostResult` returns Decimal USD or an explicit unpriced reason. `SummaryBuilder.build(events: [UsageEvent], now: Date, calendar: Calendar, pricing: PricingCatalog) -> CostSummary` produces today/month totals, sorted model rows, and unpriced event counts.

- [ ] Write failing tests: at input $2, cached $0.10, output $10 per million, 1M input including 250K cached plus 100K output costs $2.525. Adding reasoning_output_tokens leaves that cost unchanged. Test the >272K request-input boundary independently with distinct long-context rates.
- [ ] Run `swift test` and verify new pricing tests fail.
- [ ] Fetch official pricing again and bundle Standard rates for supported models with source URL and verification date. Use Decimal arithmetic. Do not map unknown model aliases to arbitrary prices. Apply long-context rates only with usable request input counts; mark ambiguous cases unpriced. Nonzero cache writes require verified count semantics before subtraction; if not established, mark those events unpriced and explain coverage in the UI.
- [ ] Write period tests using America/New_York: events at 23:59 and 00:00 belong to separate days; September 30 and October 1 belong to separate months. Include DST transitions, future timestamps, unknown models, and totals equal to the sum of priced model rows. Exclude future events.
- [ ] Implement aggregation with Calendar date intervals, current-rate valuation, zero-cost empty periods, and explicit unknown rows. Preserve incomplete coverage counts in each period.
- [ ] Run `swift test` and commit pricing/summary with passing tests.

## Task 3: Native app and delivery

**Files:** `Sources/CodexCost/App.swift`, `Sources/CodexCost/AppModel.swift`, `Sources/CodexCost/CostPanel.swift`, `scripts/build-app.sh`, `Resources/Info.plist`, `README.md`.

**Interfaces:** `AppModel` is a MainActor observable model with summary, refreshing state, last successful refresh, and error state; `refresh()` runs scanner/aggregation off the main actor. `App` owns NSStatusItem, NSPopover, timer, and Quit action.

- [ ] Implement launch refresh, a 30-second timer, and manual Refresh. Coalesce overlapping refreshes. Retain the last successful summary on failure; surface errors and timestamp. Use the user's home by default and CODEX_HOME when supplied.
- [ ] Build the panel with Today and This Month totals and model rows, the exact estimate note, Standard pricing baseline/date, refresh timestamp, Refresh, and Quit. Show unpriced coverage only when present. Use USD currency formatting and native light/dark appearance.
- [ ] Create a repeatable release build script producing `build/Codex Cost.app`, copying package resources and setting LSUIElement. Add README build/run instructions, log coverage, current-price behavior, and limitations. Ignore build outputs in Git.
- [ ] Run `swift test` and `bash scripts/build-app.sh`; require passing tests and a built executable bundle. Run a read-only independent Python calculation over representative real sessions and compare the app library's totals. Investigate discrepancies before delivery.
- [ ] Open the app and inspect the actual menu bar/panel. Verify today/month model rows, totals, manual refresh, failure messaging, and Quit. Confirm no Dock icon and no pricing link. If GUI access prevents verification, report that limitation explicitly.
- [ ] Run `git diff --check`, review the complete change against this spec, commit source/docs, and deliver a clickable app path with concise launch instructions.

## Execution choice

Native execution is recommended: this is a small app with three closely connected tasks. A final independent review can check accounting and packaging after implementation. Subagent-driven execution is also available if requested.
