#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
# Compile the production panel, without launching the app or its sessions.
awk '/^@MainActor final class PanelCoordinator/ {exit} !/^import FluttiosCore/' Sources/Fluttios/PanelCoordinator.swift > "$scratch/ControlPanel.swift"
cp Tests/PanelPresentation/main.swift "$scratch/main.swift"
xcrun swiftc "$scratch/ControlPanel.swift" "$scratch/main.swift" -o "$scratch/verify"
"$scratch/verify"
