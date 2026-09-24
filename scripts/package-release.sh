#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
unsigned=false
if [[ "${1:-}" == "--unsigned" ]]; then
  unsigned=true
elif [[ $# -gt 0 ]]; then
  print -u2 'Usage: scripts/package-release.sh [--unsigned]'
  exit 1
fi
if ! $unsigned; then
  : "${POPESTE_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
  : "${POPESTE_NOTARY_PROFILE:?Set a notarytool Keychain profile}"
fi
./scripts/build-app.sh
app="$PWD/dist/Popaste.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
arch=$(uname -m)
archive="$PWD/dist/Popeste-${version}-${arch}.zip"
if ! $unsigned; then
  submission="$PWD/.build/notary-submission.zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"
  xcrun notarytool submit "$submission" --keychain-profile "$POPESTE_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose "$app"
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd dist && shasum -a 256 "${archive:t}" > "${archive:t}.sha256")
printf '%s\n' "Archive: $archive"
if $unsigned; then
  print 'This development archive is not notarized. Gatekeeper may block it.'
fi
