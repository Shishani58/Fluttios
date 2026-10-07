<div align="center">
  <img src="Resources/AppIcon.png" width="96" alt="Fluttios">
  <h1>Fluttios</h1>
  <p>Flutter controls. Right beside your simulator.</p>
  <p><a href="README.md">Русский</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="LICENSE">MIT</a></p>
  <img src="docs/images/panel.png" width="630" alt="Fluttios panel with Run, Reload, Restart and Stop controls">
</div>

A native macOS utility to run Flutter projects, use Hot Reload and read logs without switching to Terminal or your IDE.

## Install

[**Download Fluttios 1.0.1 (.dmg)**](https://github.com/Shishani58/Fluttios/releases/download/v1.0.1/Fluttios-1.0.1.dmg)

Requires **macOS 14+**, **Flutter SDK** and full **Xcode**. Supports Apple Silicon and Intel. Open the DMG and drag the app to **Applications**.

The build is not notarized by Apple. If macOS blocks the first launch, follow [Apple’s guidance](https://support.apple.com/en-us/102445).

## Features

- **Run, Hot Reload, Hot Restart and Stop**, with an independent session per project.
- A panel beside **Simulator / Device Hub**, or a floating panel.
- Device and launch mode selection, with **FVM** support.
- Logs, saved deep links and quick access to project and app data folders.
- English and Russian UI, light and dark appearance.

## Quick start

1. Open Fluttios → menu bar icon → **Settings → Projects → Open Project**. Select a folder containing `pubspec.yaml`.
2. Select a device and press **Run**. Use **Reload** after Dart changes, or **Restart** to reset state.
3. To attach the panel, enable Fluttios under **System Settings → Privacy & Security → Accessibility**.

Hot Reload and Hot Restart require Debug mode. After native code or plugin changes, use **Stop → Run**.

## Build from source

```bash
git clone https://github.com/Shishani58/Fluttios.git
cd Fluttios
./scripts/build-app.sh
open dist/Fluttios.app
```

To build a DMG: `./scripts/build-dmg.sh`.
