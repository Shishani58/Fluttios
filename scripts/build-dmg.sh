#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/check-version.sh
version=$(tr -d '\r\n' < VERSION)
app="${APP_OUTPUT:-$PWD/dist/SimFlutDock.app}"
output="${DMG_OUTPUT:-$PWD/dist/SimFlutDock-$version.dmg}"
if [[ "${SKIP_BUILD:-0}" != 1 ]]; then ./scripts/build-app.sh; fi
[[ -d "$app" ]] || { echo "App bundle missing: $app" >&2; exit 1; }
actual=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$actual" == "$version" ]] || { echo "App version does not match VERSION" >&2; exit 1; }
codesign --verify --deep --strict "$app"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/volume"
# Stage only the app and public installation material, never the workspace.
ditto --noextattr --noqtn "$app" "$staging/volume/SimFlutDock.app"
ln -s /Applications "$staging/volume/Applications"
cp LICENSE "$staging/volume/LICENSE.txt"
cat > "$staging/volume/Installation.txt" <<'INSTALL'
SimFlutDock — macOS 14+ / Apple Silicon + Intel

ENGLISH
Drag SimFlutDock.app to Applications, then launch it from Applications.
Install Xcode and Flutter to run your Flutter projects.
For simulator window attachment, enable SimFlutDock in:
System Settings > Privacy & Security > Accessibility.

Unsigned/ad-hoc builds are not notarized by Apple. macOS may block the first
launch. Review the release notes before opening the app.

РУССКИЙ
Перетащите SimFlutDock.app в Applications и запускайте установленную копию.
Для запуска проектов нужны Xcode и Flutter.
Для привязки панели разрешите SimFlutDock в:
Настройки системы > Конфиденциальность и безопасность > Универсальный доступ.

Сборки с ad-hoc подписью не нотарифицированы Apple. macOS может заблокировать
первое открытие. Перед запуском прочитайте описание релиза.
INSTALL
hdiutil create -volname "SimFlutDock $version" -srcfolder "$staging/volume" \
  -format UDZO -ov "$staging/SimFlutDock.dmg"
hdiutil verify "$staging/SimFlutDock.dmg"
mkdir -p "$(dirname "$output")"
mv -f "$staging/SimFlutDock.dmg" "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
printf "Built DMG: %s\n" "$output"
