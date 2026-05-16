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

before="$(mktemp)"
after="$(mktemp)"
trap 'rm -f "$before" "$after"' EXIT

shasum -a 256 Resources/AppIcon.icns > "$before"
swiftc scripts/generate-icon.swift -framework AppKit -o .build/generate-icon
.build/generate-icon >/dev/null
shasum -a 256 Resources/AppIcon.icns > "$after"

if ! cmp -s "$before" "$after"; then
  printf 'error: Resources/AppIcon.icns is out of date. Run scripts/check-icon.sh and commit the regenerated icon.\\n' >&2
  exit 1
fi
