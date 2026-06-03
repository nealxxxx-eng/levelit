#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SOURCE="$ROOT_DIR/scripts/pre-commit-levelit.sh"

install_hook() {
  local repo_dir="$1"
  local hook_path
  hook_path="$(git -C "$repo_dir" rev-parse --absolute-git-dir)/hooks/pre-commit"
  mkdir -p "$(dirname "$hook_path")"

  if [[ -e "$hook_path" && ! -L "$hook_path" ]]; then
    local backup="${hook_path}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$hook_path" "$backup"
    echo "Backed up existing hook: $backup"
  fi

  ln -sf "$HOOK_SOURCE" "$hook_path"
  chmod +x "$HOOK_SOURCE" "$hook_path"
  echo "Installed pre-commit hook for $repo_dir -> $hook_path"
}

install_hook "$ROOT_DIR"

if [[ -d "$ROOT_DIR/LevelIt/.git" ]]; then
  install_hook "$ROOT_DIR/LevelIt"
fi

cat <<'EOF'

Pre-commit hooks installed.

Every git commit in the root repo or LevelIt subrepo now runs:
  scripts/verify-three-gates.sh --skip-build

Before pushing or opening a release PR, still run the full gate manually:
  scripts/verify-three-gates.sh

Emergency bypass:
  LEVELIT_SKIP_PRECOMMIT=1 git commit ...
EOF
