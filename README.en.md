<div align="center">
  <img src="Resources/AppIcon.png" width="112" alt="Fluttios icon">
  <h1>Fluttios</h1>
  <p><strong>Flutter controls. Right beside your simulator.</strong></p>
  <p>
    <img src="https://img.shields.io/badge/version-1.0.0-1677ff" alt="Version 1.0.0">
    <img src="https://img.shields.io/badge/macOS-14%2B-222222" alt="macOS 14+">
    <img src="https://img.shields.io/badge/Swift-SwiftUI%20%2B%20AppKit-f05138" alt="SwiftUI and AppKit">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-687080" alt="MIT license"></a>
  </p>
  <p><a href="README.md">Русский</a> · English · <a href="CHANGELOG.md">Changelog</a> · <a href="SECURITY.md">Security</a></p>
  <img src="docs/images/panel.png" width="630" alt="Fluttios panel: project, device, Run, Reload, Restart, Stop, logs and settings">
</div>

**Fluttios is a native macOS utility for Flutter development.** Keep a compact control panel beside Simulator / Device Hub, or use it as a floating panel. Switch projects, run your app and update Dart code without repeatedly returning to Terminal or your IDE. Each project has its own independent session.

Version **1.0.0**, build **1**. MIT licensed source. Download the universal DMG below, or build from source. The download uses ad-hoc signing without Apple notarization.

## Download DMG

