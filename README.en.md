<div align="center">
  <img src="Resources/AppIcon.png" width="96" alt="SimFlutDock">
  <h1>SimFlutDock</h1>
  <p>Flutter controls. Right beside your simulator.</p>
  <p><a href="README.md">Русский</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="LICENSE">MIT</a></p>
  <img src="docs/images/panel.png" width="630" alt="SimFlutDock panel with Run, Reload, Restart and Stop controls">
</div>

A native macOS utility to run Flutter projects, use Hot Reload and read logs without switching to Terminal or your IDE.

## Install

[**Download SimFlutDock 1.0.8 (.dmg)**](https://github.com/Shishani58/Fluttios/releases/download/v1.0.8/SimFlutDock-1.0.8.dmg)

Requires **macOS 14+**, **Flutter SDK** and full **Xcode**. Supports Apple Silicon and Intel. Open the DMG and drag the app to **Applications**.

The build is not notarized by Apple. If macOS blocks the first launch, follow [Apple’s guidance](https://support.apple.com/en-us/102445).

### Updates

The app checks stable GitHub Releases at launch, at most once a day. Check manually using **Settings → General → App Updates**. Automatic checks can be disabled.

A manual **Check for Updates…** downloads and prepares a newer version automatically. A background check announces the update; choose **Download Update** to proceed. The app verifies the size, SHA-256, version, and signature, then offers **Quit and Install**. It quits, replaces the installed copy, and relaunches automatically. Stopping active Flutter sessions requires confirmation; cancelling quit postpones installation. Downloads can be cancelled. Automatic replacement requires a writable installation folder outside a DMG; a failed replacement restores the previous version.

To ship an update, publish a stable `vX.Y.Z` release containing `SimFlutDock-X.Y.Z.dmg`, `SimFlutDock-X.Y.Z.dmg.sha256`, and `app-update.json`. The existing `scripts/build-dmg.sh` and release workflow create and publish all three files. The version must be higher than the installed version; prereleases are not offered.

## Features

- **Run, Hot Reload, Hot Restart and Stop**, with an independent session for each project and device. Switching devices changes the session being controlled while other sessions keep running.
- A panel beside **Simulator / Device Hub**, or a floating panel.
- Device and launch mode selection, with **FVM** support.
- Logs, saved deep links and quick access to project and app data folders.
- English and Russian UI, light and dark appearance.

## Quick start

1. Open SimFlutDock → menu bar icon → **Settings → Projects → Open Project**. Select a folder containing `pubspec.yaml`.
2. Select a device and press **Run**. Use **Reload** after Dart changes, or **Restart** to reset state.
3. To attach the panel, enable SimFlutDock under **System Settings → Privacy & Security → Accessibility**.

Hot Reload and Hot Restart require Debug mode. After native code or plugin changes, use **Stop → Run**.

### Memory and background processes

`dart:frontend_server_aot.dart.snapshot` is Flutter's compiler for Debug and Hot Reload. `Runner` is the launched app; `SimMetalHost` and `SimRenderServer` are iOS Simulator graphics services. Their memory is accounted for separately from SimFlutDock. **Stop** ends the Flutter session and remaining processes in its owned process group; the simulator stays booted. Shut down the specific device with `xcrun simctl shutdown <UDID>` when it is no longer needed.

SimFlutDock retains at most 2000 log entries and 2 MiB of log text per session, truncating individual entries to approximately 16 KiB. Oldest entries are discarded first. Removing an inactive project releases all its sessions and logs. These limits apply to retained log text, not total application memory.

## Build from source

```bash
git clone https://github.com/Shishani58/Fluttios.git
cd Fluttios
APP_OUTPUT=/Applications/SimFlutDock.app ./scripts/build-app.sh
open /Applications/SimFlutDock.app
```

The command updates the installed copy in Applications. To build separately without installing, use `./scripts/build-app.sh`; the bundle in `dist` does not need to be installed again. To build a DMG: `./scripts/build-dmg.sh`.

For local checks, source layout, and integration tests, see [Contributing](CONTRIBUTING.md).
