# Contributing to SimFlutDock

SimFlutDock is a native macOS app built with SwiftUI and AppKit. Use macOS 14 or later and full Xcode. The regular test suite uses isolated fixtures and does not require Flutter or a running simulator.

## Build and check

Run the same checks used by CI:

```bash
./scripts/check.sh
```

This validates versions, shell syntax and property lists, builds the Swift package, runs its tests and the Python 3 MCP protocol tests, and checks panel presentation. CI also builds the Xcode project. To build it locally without signing:

```bash
xcodebuild -project SimFlutDock.xcodeproj -scheme SimFlutDock \
  -configuration Debug -derivedDataPath .build/xcode \
  CODE_SIGNING_ALLOWED=NO build
```

Build a usable app bundle with `./scripts/build-app.sh`. Signing and universal DMG packaging are handled by the existing build scripts; release publication is a separate workflow.

## Source layout

- `Sources/SimFlutDockCore`: project persistence, launch configuration, Flutter processes, machine protocol, Dart console, simulator tools, localization, and update verification.
- `Sources/SimFlutDock`: application lifecycle and model, AppKit panel coordination, window tracking, update UI, and separate SwiftUI view files.
- `Sources/SimFlutDockHelper`: login helper that opens the parent app when Simulator or Device Hub launches.
- `Tests/SimFlutDockCoreTests`: unit tests, process fixtures, update installation tests, and the opt-in Flutter integration test.
- `Tests/PanelPresentation`: isolated AppKit panel checks.

UI state and session coordination belong to the main actor. Short-lived commands go through `ToolRunner`, with bounded output, cancellation, and timeouts. Each Flutter session owns its process and protocol client; asynchronous callbacks must respect its generation and current state. Preserve unreadable project archives until the user explicitly recovers them.

SwiftPM discovers source files automatically. When adding or moving production Swift files, also update `SimFlutDock.xcodeproj/project.pbxproj` and build both entry points.

## Formatting

Use the repository's `.swift-format` configuration with the formatter bundled in Xcode:

```bash
xcrun swift-format format --in-place --recursive Sources Tests Package.swift
```

Keep behavior changes separate from formatting where practical. Add focused regression tests for lifecycle, persistence, and protocol changes. Add user-facing English keys and Russian translations to `Localization.swift`.

## Real Flutter integration

This test starts apps and edits a generated probe, so it is opt-in. Install Flutter and iOS Simulator runtimes, then generate the two disposable projects:

```bash
./scripts/create-probes.sh
```

Boot two iOS simulators in Xcode, then run:

```bash
FLUTTIOS_INTEGRATION=1 xcrun swift test --filter IntegrationTests
```

Generated projects and logs stay under `.build/integration`. The test exercises two independent sessions, hot reload, hot restart, compile-error recovery, launch conflicts, and shutdown.

## Before submitting

Run `./scripts/check.sh`, describe the behavior changed and validation performed, and follow [SECURITY.md](SECURITY.md) for logs, screenshots, credentials, and release material. Never include a real project's private data in fixtures or screenshots.
