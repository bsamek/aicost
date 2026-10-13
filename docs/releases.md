# Release maintenance

See the [README](../README.md) for user installation instructions.

The tag workflow in `.github/workflows/release.yml` calls the same test-and-package workflow used for PRs and `main`. It uses macOS 15, Xcode 16.4 and the standard Swift toolchain; there are no third-party Swift dependencies. The app is built for arm64 with an explicit macOS 13 deployment target; Intel Macs are not supported. This is a repeatable build recipe, not a claim of byte-for-byte identical ZIPs (build numbers, signatures and archive timestamps can differ).

To validate a release locally without publishing:

```sh
# A standard Swift 6 toolchain; omit SWIFT_TOOL to use the local CLT workaround.
SWIFT_TOOL=swift scripts/package-release.sh 1.2.3 1
```

This writes `Token-Meter-VERSION-arm64.zip` (containing `Token Meter.app`), its SHA-256 checksum and generated release notes into `build/release`. It validates the arm64-only binary architecture, version/build metadata, macOS deployment targets, signature integrity, resource contents, the diagnostic report with `.build` hidden, and native GUI process startup after relocation and ZIP extraction. It stops only the temporary app process it starts. Runtime checks cover the Apple Silicon runner's OS; macOS 13 compatibility is validated in metadata, not tested on a physical Mac running macOS 13.

After merging and reviewing CI, a maintainer can create and push an annotated `v1.2.3` tag at the intended commit. Only numeric three-part stable versions are accepted. **Pushing a version tag authorizes publication**: after validation passes, the workflow creates the GitHub Release and attaches the ZIP and checksum. A failed test, packaging check or extraction check prevents the publish job. The tag sets `CFBundleShortVersionString`; the release workflow's run number sets `CFBundleVersion`. The public Release names the source commit and includes install/Gatekeeper instructions. A repeated run does not overwrite an existing Release; choose a new version for changed artifacts.

### Signing and notarization

The current workflow needs only GitHub's temporary token to publish the validated artifacts. It does not request Apple credentials or claim notarization. To distribute with the normal Gatekeeper developer identity path, a future workflow needs an Apple Developer Program membership, a **Developer ID Application** certificate/private key, hardened runtime signing with a secure timestamp, submission to Apple's notary service, and a stapled accepted ticket before packaging. See [Apple's notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

Keep any future certificate export, certificate password and notarization credentials in **GitHub Actions secrets**; never commit them or print them in logs. Import the certificate into a temporary runner keychain, sign the finished app, wait for notarization acceptance, staple and validate the ticket, re-run relocated package checks, and only then permit publication. Signing/notarization is not implemented by this release workflow; the ad-hoc download path above retains a first-launch Gatekeeper exception.
