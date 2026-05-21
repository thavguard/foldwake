# Foldwake

Native macOS menu bar app that disables system sleep through a privileged helper while still allowing the display to sleep.

## Features

- Menu bar only: no Dock icon, no main window.
- `Block Mac Sleep`: prevents idle/system sleep and asks the privileged helper to set `pmset -a disablesleep 1`.
- `SleepDisabled` diagnostics: shows the actual `pmset -g` state instead of relying on saved preferences.
- `Battery Guard`: restores normal sleep when the Mac is on battery and reaches the low-battery threshold.
- `Open at Login`: installs a user LaunchAgent for the built app.
- Privileged helper is bundled and managed through `SMAppService`, so toggling lid sleep does not require repeated password prompts after approval.

## Menu Shortcuts

- `Command-B`: toggle `Block Mac Sleep`.
- `Command-G`: toggle `Battery Guard`.
- `Command-L`: toggle `Open at Login`.
- `Command-R`: restore normal sleep.
- `Command-I`: install or repair the helper.
- `Command-,`: open Login Items settings.
- `Command-Q`: quit Foldwake.

## Requirements

- macOS 14 or newer.
- Swift 6.3.x. This repository includes `.swift-version` set to `6.3.2`.
- For local development, install Swift through Swiftly:

```bash
swiftly install 6.3.2 --use
source "$HOME/.swiftly/env.sh"
```

## Build

```bash
git clone https://github.com/thavguard/foldwake.git
cd foldwake
./scripts/build-app.sh
open dist/Foldwake.app
```

The build script prefers `~/.swiftly/bin` when Swiftly is installed, so it uses Swift 6.3.x instead of the older `/usr/bin/swift` from Xcode.

## Test

```bash
./scripts/test.sh
```

## Helper Approval

The app bundles `FoldwakeHelper` as:

```text
Foldwake.app/Contents/Library/LaunchDaemons/io.github.thavguard.foldwake.helper.plist
```

Use `Install or Repair Helper...` from the menu after building the app. macOS may require approval in System Settings > Login Items. After approval, `Block Mac Sleep` talks to the helper over XPC.

## Lid-Close Limits

Foldwake does not require an external display. When `Block Mac Sleep` is enabled, it uses the helper to set the system `pmset disablesleep` flag and then verifies that macOS reports `SleepDisabled = 1`.

macOS can still enforce hardware, firmware, thermal, battery, security, or OS-version-specific sleep behavior. Foldwake treats `SleepDisabled` as the source of truth it can verify through public system tools; if macOS refuses to apply that state, Foldwake reports the failure instead of showing a fake enabled state.

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development

Validate app icon generation after changing the icon source:

```bash
./scripts/check-icon.sh
```

## License

MIT
