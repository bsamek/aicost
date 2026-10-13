# Contributing to Token Meter

Token Meter estimates API-equivalent token costs from local coding-agent logs. Start with the [architecture guide](docs/architecture.md) and [accounting rules](docs/accounting.md).

## Set up

Use an Apple Silicon Mac with Swift 6 and Apple's Command Line Tools or Xcode. The app supports macOS 13 and later; CI uses macOS 15 and Xcode 16.4. Sparkle 2 is the app’s only third-party Swift dependency. Building and running the app needs no API keys or account connections.

```sh
git clone https://github.com/bsamek/aicost.git
cd aicost
swift --version
scripts/check.sh
```

Open `Package.swift` in Xcode to navigate and debug the package, or use your editor and the commands below. The product and executable remain `CodexCost`; the public app name is Token Meter.

## Everyday commands

| Command | Purpose |
| --- | --- |
| `scripts/format.sh` | Format the manifest, source, and tests in place |
| `scripts/format.sh --check` | Check formatting without changing files |
| `scripts/check.sh` | Check formatting, then run all Swift Testing tests |
| `scripts/preview-ui.sh` | Capture the real native panel with synthetic data for agent visual review |
| `bash scripts/build-app.sh` | Build and ad-hoc sign `build/Token Meter.app` |
| `open 'build/Token Meter.app'` | Launch the local app |
| `SWIFT_TOOL=swift scripts/package-release.sh 0.0.0 0` | Build and validate an arm64 preview ZIP without publishing |

Formatting uses the toolchain's `swift format` and the checked-in `.swift-format`. Use CI's Xcode version when resolving formatter differences between toolchains. Keep broad formatting changes separate from behavior changes.

`scripts/check.sh` keeps compiler caches under `.build` by default and accepts additional Swift test options, such as `--filter ScannerTests`. Tests use synthetic fixtures and temporary directories; they need no personal logs. Do not run packaging concurrently with builds or tests: the relocated-bundle verifier temporarily moves `.build`.

### Command Line Tools workaround

Some CLT installations contain inconsistent SwiftPM package interfaces. If standard Swift fails while loading the package manifest, use:

```sh
SWIFT_TOOL=scripts/swift-tool.sh scripts/check.sh --disable-sandbox
```

The wrapper copies public package interfaces into `.build` and supplies framework paths; it leaves system files untouched. `--disable-sandbox` is for environments that cannot run SwiftPM's build sandbox. CI uses standard Swift without the workaround. The app builder defaults to the wrapper; use `SWIFT_TOOL=swift bash scripts/build-app.sh` with a standard toolchain.

## Debug and validate changes

For panel appearance changes, run `scripts/preview-ui.sh` (or `SWIFT_TOOL=scripts/swift-tool.sh scripts/preview-ui.sh`) and inspect the captured PNGs before claiming visual validation. This uses an incremental debug test build and briefly shows native preview windows; it does not install or replace the app. See [native UI validation](docs/ui-validation.md) for states, review criteria, and limitations.

Use the matching provider tests in `Tests/CostCoreTests` for parsing, deduplication, pricing, and period boundaries. Refresh and lifecycle tests live in `Tests/AppTests`. For an accounting fix, add a synthetic regression fixture that fails before the fix and passes afterward. Never commit personal logs, database snapshots, credentials, or conversation text.

To inspect the shared accounting path without opening the UI:

```sh
'build/Token Meter.app/Contents/MacOS/CodexCost' --report --at 2026-10-12T16:00:00Z
```

This reads local usage logs. To use synthetic data, set all four source overrides (`CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `PI_CODING_AGENT_DIR`, and `XDG_DATA_HOME`) to temporary fixture roots; `XDG_DATA_HOME` contains an `opencode` subdirectory. Periods use the Mac's current timezone. See the [README](README.md#usage-and-log-locations) for paths and override details.

Run `scripts/check.sh` and `python3 -B -m unittest discover -s Tests/ReleaseTests -v` before submitting a PR. SwiftPM must resolve Sparkle before the signed-feed tests. For resource, bundle-loading, build-script, or release-workflow changes, also run arm64 preview packaging. It launches a temporary app instance and validates the extracted bundle. See [release maintenance](docs/releases.md) for the checks and their limits.

Describe the problem, resulting behavior, and commands you ran in the PR. Mention checks you could not run. Update current documentation when changing formats, pricing coverage, commands, or user behavior. Pushing a version tag triggers publication; preview packaging does not.
