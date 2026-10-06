#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-version.sh
if [[ ! -d "${DEVELOPER_DIR:-}/Platforms/iPhoneSimulator.platform" ]]; then
  candidate=$(xcode-select -p)
  if [[ -d "$candidate/Platforms/iPhoneSimulator.platform" ]]; then export DEVELOPER_DIR="$candidate"; else
    for candidate in /Applications/Xcode*.app/Contents/Developer; do
      if [[ -d "$candidate/Platforms/iPhoneSimulator.platform" ]]; then export DEVELOPER_DIR="$candidate"; break; fi
    done
  fi
fi
configuration=${CONFIGURATION:-release}
app="${APP_OUTPUT:-$PWD/dist/Fluttios.app}"
distribution=${DISTRIBUTION:-0}
architectures=${ARCHITECTURES:-"arm64 x86_64"}
# Keep the certificate used by the installed local build. Ad-hoc signatures use
# a different cdhash after every build and invalidate existing TCC grants.
identity=${SIGNING_IDENTITY:-}
if [[ -z "$identity" && -d "$app" ]]; then
  certificate_dir=$(mktemp -d)
  if codesign --display --extract-certificates="$certificate_dir/cert" "$app" 2>/dev/null && [[ -f "$certificate_dir/cert0" ]]; then
    identity=$(openssl x509 -inform DER -in "$certificate_dir/cert0" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
  fi
  rm -rf "$certificate_dir"
fi
identity=${identity:--}
if [[ "$distribution" == 1 ]]; then
  if [[ "$identity" == - || -z "${NOTARY_PROFILE:-}" ]]; then
    echo "Distribution requires SIGNING_IDENTITY (Developer ID Application) and NOTARY_PROFILE." >&2
    exit 1
  fi
fi
# Validate the distribution certificate before building or replacing an app.
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
if [[ "$distribution" == 1 ]]; then
  cp /usr/bin/true "$staging/signing-probe"
  codesign --force --sign "$identity" --options runtime --timestamp "$staging/signing-probe"
  if ! codesign --display --verbose=4 "$staging/signing-probe" 2>&1 | grep -q '^Authority=Developer ID Application:'; then
    echo "Distribution requires a Developer ID Application certificate." >&2
    exit 1
  fi
fi
binaries=()
helper_binaries=()
for architecture in $architectures; do
  case "$architecture" in arm64|x86_64) ;; *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;; esac
  scratch="$PWD/.build/universal/$architecture"
  triple="$architecture-apple-macosx14.0"
  xcrun swift build --scratch-path "$scratch" --triple "$triple" -c "$configuration" --product Fluttios
  xcrun swift build --scratch-path "$scratch" --triple "$triple" -c "$configuration" --product FluttiosHelper
  binary_dir=$(xcrun swift build --scratch-path "$scratch" --triple "$triple" -c "$configuration" --show-bin-path)
  binaries+=("$binary_dir/Fluttios")
  helper_binaries+=("$binary_dir/FluttiosHelper")
done
[[ ${#binaries[@]} -gt 0 ]] || { echo "ARCHITECTURES must not be empty." >&2; exit 1; }
staged_app="$staging/Fluttios.app"
helper="$staged_app/Contents/Library/LoginItems/FluttiosHelper.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources" "$helper/Contents/MacOS"
xcrun lipo -create "${binaries[@]}" -output "$staged_app/Contents/MacOS/Fluttios"
xcrun lipo -create "${helper_binaries[@]}" -output "$helper/Contents/MacOS/FluttiosHelper"
cp Resources/Info.plist "$staged_app/Contents/Info.plist"
cp Resources/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"
cp Resources/Helper-Info.plist "$helper/Contents/Info.plist"
signing_options=(--force --sign "$identity" --options runtime)
if [[ "$distribution" == 1 ]]; then signing_options+=(--timestamp); else signing_options+=(--timestamp=none); fi
codesign "${signing_options[@]}" "$helper"
codesign "${signing_options[@]}" "$staged_app"
codesign --verify --deep --strict "$staged_app"
if [[ "$distribution" == 1 ]]; then
  ditto -c -k --keepParent "$staged_app" "$staging/notarization.zip"
  xcrun notarytool submit "$staging/notarization.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$staged_app"
  xcrun stapler validate "$staged_app"
  spctl --assess --type execute --verbose "$staged_app"
fi
# Publish the prepared bundle only after every required validation succeeds.
mkdir -p "$(dirname "$app")"
if [[ -e "$app" ]]; then mv "$app" "$staging/previous.app"; fi
if ! ditto "$staged_app" "$app"; then
  rm -rf "$app"
  if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$app"; fi
  exit 1
fi
if [[ "$distribution" == 1 ]]; then ditto -c -k --keepParent "$app" "${app%.app}.zip"; fi
printf "Built: %s\n" "$app"
