# Release maintenance

See the [README](../README.md) for user installation instructions.

The tag workflow in `.github/workflows/release.yml` calls the same test-and-package workflow used for PRs and `main`. It uses macOS 15, Xcode 16.4 and the standard Swift toolchain; Sparkle 2 is pinned in `Package.swift` and `Package.resolved`. The app is built for arm64 with an explicit macOS 13 deployment target; Intel Macs are not supported. This is a repeatable build recipe, not a claim of byte-for-byte identical ZIPs (build numbers, signatures and archive timestamps can differ).

To validate a release locally without publishing:

```sh
# A standard Swift 6 toolchain; omit SWIFT_TOOL to use the local CLT workaround.
SWIFT_TOOL=swift scripts/package-release.sh 1.2.3 1
```

This writes `Token-Meter-VERSION-arm64.zip` (containing `Token Meter.app`), its SHA-256 checksum and generated release notes into `build/release`. It validates the arm64-only binary architecture, version/build metadata, macOS deployment targets, signature integrity, resource contents, the diagnostic report with `.build` hidden, and native GUI process startup after relocation and ZIP extraction. It stops only the temporary app process it starts. Runtime checks cover the Apple Silicon runner's OS; macOS 13 compatibility is validated in metadata, not tested on a physical Mac running macOS 13.

After merging and reviewing CI, a maintainer can create and push an annotated `v1.2.3` tag at the intended commit. Only numeric three-part stable versions are accepted. **Pushing a version tag authorizes publication**: after validation passes, the workflow creates the GitHub Release and attaches the ZIP, checksum and `appcast.xml` after update signing succeeds. A failed test, packaging check or extraction check prevents the publish job. The tag sets `CFBundleShortVersionString`; the release workflow's run number sets `CFBundleVersion`. The public Release names the source commit and includes install/Gatekeeper instructions. A repeated run does not overwrite an existing Release; choose a new version for changed artifacts.

### Signing and notarization

The workflow uses GitHub's temporary token to publish, plus the `SPARKLE_PRIVATE_KEY` Actions secret to sign update archives. It does not request Apple credentials or claim notarization. To distribute with the normal Gatekeeper developer identity path, a future workflow needs an Apple Developer Program membership, a **Developer ID Application** certificate/private key, hardened runtime signing with a secure timestamp, submission to Apple's notary service, and a stapled accepted ticket before packaging. See [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Keep any future certificate export, certificate password and notarization credentials in **GitHub Actions secrets**; never commit them or print them in logs. Import the certificate into a temporary runner keychain, sign the finished app, wait for notarization acceptance, staple and validate the ticket, re-run relocated package checks, and only then permit publication. Signing/notarization is not implemented by this release workflow; the ad-hoc download path above retains a first-launch Gatekeeper exception.

### Sparkle update signing

Sparkle 2.10.0 is pinned. `Resources/Info.plist` contains the permanent public Ed25519 key and the stable feed URL `https://github.com/bsamek/aicost/releases/latest/download/appcast.xml`. Each stable release includes a single-item feed pointing to its immutable, version-specific ZIP URL. Publish a new release to introduce changes; do not replace archives in existing releases. Keep `CFBundleVersion` increasing; it is the release workflow run number, not the marketing version. If replacing that workflow, continue above the last published build number.

The `SPARKLE_PRIVATE_KEY` repository Actions secret is the base64-encoded 32-byte private seed. It must match the public key committed in the plist. The publish job passes it to Sparkle's pinned `sign_update` tool over stdin, then uses CryptoKit to verify the ZIP signature against the embedded public key. Missing secrets, mismatched keys or signing errors prevent Release creation. The private key is never included in build artifacts or releases. Keep a secure backup of this key: ad-hoc signed apps cannot rely on Developer ID identity to recover from losing it. Never print it or commit it. The initial key is backed up in macOS Keychain under account `token-meter-01a13360-1de8-7b51-95a1-b3a621badeb5` (Sparkle signing-key service).

GitHub serves the feed from the latest stable Release, so no Pages setup is required. The first Sparkle-enabled version requires a manual installation; after that the panel offers manual checks and opt-in background checks. Every installation requires user confirmation. Sparkle archive signatures authenticate updates but do not replace Developer ID signing or notarization.

Run `python3 -B -m unittest discover -s Tests/ReleaseTests -v` after resolving the Swift package. This uses temporary synthetic keys and app ZIPs to test feed metadata, valid signatures, tampered archives, mismatched keys, missing secrets and mismatched tags. Preview packaging never publishes a feed or needs the production private key. A real previous-to-new app replacement remains a manual release smoke test; metadata, synthetic signing and relocated startup do not prove that installation path.
