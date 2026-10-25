<div align="center">
  <img src="Resources/AppIcon.png" width="96" alt="SimFlutDock">
  <h1>SimFlutDock</h1>
  <p>Flutter controls. Right beside your simulator.</p>
  <p><a href="README.md">Русский</a> · <a href="CHANGELOG.md">Changelog</a> · <a href="LICENSE">MIT</a></p>
  <img src="docs/images/panel.png" width="630" alt="SimFlutDock panel with Run, Reload, Restart and Stop controls">
</div>

A native macOS utility to run Flutter projects, use Hot Reload and read logs without switching to Terminal or your IDE.

## Install

[**Download SimFlutDock 1.0.10 (.dmg)**](https://github.com/Shishani58/Fluttios/releases/download/v1.0.10/SimFlutDock-1.0.10.dmg)

Requires **macOS 14+**, **Flutter SDK** and full **Xcode**. Supports Apple Silicon and Intel. Open the DMG and drag the app to **Applications**.

The build is not notarized by Apple. If macOS blocks the first launch, follow [Apple’s guidance](https://support.apple.com/en-us/102445).

### Updates

Update through **Settings → General → App Updates**. The app verifies SHA-256 and the signature before installation. Stopping active Flutter sessions requires confirmation.

## Features

- **Run, Hot Reload, Hot Restart and Stop**, with an independent session for each project and device. Switching devices changes the session being controlled while other sessions keep running.
- A panel beside **Simulator / Device Hub**, or a floating panel.
- Device and launch mode selection, with **FVM** support.
- Searchable logs, error filtering, pause/resume scrolling, source links and diagnostic report copying.
- One-click DevTools for the selected session, saved deep links and quick access to project and app data folders.
- English and Russian UI, light and dark appearance.

## Quick start

1. Open SimFlutDock → menu bar icon → **Settings → Projects → Open Project**. Select a folder containing `pubspec.yaml`.
2. Select a device and press **Run**. Use **Reload** after Dart changes, or **Restart** to reset state.
3. To attach the panel, enable SimFlutDock under **System Settings → Privacy & Security → Accessibility**.

Hot Reload and Hot Restart require Debug mode. After native code or plugin changes, use **Rerun**: the active session’s Run button stops it, rebuilds, and launches again on the same device.

### AI session control (MCP)

AI clients can discover projects and devices, launch with saved settings, read state and logs, use **Hot Reload**, **Hot Restart**, **Rerun**, and **Stop**, open deep links, and take screenshots. Open SimFlutDock, then connect Codex (Python 3 required):

```bash
codex mcp add fluttios -- python3 /Applications/SimFlutDock.app/Contents/Resources/fluttios-mcp.py
```

Set `tool_timeout_sec = 120` in the Codex server configuration. See [other clients and tool details](docs/mcp.md).

## Build from source

```bash
git clone https://github.com/Shishani58/Fluttios.git
cd Fluttios
APP_OUTPUT=/Applications/SimFlutDock.app ./scripts/build-app.sh
open /Applications/SimFlutDock.app
```

The command updates the installed copy in Applications. To build separately without installing, use `./scripts/build-app.sh`; the bundle in `dist` does not need to be installed again. To build a DMG: `./scripts/build-dmg.sh`.

For local checks, source layout, and integration tests, see [Contributing](CONTRIBUTING.md).
