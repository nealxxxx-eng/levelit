#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "${LEVELIT_SKIP_PRECOMMIT:-0}" == "1" ]]; then
  echo "LEVELIT_SKIP_PRECOMMIT=1 set; skipping LevelIt pre-commit gates."
  exit 0
fi

if [[ ! -x "$ROOT_DIR/scripts/verify-three-gates.sh" ]]; then
  echo "Missing executable: $ROOT_DIR/scripts/verify-three-gates.sh" >&2
  exit 1
fi

echo "Running LevelIt pre-commit gates: swift test + xcodebuild -list"
echo "For the full pre-submit check, run: scripts/verify-three-gates.sh"

"$ROOT_DIR/scripts/verify-three-gates.sh" --skip-build
