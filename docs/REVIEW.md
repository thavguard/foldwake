# Review Notes

## Current Status

- Build target is Swift tools 6.3 and the project includes `.swift-version` pinned to Swift 6.3.2.
- The app has been renamed to `Foldwake` with public bundle identifiers under `io.github.thavguard.foldwake`.
- Pure logic has been extracted into `FoldwakeCore` and covered by unit tests.
- The app bundle includes `CFBundleIconFile`; `Resources/AppIcon.icns` is generated from the tracked high-quality source PNG during packaging.
- Build artifacts are excluded through `.gitignore`; source, docs, tests, icon, scripts, and CI config are ready to commit.
- The checked-in static LaunchDaemon plist was removed; packaging now generates the only helper plist and includes the cdhash `SpawnConstraint`.
- Ad-hoc signing is no longer a silent fallback. It must be explicitly enabled for non-runtime CI packaging checks.

## Important Constraints

- Lid-close wakefulness is not available as a normal non-privileged macOS app API, so the privileged helper is intentional.
- Foldwake no longer gates lid sleep blocking on external-display presence. The helper writes `pmset disablesleep` and verifies the resulting `SleepDisabled` state before reporting success.
- The helper changes a system-wide setting. Users should have a visible menu action to restore normal sleep, and the app should keep reconciling drift from manual `pmset` changes.
- Distribution outside local development will require a real Developer ID signing identity and notarization before most users can run it without Gatekeeper friction.
- The helper still uses the public `NSXPCConnection.processIdentifier` surface for peer lookup. A private audit-token implementation was not added; revisit this before claiming hardened production release security.

## Remaining Product Work

- Add a signed release workflow after the Developer ID certificate and notarization credentials are available.
- Add a small screenshot or GIF to the README after the first signed build is produced.
