# Repository Guidelines

## Project Structure & Module Organization
StikDebug is an Xcode project targeting iOS 17.4+. The SwiftUI app lives under `StikJIT/` with `Views/` for UI stacks, `Utilities/` for helpers, and `idevice/` bridging C assets. The loopback VPN extension is in `TunnelProv/`, and the widget extension assets reside in `DebugWidget/`. Localized strings live in `StikJIT/*.lproj`. Shared resources such as app icons and screenshots are in `assets/`. Tests sit in `StikJITTests/` and `StikJITUITests/`.

## Build, Test, and Development Commands
- `xed .` opens the workspace in Xcode; prefer the `StikDebug` scheme.
- `xcodebuild -project StikDebug.xcodeproj -scheme StikDebug -configuration Debug build` performs a local build without signing.
- `xcodebuild test -project StikDebug.xcodeproj -scheme StikDebug -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.4'` runs unit + UI suites.
- `NAME=StikDebug make package` mirrors CI packaging and emits `packages/StikDebug.ipa`.
- `python3 update_json.py` refreshes `repo.json` and `version.txt` metadata before publishing.

## Coding Style & Naming Conventions
Swift code follows standard SwiftFormat conventions: four-space indentation, 100-character soft wraps, and `// MARK:` to partition files. Name SwiftUI views with the `*View` suffix, helper types in `Utilities` with nouns, and JavaScript helpers (`JSSupport/*.js`) using camelCase functions. Keep localized keys kebab-case and mirrored across `.lproj` catalogs. Maintain entitlements in their existing plist structure.

## Testing Guidelines
Prefer the `Testing` module in `StikJITTests` for async logic and `XCTest` in `StikJITUITests` for UI flows. Co-locate new tests next to the feature module with the suffix `Tests`. Use descriptive `test…` method names and assert network-sensitive code via dependency injection. Aim to keep simulator coverage green (`xcodebuild test` above) before submitting.

## Commit & Pull Request Guidelines
Commits use short, imperative summaries (`Fix localized error log keys`). Squash noisy work-in-progress logs. Every PR should include a clear description, linked issue (if any), and test notes (`xcodebuild test` or manual steps). Attach screenshots or screen recordings whenever UI changes `Views/` or `DebugWidget/`. Call out entitlement or provisioning adjustments explicitly.

## Security & Configuration Tips
Treat `TunnelProv.entitlements` and `DebugWidgetExtension.entitlements` as security-critical; do not broaden capabilities without review. Validate that `repo.json` stays in sync with the App Store metadata, and never commit real certificates or provisioning profiles. When shipping JavaScript helpers to `idevice`, regenerate minified assets through trusted tooling and review diffs carefully.
