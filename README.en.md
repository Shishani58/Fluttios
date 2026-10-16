<div align="center">
  <img src="Resources/AppIcon.png" width="96" alt="SimFlutDock">
  <h1>SimFlutDock</h1>
  <p>Flutter controls. Right beside your simulator.</p>
  <p><a href="README.md">Русский</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="LICENSE">MIT</a></p>
  <img src="docs/images/panel.png" width="630" alt="SimFlutDock panel with Run, Reload, Restart and Stop controls">
</div>

A native macOS utility to run Flutter projects, use Hot Reload and read logs without switching to Terminal or your IDE.

## Install

[**Download SimFlutDock 1.0.6 (.dmg)**](https://github.com/Shishani58/Fluttios/releases/download/v1.0.6/SimFlutDock-1.0.6.dmg)

Requires **macOS 14+**, **Flutter SDK** and full **Xcode**. Supports Apple Silicon and Intel. Open the DMG and drag the app to **Applications**.

The build is not notarized by Apple. If macOS blocks the first launch, follow [Apple’s guidance](https://support.apple.com/en-us/102445).

### Updates

The app checks stable GitHub Releases at launch, at most once a day. Check manually using **⚙ → Check for Updates…** or **Settings → General → App Updates**. Automatic checks can be disabled.

When a new version is available, choose **Download Update**. The app saves the DMG in a separate folder in Downloads, verifies its size and SHA-256, and opens the installer. Quit SimFlutDock, drag the new app to Applications, confirm replacement, and launch it again. Quitting asks for confirmation before stopping active Flutter sessions. Downloads can be cancelled; failed checks can be retried.

To ship an update, publish a stable `vX.Y.Z` release containing `SimFlutDock-X.Y.Z.dmg`, `SimFlutDock-X.Y.Z.dmg.sha256`, and `app-update.json`. The existing `scripts/build-dmg.sh` and release workflow create and publish all three files. The version must be higher than the installed version; prereleases are not offered.

## Features

- **Run, Hot Reload, Hot Restart and Stop**, with an independent session per project.
- A panel beside **Simulator / Device Hub**, or a floating panel.
- Device and launch mode selection, with **FVM** support.
- Logs, saved deep links and quick access to project and app data folders.
- English and Russian UI, light and dark appearance.

## Quick start

1. Open SimFlutDock → menu bar icon → **Settings → Projects → Open Project**. Select a folder containing `pubspec.yaml`.
2. Select a device and press **Run**. Use **Reload** after Dart changes, or **Restart** to reset state.
3. To attach the panel, enable SimFlutDock under **System Settings → Privacy & Security → Accessibility**.

Hot Reload and Hot Restart require Debug mode. After native code or plugin changes, use **Stop → Run**.

## Build from source

```bash
git clone https://github.com/Shishani58/Fluttios.git
cd Fluttios
./scripts/build-app.sh
open dist/SimFlutDock.app
```

To build a DMG: `./scripts/build-dmg.sh`.
