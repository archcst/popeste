# Release workflow

The app version is stored in `VERSION`. The bundle remains `Popaste.app` with identifier `app.popaste.mac` to preserve existing permissions and login registration.

## Signed and notarized package

Install a Developer ID Application certificate with its private key in the macOS Keychain. Store notarization credentials using `xcrun notarytool store-credentials`; keep credentials out of this repository.

```sh
export POPESTE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAM_ID)'
export POPESTE_NOTARY_PROFILE='popeste-notary'
./scripts/test.sh
./scripts/package-release.sh
```

The packaging script signs with hardened runtime, submits to Apple's notary service, staples and validates the ticket, and assesses the app with Gatekeeper before producing a ZIP and SHA-256 file in `dist/`.

For local development or an explicitly identified unnotarized test release:

```sh
./scripts/package-release.sh --unsigned
```

This skips notarization; macOS can block the downloaded app. A passing ad-hoc signature verification does not mean Gatekeeper approval.

## GitHub and Homebrew

1. Commit the version and release changes, tag that commit, and upload the ZIP and its checksum to the matching GitHub Release in `archcst/popeste`.
2. Update `Casks/popeste.rb` in `archcst/homebrew-tap` with the release version, archive URL, and actual SHA-256. The initial package is Apple Silicon only and requires macOS 14+.
3. Check the Cask's syntax and style, download and verify the published archive, and test installation before announcing it.
4. Keep user data during normal uninstall. Do not add a `zap` action that silently removes `~/.config/popeste`.

Do not overwrite an already published version's archive. Publish a new version and checksum for changes.
