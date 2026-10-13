# Repository Hygiene Implementation Plan

Status: Completed. This is a record of the maintenance work, not an active backlog. Brian approved recommendations 1–4 in chat.

**Goal:** Make contributor setup, repository navigation, and validation easy for humans and coding agents.

**Architecture:** Keep the Swift package and release pipeline intact. Add shared formatting/check scripts, concise contributor guidance, and a current architecture map.

**Tech Stack:** Swift 6, Swift Testing, Bash, GitHub Actions, Markdown.

## Constraints and review focus

- Preserve runtime behavior and accounting rules; initial source changes are formatter output only.
- Keep formatting separate from the documentation and workflow commit.
- Use existing synthetic tests, without personal logs or credentials.
- Keep the standard Swift path and document the explicit CLT workaround.
- Keep historical plans intact and identify current documentation as authoritative.

## Tasks

- [x] Add `.swift-format` and `scripts/format.sh`; format `Package.swift`, `Sources`, and `Tests`, then run strict lint and tests before committing the initial reformat separately.
- [x] Add `scripts/check.sh` for strict formatting checks and Swift Testing; use it in the CI test job. Retain the existing universal packaging job.
- [x] Add `CONTRIBUTING.md`, `AGENTS.md`, and `docs/architecture.md`; replace duplicated README development instructions with the shared commands and links.
- [x] Mark the original spec and plan historical, preserving their content beneath the notice.
- [x] Verify script syntax, formatter idempotence, lint failure behavior, documentation links, and the complete local check command. Review the final diff for scope and report any validation limitations.

## Validation

- All 75 tests in 9 suites passed with the documented CLT workaround.
- Strict formatting lint, idempotence, intentional lint-failure behavior, script syntax, documentation links, and diff whitespace checks passed.
- Universal preview packaging passed, including relocated and extracted GUI startup. GUI registration required execution outside the filesystem sandbox.
- Independent review confirmed all 29 reformatted Swift files match formatter output from the original revision.
- Local validation used Swift 6.4. Hosted CI with Xcode 16.4 has not been run for this change.