[**Download Fluttios 1.0.0 for macOS (.dmg)**](https://github.com/Shishani58/Fluttios/releases/download/v1.0.0/Fluttios-1.0.0.dmg) · [Release notes and checksum](https://github.com/Shishani58/Fluttios/releases/tag/v1.0.0)

Supports Apple Silicon and Intel, macOS 14+. Open the DMG and drag **Fluttios.app** to **Applications**. Flutter SDK and full Xcode are required to run projects.

This build uses an **ad-hoc signature without Apple notarization**. macOS may block the first launch; the release notes include details and Apple's guidance. The download contains no personal developer certificate.

## Screenshots

These are captures of actual Fluttios SwiftUI views using **fictional demo data**. They show no private application screens, real project paths, logs, UDIDs or working project names. They demonstrate the interface, not successful execution of the pictured projects. The UI is shown in Russian; English is also available.

<table>
  <tr><th>Projects · light</th><th>Projects · dark</th></tr>
  <tr><td><img src="docs/images/projects-light.png" width="360" alt="Demo Shop and Demo Notes, project folder, data and permission actions"></td><td><img src="docs/images/projects-dark.png" width="360" alt="Fictional projects in dark appearance"></td></tr>
  <tr><th>Device and launch mode</th><th>Settings and version</th></tr>
  <tr><td><img src="docs/images/devices.png" width="360" alt="Device search, pinned iPhone, Debug mode and automatic selection"></td><td><img src="docs/images/general.png" width="520" alt="General settings: version 1.0.0, build 1, language and automatic launch"></td></tr>
</table>

<details>
<summary>Saved links and simulator tools</summary>

<img src="docs/images/tools.png" width="900" alt="Demo Shop tools with fictional product and profile links">

</details>

## Features

| Feature | Behavior |
| :--- | :--- |
| **Run / Hot Reload / Hot Restart / Stop** | Start a project, reload Dart while preserving state, restart Dart with fresh state, or stop the selected session. Reload and Restart are available in Debug. |
| **Independent sessions** | Switching A → B → A preserves processes. Hiding the panel or closing settings leaves sessions running. Quit offers Stop All and Quit or Cancel. |
| **Saved projects** | Open a folder containing `pubspec.yaml`, switch projects, and search lists longer than five entries. Icons come from standard iOS/macOS/Android/web assets, with a folder fallback. Paths are available in tooltips. |
| **Project settings** | Store device, mode and SDK per project. Relocate, remove a saved entry, or clear the list with confirmation; source folders and app data remain on disk. Stop active sessions before removing their entries. Symlinks do not create duplicates. |
| **Devices** | Discover iOS Simulator through Xcode, and physical iPhone/iPad, Android, macOS and browsers through Flutter. Search by name/OS, refresh manually, view status, pin simulators and boot a simulator without running a project. The Flutter project must support the target platform. |
| **Automatic selection** | Prefer an available running iOS Simulator; otherwise boot the first available one. Android, desktop and browser targets are never selected automatically. A missing explicitly saved device requires a new choice. |
| **Debug / Profile / Release** | Save the mode per project. iOS Simulator supports Debug only. Stop the active session before changing its device or mode; update Profile/Release apps with Stop → Run. |
| **SDK and FVM** | Project SDK overrides the global SDK. Discovery checks `.fvm/flutter_sdk`, common installations and PATH. Tool checks explain Flutter/Xcode errors; full Xcode is discovered even when Command Line Tools are selected, without changing system `xcode-select`. Fluttios does not download SDKs or invoke the FVM CLI. |
| **Operation progress** | See SDK checks, device preparation, build, installation, launch and session operations as text and an activity indicator. Flutter does not provide an overall build percentage. |
| **Logs and errors** | Per-project console with selection, copy, clear and up to 2000 entries per session. Errors can be reopened from the panel menu. Dart VM Service separates Dart logs for simulator Debug sessions; other targets use their own Flutter process output. |
| **Dart memory** | The open project menu shows main-isolate used Dart heap for iOS Simulator Debug sessions, updated about every three seconds while visible. This is not total application RAM; the launch mode is shown when unavailable. |
| **Saved links** | Add, edit, delete and open custom-scheme/HTTP/HTTPS links on a specific running iOS Simulator. Links are stored per project. The app must handle the link; web links may open in Safari. |
| **Folders and permissions** | Project-row actions open source folders and the current simulator app data container in Finder. Permission reset targets only the selected installed simulator app and preserves its files; Stop first. |
| **Attached panel** | Automatically or manually attach to Simulator / Device Hub, choose above/below/left/right, and follow window size and available monitor space. Dragging empty panel space moves the simulator with it. |
| **Floating panel** | Use an independent panel with saved coordinates. Attached panels hide when the simulator loses focus, hides, minimizes or closes, and return on activation. Focusing settings temporarily hides the panel. The menu-bar icon restores it. |
| **Compact native UI** | macOS light/dark appearance, system icons, tooltips and accessibility labels. Horizontal panels follow the window width; below 380 points Reload/Restart move to the menu. Vertical panels retain all four actions. |
| **Automatic launch** | An SMAppService login helper opens Fluttios when Simulator launches. Projects start only when you press Run. Disable it in settings; macOS may require Login Items approval. |
| **English / Russian** | Follow the system language or switch manually without restarting sessions. Other system languages fall back to English. Output from Flutter/Xcode is kept in its original language. |

## Getting started

1. Build Fluttios below. For regular use, move `dist/Fluttios.app` to `/Applications` and launch that copy.
2. Fluttios lives in the menu bar. Click its icon → gear → Settings → Projects → Open Project. Select a Flutter folder containing `pubspec.yaml`.
3. Choose a device and Debug. If necessary, set a project SDK or the default SDK under Tools, then run the tool check.
4. For window attachment, open Panel → Allow Access and enable **Fluttios** in System Settings → Privacy & Security → Accessibility. Flutter works in floating mode without this permission. Grant it to the main application, not the helper.
5. Press **Run**. Dart changes → **Reload**. Reset Dart state → **Restart**. Swift/Objective-C, plugin or native configuration changes → **Stop**, then **Run**.
6. Optionally enable Launch with Simulator under General. This section also displays version **1.0.0** and the build number.

## Build from source

Requires **macOS 14+**, full **Xcode with the macOS SDK**, **Swift 5.9+**, and Python 3 for version checks. Flutter SDK and an iOS runtime are needed to run Flutter projects, not to compile this utility. Physical iOS devices require trust, Developer Mode and project signing configured in Xcode; Fluttios does not change signing.

```bash
git clone git@github.com:Shishani58/Fluttios.git
cd Fluttios
./scripts/build-app.sh
open dist/Fluttios.app
```

The default script produces a universal **arm64 + x86_64** Release app, embeds its helper and verifies signatures. Set `CONFIGURATION=debug`, `ARCHITECTURES=arm64` or `APP_OUTPUT` to change configuration, architecture or output location. Alternatively open `Fluttios.xcodeproj` and build the **Fluttios** scheme in Xcode.

Local builds use ad-hoc signing or preserve the previous build's certificate. Set `SIGNING_IDENTITY` explicitly to choose a certificate. A changing ad-hoc signature can invalidate Accessibility permission; use one stable certificate for repeated local builds.

<details>
<summary>Signed distribution builds</summary>

Install a **Developer ID Application** certificate and private key in Keychain, and store a `notarytool` credentials profile there first. The values below are placeholders; keep signing material out of Git.

```bash
DISTRIBUTION=1 \
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="fluttios-notary" \
./scripts/build-app.sh
```

This enables Hardened Runtime, secure timestamps, notarization, stapling and Gatekeeper validation, producing an app and ZIP in `dist` only after success. Failures preserve the previous app. Normal local builds are not sent to Apple. No notarized installer is published for this source release.

</details>

Build a DMG with `./scripts/build-dmg.sh`; the image and SHA-256 checksum are saved in `dist`. GitHub Actions builds the exact `vX.Y.Z` source tag with ad-hoc signing, runs checks and publishes the DMG/checksum to Releases. The workflow runs on tags or manually; the initial 1.0.0 publication also runs when the workflow is added to main. Packaging changes after a tag are allowed only when application source and build metadata are unchanged.

## Verification

Release results: [docs/release-checks.md](docs/release-checks.md).

```bash
./scripts/check-version.sh
xcrun swift test --build-system native
./scripts/verify-panel-presentation.sh
```

If Command Line Tools are selected, set `DEVELOPER_DIR` to your full Xcode developer directory. Newer Swift versions may warn that `--build-system native` is deprecated.

Opt-in real-device integration: run `./scripts/create-probes.sh`, boot two iOS Simulators, then run `FLUTTIOS_INTEGRATION=1 xcrun swift test --build-system native --filter IntegrationTests`. It creates two isolated projects under `.build/integration` and stops only its own sessions. Existing user projects and simulators are not deleted. Logs remain local.

## Limits and privacy

- Runs use the standard `lib/main.dart`, Runner scheme and mode configuration. Custom flavors, schemes, entrypoints and additional arguments are not exposed in the UI.
- Automatic attachment and link/data/permission tools are limited to iOS Simulator. Duplicate device names or ambiguous titles require manual attachment; losing a window does not stop Flutter.
- Attaching to external Flutter processes and restoring sessions after quitting/rebooting are not supported.
- This developer utility is not sandboxed. Fast window notifications use undocumented SkyLight/Accessibility symbols with a public AX fallback. Test the fallback with `FLUTTIOS_DISABLE_PRIVATE_WINDOW_API=1 dist/Fluttios.app/Contents/MacOS/Fluttios`. Distribution is intended outside the Mac App Store.
- Project paths, device choices and links are stored locally in `~/Library/Application Support/Fluttios/projects.json`; preferences use UserDefaults. Logs can contain your application's data. See [SECURITY.md](SECURITY.md).

## Structure and versioning

`FluttiosCore` owns projects, SDK/Xcode discovery, devices, Flutter machine protocol, sessions and Dart VM Service. `Fluttios` owns SwiftUI/AppKit UI, panels and Accessibility. `FluttiosHelper` is an event-driven login item. `Tests` contains core tests and NSPanel behavior checks.

Releases follow **SemVer**: MAJOR for incompatible changes, MINOR for compatible features, PATCH for fixes. Update `VERSION`, both `Resources/*Info.plist` versions, the settings fallback, the badge and [CHANGELOG.md](CHANGELOG.md); increment the build number. `check-version.sh` checks consistency before packaging. Releases use Git tags named `vX.Y.Z`.

[MIT](LICENSE) · [Русская документация](README.md) · [Changelog](CHANGELOG.md)
