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
| Codex counters, active/archive merging, forks | `Sources/CostCore/SessionParser.swift`, `SessionScanner.swift` |
| Claude, Pi, or OpenCode formats and identities | Corresponding `*SessionParser.swift` and `*SessionScanner.swift` files |
| Combined scanning and diagnostics | `Sources/CostCore/UsageScanner.swift` |
| Shared usage types | `Sources/CostCore/Usage.swift` |
| Rates and provider-specific pricing | `Sources/CostCore/Pricing.swift`, `OpenCodePricing.swift`, `ModelsDevCatalog.swift`, `PricingStore.swift`, `Resources/*.json` |
| Day/month totals and ordering | `Sources/CostCore/Summary.swift`, `ModelOrder.swift` |
| Source overrides, background loading, refresh state | `Sources/CodexCost/AppModel.swift` |
| Menu bar lifecycle and automatic refresh | `Sources/CodexCost/App.swift` |
| Panel and restart helper | `Sources/CodexCost/CostPanel.swift`, `AppRelauncher.swift` |
| JSON diagnostics | `Sources/CodexCost/CostReport.swift` |
| Metadata and packaging | `Resources/Info.plist`, `scripts/build-app.sh`, `scripts/package-release.sh` |

## Accounting boundaries

Each provider retains its own token semantics and deduplication rules. `UsageScanner` combines their results. `PricingCatalog` returns Decimal USD or an explicit unpriced reason. `SummaryBuilder` computes periods with a supplied calendar and cutoff, excluding future events. Provider/model rows remain distinct where pricing depends on the provider. The panel shows priced rows; the report includes unpriced counts and reasons. Read [accounting coverage](accounting.md) for supported formats and precise limits.

`UsageLoader` is an actor that owns the scanners and runs accounting away from the main actor. `AppModel` publishes successful results on the main actor, coalesces overlapping refreshes, and retains previous totals on failure. Refresh happens at launch and every 30 seconds. The report uses the same scan/pricing/summary components and supports a reproducible `--at` cutoff.

## Resources, tests, and distribution

The models.dev API supplies provider/model rates through `ModelsDevCatalog`; `PricingStore` validates responses, persists a last-good cache, and throttles background fetches to once every 24 hours. Startup reads cached prices or bundled fallback immediately; the report reads the same disk cache without fetching. Three fallback pricing JSON catalogs live in `Sources/CostCore/Resources` and are packaged into the CostCore resource bundle. Command-line builds use SwiftPM resource lookup; `.app` builds load the copied bundle from app resources. Harness is the display name; the executable, Swift targets, and resource bundle retain CodexCost identifiers.

`Tests/CostCoreTests` covers accounting with synthetic logs and temporary databases. `Tests/AppTests` covers refresh state, source resolution, and relaunch behavior. Both use Swift Testing. Follow [CONTRIBUTING](../CONTRIBUTING.md) for local commands.

CI runs formatting and tests before arm64 packaging. Packaging validates metadata, the arm64 architecture, signatures, resources, and execution after relocation/extraction. Version-tag releases reuse the validation workflow before publication. See [release maintenance](releases.md) for signing limits and validation details.
