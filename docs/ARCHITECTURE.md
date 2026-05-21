# Foldwake Architecture

Foldwake is a native macOS menu bar app with one privileged helper.

## Targets

- `FoldwakeCore`: pure Swift policy, formatting, identifiers, and plist generation. This target has unit tests and no AppKit, IOKit, ServiceManagement, or Security dependency.
- `Foldwake`: menu bar app. It owns the `NSStatusItem`, user defaults, IOKit power assertions, battery/lid monitoring, and `SMAppService` registration.
- `FoldwakeHelper`: privileged LaunchDaemon reached over XPC. It validates the calling app by bundle identifier, non-empty team identifier, certificate chain, and code-signing validity before running `pmset -a disablesleep`.

## Power Model

`Foldwake` uses two mechanisms because macOS exposes two different surfaces:

- IOKit power assertions prevent idle/system sleep while the app process is alive.
- The helper toggles the system `pmset disablesleep` setting for lid-close behavior.

The app reconciles the expected state periodically because `pmset` can be changed outside Foldwake.

The app does not require an external display before enabling the lid-close path. The privileged helper writes `pmset -a disablesleep` and immediately reads `pmset -g`; a requested state is only accepted when the observed `SleepDisabled` value matches it.

## Security Boundaries

The helper only accepts XPC clients with the expected bundle identifier, the same non-ad-hoc signing identity, and valid signed resources. The helper does not expose arbitrary command execution; it only toggles one `pmset` setting.

Bundle and helper identifiers are centralized in `FoldwakeCore.AppIdentity` to avoid mismatched LaunchDaemon, XPC, signing, and login item names.

The generated LaunchDaemon plist includes a `SpawnConstraint` tied to the signed helper's cdhash. The plist is generated during packaging so stale source plist variants cannot drift from the actual signed helper.
