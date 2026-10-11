# Codex Cost

A small native macOS menu bar app that estimates what Brian's locally recorded Codex token usage would cost at published OpenAI API prices while he uses a subscription.

## Interface

The menu bar displays today's estimated total in USD. Clicking opens a compact popover with two sections: Today and This Month. Each section shows a total and a row per model with its estimated cost. Period boundaries use the Mac's local timezone; This Month means the current calendar month. Display the last successful refresh time and a Refresh action. Include Quit.

No charts, subscription comparison, notifications, account login, API key, or launch-at-login setting in the first version.

## Implementation

Use Swift with native AppKit/SwiftUI, built locally as a standalone .app. Keep parsing, pricing, aggregation, and presentation separate. Include a repeatable build script and usage instructions. The app runs without a Dock icon.

Read session JSONL files from ~/.codex/sessions and ~/.codex/archived_sessions when present. Support an alternate Codex home via CODEX_HOME. Never modify source logs or read authentication files. Parse only metadata needed for attribution and token usage; do not retain conversation text.

Refresh on launch, every 30 seconds, and on manual refresh. Perform parsing off the UI thread. Cache per-file results and reread changed files. Handle truncated trailing lines while Codex is writing; isolate malformed records so other sessions remain usable.

## Usage accounting

Attribute usage to the event timestamp and the most recent model in turn_context. Use changes in cumulative total_token_usage to count new usage, rather than summing repeated last_token_usage snapshots. Handle counter resets and reject negative counts. Deduplicate repeated session/event records and inherited fork history when identifiable; tests must cover repeated snapshots, resets, model changes, and forks. Unknown attribution remains visible as unpriced usage, never silently zero dollars.

Input counts include cached input. Charge ordinary input, cached input, separately recorded cache writes, and output using the model's corresponding rates. Verify cache-write field semantics against available records before implementing the subtraction. Reasoning output is part of output and must not be charged twice.

## Pricing and limits

Bundle a readable pricing table with official source URL and verification date. Use published Standard API rates as the explicit baseline, with long-context rates when a recorded request exceeds the documented threshold and the request input count is available. Show the baseline in the popover. Do not infer processing tier from the subscription or fabricate historical prices.

Current rates are applied to all displayed usage. Unknown models are marked unpriced and excluded from the dollar total, with a visible coverage notice. Totals estimate model tokens only; cloud sessions absent from local logs and non-token tool charges are outside coverage. The popover includes a concise estimate note and a link to pricing. No network access is needed during ordinary operation.

## Validation and delivery

Use fixture-based tests for cumulative accounting, cached and reasoning tokens, pricing, model attribution, fork duplication, malformed records, and local day/month boundaries. Compile the app, run it against real local logs read-only, and verify displayed totals against an independent calculation. Deliver the .app in the workspace with source and build instructions; open it for a launch check. Installation outside the workspace is optional and requires a user request.
