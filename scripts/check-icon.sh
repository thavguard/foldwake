#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$HOME/.swiftly/env.sh" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.swiftly/env.sh"
  export PATH="$HOME/.swiftly/bin:$PATH"
  hash -r
fi

if [[ ! -f Resources/IconSource/foldwake-hinge-halo.png ]]; then
  printf 'error: missing Resources/IconSource/foldwake-hinge-halo.png\\n' >&2
  exit 1
fi

swiftc scripts/generate-icon.swift -framework AppKit -o .build/generate-icon
.build/generate-icon >/dev/null

if [[ ! -f Resources/AppIcon.icns ]]; then
  printf 'error: icon generation did not produce Resources/AppIcon.icns\\n' >&2
  exit 1
fi

iconutil -c iconset Resources/AppIcon.icns -o .build/AppIcon.verify.iconset >/dev/null
test -f .build/AppIcon.verify.iconset/icon_512x512@2x.png
