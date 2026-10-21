#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/check-version.sh
for script in scripts/*.sh; do bash -n "$script"; done
plutil -lint Resources/Info.plist Resources/Helper-Info.plist SimFlutDock.xcodeproj/project.pbxproj
xcrun swift test --build-system native
./scripts/verify-panel-presentation.sh
