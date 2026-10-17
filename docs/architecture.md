# Architecture

This describes the current implementation. The original [October 10 design](superpowers/specs/2026-10-10-codex-cost-design.md) and [implementation plan](superpowers/plans/2026-10-10-codex-cost.md) are historical.

## Data flow

```text
Local logs / OpenCode database snapshot
    → provider parser + scanner
    → UsageScanner → UsageEvent records + diagnostics
    → PricingCatalog + SummaryBuilder
    → CostSummary → AppModel / CostPanel or CostReport JSON
```

`CostCore` owns parsing, scanning, pricing, aggregation, and ordering. It uses Foundation and platform APIs, with no UI code or third-party libraries. `CodexCost` owns the AppKit/SwiftUI menu bar app and report. The package uses Swift 6 language mode and targets Apple Silicon Macs running macOS 13 or later.

## Where to make a change

| Concern | Files |
| --- | --- |
| Codex counters, active/archive merging, forks | `Sources/CostCore/CodexSessionParser.swift`, `CodexSessionScanner.swift` |
| Claude, Pi, or OpenCode formats and identities | Corresponding `*SessionParser.swift` and `*SessionScanner.swift` files |
| JSONL log discovery, parse caching, identity deduplication | `Sources/CostCore/LogScanning.swift` |
| Combined scanning, diagnostics, and source overrides | `Sources/CostCore/UsageScanner.swift`, `UsageSources.swift` |
| Shared usage types, including per-agent `ProviderUsage` | `Sources/CostCore/Usage.swift` |
| Rate tables and catalog loading | `Sources/CostCore/Rates.swift`, `Pricing.swift`, `ModelsDevCatalog.swift`, `PricingStore.swift`, `Resources/*.json` |
| Per-agent cost rules | `Sources/CostCore/ProviderPricing.swift` |
| Provider aliases and readable model names | `Sources/CostCore/ModelNaming.swift` |
| Day/month totals and ordering | `Sources/CostCore/Summary.swift`, `ModelOrder.swift` |
| Background loading and refresh state | `Sources/CodexCost/AppModel.swift`, `UsageLoader.swift` |
| Menu bar lifecycle and automatic refresh | `Sources/CodexCost/App.swift` |
| Sparkle update lifecycle and configuration | `Sources/CodexCost/AppUpdater.swift`, `UpdateConfiguration.swift` |
| Panel and restart helper | `Sources/CodexCost/CostPanel.swift`, `AppRelauncher.swift` |
| Native UI captures and synthetic preview states | `Tests/AppTests/PanelPreviewTests.swift`, `scripts/preview-ui.sh`, [validation guide](ui-validation.md) |
| JSON diagnostics | `Sources/CodexCost/CostReport.swift` |
| Metadata and packaging | `Resources/Info.plist`, `scripts/build-app.sh`, `scripts/package-release.sh` |

## Accounting boundaries

Each provider retains its own token semantics and deduplication rules: `UsageEvent.usage` is a `ProviderUsage` case per agent, and `PricingCatalog.cost` switches on it to that agent's rule in `ProviderPricing`. `UsageScanner` combines their results. `PricingCatalog` returns Decimal USD or an explicit unpriced reason. `SummaryBuilder` computes periods with a supplied calendar and cutoff, excluding future events. Provider/model rows remain distinct where pricing depends on the provider. The panel (via `PanelRow`) combines rows that share a `ModelNaming.displayName` into one row per model; its hover help lists each row's `ModelNaming.source` (the serving provider for prefixed rows, or the agent for bare IDs). The report includes raw row IDs, unpriced counts, and reasons. Read [accounting coverage](accounting.md) for supported formats and precise limits.

`UsageLoader` is an actor that owns the scanners and runs accounting away from the main actor. `AppModel` publishes successful results on the main actor, coalesces overlapping refreshes, and retains previous totals on failure. Refresh happens at launch and every 30 seconds. The report uses the same scan/pricing/summary components and supports a reproducible `--at` cutoff.

## Resources, tests, and distribution

The models.dev API supplies provider/model rates through `ModelsDevCatalog`; `PricingStore` validates responses, persists a last-good cache, and throttles background fetches to once every 24 hours. Startup reads cached prices or bundled fallback immediately; the report reads the same disk cache without fetching. Three fallback pricing JSON catalogs live in `Sources/CostCore/Resources` and are packaged into the CostCore resource bundle. Command-line builds use SwiftPM resource lookup; `.app` builds load the copied bundle from app resources. Token Meter is the display name; the executable, Swift targets, and resource bundle retain CodexCost identifiers.

`Tests/CostCoreTests` covers accounting with synthetic logs and temporary databases. `Tests/AppTests` covers refresh state, source resolution, and relaunch behavior, plus an opt-in native panel capture harness. `CostPanel` adapts observable app/updater state into `CostPanelContent`, the presentation shared with native captures. Both test targets use Swift Testing. Follow [CONTRIBUTING](../CONTRIBUTING.md) for local commands.

CI runs formatting and tests before arm64 packaging. Packaging validates metadata, the arm64 architecture, signatures, resources, and execution after relocation/extraction. Version-tag releases reuse the validation workflow before publication. See [release maintenance](releases.md) for signing limits and validation details.

## App updates

The GUI creates an `AppUpdater` at launch, using Sparkle's standard updater controller. The panel exposes manual checks and an opt-in background-check toggle. Silent automatic installation and profile reporting are disabled. Scheduled updates that would otherwise appear behind other apps instead show an arrow in the menu bar and an **Update Available…** button in the panel. Clicking it brings Sparkle’s update prompt forward. Bare SwiftPM executables and bundles without valid HTTPS feed/public-key configuration do not start an updater. The `--report` path returns before any updater is created. Sparkle state does not affect accounting refreshes.

The custom builder embeds Sparkle's complete versioned framework and signs nested helpers inside out before signing the app. Relocated release checks verify framework linkage, symlinks, helpers and app metadata. The release pipeline signs the validated ZIP and verifies the signature against the public key inside that ZIP before publishing its appcast.
