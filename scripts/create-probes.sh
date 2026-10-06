#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for item in A B; do
  project=".build/integration/Проект $item"
  if [[ ! -f "$project/pubspec.yaml" ]]; then
    name=$(printf "%s" "$item" | tr "[:upper:]" "[:lower:]")
    flutter create --platforms ios --project-name "fluttios_probe_$name" --org com.fluttios.probe "$project"
  fi
  cp scripts/probe.dart "$project/lib/main.dart"
done
