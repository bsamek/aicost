# Working in this repository

Harness is a Swift 6 macOS app. Read [CONTRIBUTING.md](CONTRIBUTING.md) for commands, [docs/architecture.md](docs/architecture.md) for navigation, and [docs/accounting.md](docs/accounting.md) before changing accounting.

## Commands

- Format: `scripts/format.sh`
- Check formatting and all tests: `scripts/check.sh`
- CLT workaround: `SWIFT_TOOL=scripts/swift-tool.sh scripts/check.sh --disable-sandbox`
- Build app: `bash scripts/build-app.sh`
- Validate universal preview: `SWIFT_TOOL=swift scripts/package-release.sh 0.0.0 0`

Use preview packaging for resource, bundle, build, or release changes. Do not run it concurrently with builds/tests; it temporarily moves `.build`. Report actual checks run and any limitations.

## Invariants

- Read source logs only. Do not alter logs, read authentication files, or retain conversation text. OpenCode reads a temporary snapshot, never the source database through SQLite.
- Keep missing rates, unsupported attribution, and ambiguous usage explicitly unpriced. Never convert them to zero-cost estimates or guess a provider/model rate.
- Preserve provider-specific input/cache-write/output semantics and request context thresholds. Do not charge reasoning twice or sum repeated cumulative counters.
- Deduplicate identifiable copied/forked history while preserving independent requests and subagent usage. Add synthetic regression coverage for accounting fixes.
- Keep UI and `--report` on the shared accounting path, using the Mac's calendar/timezone for day/month boundaries. Preserve the last successful UI totals when refresh fails.
- Use synthetic fixtures and temporary directories in tests; never commit personal logs or credentials.

## Scope and documentation

Keep changes focused and broad formatting separate from behavior changes. The public app name is Harness; Swift targets, executable, resource bundle, and bundle identity still use CodexCost. Preserve those internal identifiers unless migration is explicitly in scope.

Current guidance lives in the README, CONTRIBUTING, architecture, accounting, and release documents. The original October 10 spec and plan under `docs/superpowers` are historical records, not instructions to execute or a current backlog.
