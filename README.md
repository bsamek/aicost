# Codex Cost

A native macOS menu bar app that shows what your locally recorded Codex and Claude Code token usage would cost at Standard API rates. The menu bar shows today's total; click it for Today and This Month totals and a breakdown by model. It refreshes every 30 seconds. The panel shows both periods in full with a consistent font size.

## Download and install

Versioned downloads are published on [GitHub Releases](https://github.com/bsamek/aicost/releases) when a maintainer pushes a `vMAJOR.MINOR.PATCH` tag. There may be no downloadable version until the first tag is published. Download `Codex-Cost-VERSION-universal.zip`: it includes both Apple Silicon (`arm64`) and Intel (`x86_64`) code and requires **macOS 13 or later**. Swift tools and an API key are not needed to run a download.

1. Unzip the download and drag `Codex Cost.app` into Applications.
2. Open the app. Its total appears in the menu bar; there is no Dock icon or main window.
3. If macOS blocks it, try opening it once, then go to **System Settings → Privacy & Security → Open Anyway** and confirm Open. Only do this for a download you trust; [Apple explains the exception](https://support.apple.com/102445). Do not disable Gatekeeper globally.

Downloads are ad-hoc signed, **not Developer ID signed or notarized by Apple**. The signature supports executable integrity checks but does not establish the publisher's identity. The ZIP's adjacent `.sha256` file checks download integrity: put both in the same folder and run `shasum -a 256 -c Codex-Cost-VERSION-universal.zip.sha256` there. A checksum does not authenticate a publisher either.

To update, quit the running copy (Activity Monitor can stop `CodexCost`), replace the app in Applications, and open the new copy. Local usage logs are stored outside the app. Open it again after restarting your Mac.

## Build and run

Requires macOS 13 or later and Apple's Swift Command Line Tools. No third-party dependencies or API key.

```sh
bash scripts/build-app.sh
open 'build/Codex Cost.app'
```

The build uses the Mac's architecture and ad-hoc signs the bundle locally. You can keep it in this folder or copy it into Applications. To start it after restarting your Mac, open the app again.

Tests:

```sh
scripts/swift-tool.sh test --disable-xctest
```

`scripts/swift-tool.sh` uses native SwiftPM and a local copy of public package interfaces to accommodate this Mac's inconsistent Command Line Tools installation. System files remain untouched. A normal Swift 6 installation can also use `swift test --disable-xctest` and `swift build -c release`.

GitHub Actions runs both `CostCoreTests` and `AppTests` on pull requests and pushes to `main` (including merges) using macOS 15 and Xcode 16.4's bundled Swift 6 toolchain. CI uses the standard toolchain directly, without the local Command Line Tools workaround:

```sh
swift test --disable-xctest --enable-swift-testing
```

All tests use synthetic fixtures and temporary directories; no local Codex or Claude Code logs, API credentials, or account access are required. Compilation errors and test failures fail the CI job. After tests pass, CI also builds both architectures, packages a universal ZIP, verifies version/deployment metadata and every bundled resource, and launches a relocated copy of the extracted app with isolated log roots. PR builds use version `0.0.0` and are workflow artifacts, not public releases.

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

## Release maintenance

The tag workflow in `.github/workflows/release.yml` calls the same test-and-package workflow used for PRs and `main`. It uses macOS 15, Xcode 16.4 and the standard Swift toolchain; there are no third-party Swift dependencies. Each architecture is built with an explicit macOS 13 deployment target and combined with `lipo`. This is a repeatable build recipe, not a claim of byte-for-byte identical ZIPs (build numbers, signatures and archive timestamps can differ).

To validate a release locally without publishing:

```sh
# A standard Swift 6 toolchain; omit SWIFT_TOOL to use the local CLT workaround.
SWIFT_TOOL=swift scripts/package-release.sh 1.2.3 1
```

This writes a universal ZIP, SHA-256 checksum and generated release notes into `build/release`. It validates both binary architectures, version/build metadata, macOS deployment targets, signature integrity, resource contents, the diagnostic report with `.build` hidden, and native GUI process startup after relocation and ZIP extraction. It stops only the temporary app process it starts. Runtime checks cover the runner's native architecture and OS; macOS 13 and the other architecture are validated in metadata, not tested on physical Macs.

After merging and reviewing CI, a maintainer can create and push an annotated `v1.2.3` tag at the intended commit. Only numeric three-part stable versions are accepted. **Pushing a version tag authorizes publication**: after validation passes, the workflow creates the GitHub Release and attaches the ZIP and checksum. A failed test, packaging check or extraction check prevents the publish job. The tag sets `CFBundleShortVersionString`; the release workflow's run number sets `CFBundleVersion`. The public Release names the source commit and includes install/Gatekeeper instructions. A repeated run does not overwrite an existing Release; choose a new version for changed artifacts.

### Signing and notarization

The current workflow needs only GitHub's temporary token to publish the validated artifacts. It does not request Apple credentials or claim notarization. To distribute with the normal Gatekeeper developer identity path, a future workflow needs an Apple Developer Program membership, a **Developer ID Application** certificate/private key, hardened runtime signing with a secure timestamp, submission to Apple's notary service, and a stapled accepted ticket before packaging. See [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Keep any future certificate export, certificate password and notarization credentials in **GitHub Actions secrets**; never commit them or print them in logs. Import the certificate into a temporary runner keychain, sign the finished app, wait for notarization acceptance, staple and validate the ticket, re-run relocated package checks, and only then permit publication. Signing/notarization is not implemented by this release workflow; the ad-hoc download path above retains a first-launch Gatekeeper exception.
