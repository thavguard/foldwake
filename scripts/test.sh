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

swift --version
swift test
