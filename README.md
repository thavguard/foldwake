# Foldwake

Native macOS menu bar app that keeps a Mac awake, including lid-close workflows, while still allowing the display to sleep.

## Features

- Menu bar only: no Dock icon, no main window.
- `Block Mac Sleep`: prevents idle sleep, system sleep, and lid-triggered sleep.
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

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development

Regenerate the app icon when changing the icon source:

```bash
./scripts/check-icon.sh
```

## License

MIT
