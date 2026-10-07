#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(tr -d '\r\n' < VERSION)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
for plist in Resources/Info.plist Resources/Helper-Info.plist; do
  actual=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
  [[ "$actual" == "$version" ]] || { echo "Version mismatch: $plist" >&2; exit 1; }
  build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
  [[ "$build" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid build number: $plist" >&2; exit 1; }
done
# Keep SwiftPM's unbundled UI fallback consistent with the app bundle.
python3 - "$version" <<'CHECK'
import sys
from pathlib import Path
source = Path('Sources/SimFlutDock/Views.swift').read_text()
assert f'as? String ?? "{sys.argv[1]}"' in source, 'Update the version fallback in Views.swift'
CHECK
printf 'Version verified: %s\n' "$version"
